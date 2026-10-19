package com.swarnos.search.service;

import com.swarnos.common.money.Decimals;
import com.swarnos.inventory.domain.ItemCriteria;
import com.swarnos.inventory.domain.ItemListing;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.service.ItemService;
import com.swarnos.rates.domain.RateLine;
import com.swarnos.rates.service.RateService;
import com.swarnos.repair.service.RepairService;
import com.swarnos.search.domain.QueryInterpreter;
import com.swarnos.search.domain.Rupees;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.service.MasterDataService;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import org.springframework.stereotype.Service;

/**
 * Voice and natural-language search (BRD §13). The interpreted filters are
 * always returned with the results so the user can see and correct them.
 */
@Service
public class SearchService {
    private static final int MAX_RESULTS = 100;

    private final ItemService items;
    private final RateService rates;
    private final RepairService repairs;
    private final MasterDataService masters;
    private final QueryInterpreter interpreter = new QueryInterpreter();

    public SearchService(ItemService items, RateService rates, RepairService repairs, MasterDataService masters) {
        this.items = items;
        this.rates = rates;
        this.repairs = repairs;
        this.masters = masters;
    }

    public record Answer(String query, String intent, List<String> chips, QueryInterpreter.Interpretation filters, String answer,
                         List<ItemService.PricedItem> results, List<RepairService.ListedJob> repairs, Integer count,
                         BigDecimal totalValue, BigDecimal totalNetWt) {}

    public Answer ask(String text) {
        List<QueryInterpreter.Category> categories = masters.activeCategories().stream()
                .map(c -> new QueryInterpreter.Category(c.id(), c.code(), c.name(), c.family().name(),
                        c.metal() == null ? null : c.metal().name()))
                .toList();
        QueryInterpreter.Interpretation in = interpreter.interpret(text, categories);
        List<String> chips = chips(in, categories);
        return switch (in.intent()) {
            case "TAG" -> tag(text, in, chips);
            case "RATE" -> rate(text, in, chips);
            case "REPAIR" -> repair(text, in, chips);
            default -> stock(text, in, chips);
        };
    }

    private Answer tag(String text, QueryInterpreter.Interpretation in, List<String> chips) {
        Optional<ItemService.ItemDetail> found = items.findByCode(in.tag());
        if (found.isEmpty() && in.tag().matches("\\d+")) found = items.findByCodeSuffix(in.tag());
        String answer = found.map(d -> "Tag " + d.item().listing().item().tagCode() + ": " + d.item().listing().item().name()
                + " (" + d.item().listing().item().status() + ")").orElse("No item with tag " + in.tag());
        return new Answer(text, in.intent(), chips, in, answer, found.map(d -> List.of(d.item())).orElse(List.of()), null, null,
                null, null);
    }

    private Answer rate(String text, QueryInterpreter.Interpretation in, List<String> chips) {
        String answer = rates.approvedToday().map(set -> {
            List<String> parts = new ArrayList<>();
            for (RateLine l : rates.get(set.id()).lines()) {
                if (in.purity() != null && !in.purity().equals(l.purityCode())) continue;
                if (in.metal() != null && !in.metal().equals(l.metal().name())) continue;
                parts.add(l.metal() + " " + l.purityCode() + ": " + Rupees.format(l.ratePerGram()) + "/g");
            }
            return "Today's approved rate - " + String.join(", ", parts);
        }).orElse("Today's rate is not approved yet.");
        return new Answer(text, in.intent(), chips, in, answer, List.of(), null, null, null, null);
    }

    private Answer repair(String text, QueryInterpreter.Interpretation in, List<String> chips) {
        String words = in.normalized().replaceAll("\\b(repair|repairs|ready|for|of|ji|show|ka|ki|ke|status|job|jobs|customer)\\b", " ")
                .trim();
        List<RepairService.ListedJob> jobs = repairs.list(in.normalized().contains("ready") ? "READY" : "OPEN",
                words.isBlank() ? null : words.split("\\s+")[0]);
        return new Answer(text, in.intent(), chips, in, jobs.size() + " repair job(s) found.", List.of(), jobs, null, null, null);
    }

    private Answer stock(String text, QueryInterpreter.Interpretation in, List<String> chips) {
        ItemCriteria criteria = new ItemCriteria(null, ItemStatus.IN_STOCK, null, null,
                in.metal() == null ? null : Metal.valueOf(in.metal()), in.purity(), null, in.minWt(), in.maxWt(), in.stoneType(), null);
        List<ItemService.PricedItem> results = new ArrayList<>();
        for (ItemService.PricedItem p : items.search(new ItemService.ItemSearch(criteria, in.minPrice(), in.maxPrice(), 5000))) {
            ItemListing l = p.listing();
            if (!in.categoryIds().isEmpty() && !in.categoryIds().contains(l.item().categoryId())) continue;
            if (in.categoryIds().isEmpty() && !in.typeWords().isEmpty()) continue;   // asked for a type the shop does not stock
            if (!in.families().isEmpty() && !in.families().contains(l.family().name())) continue;
            results.add(p);
        }
        Comparator<ItemService.PricedItem> byPrice = Comparator.comparing(ItemService.PricedItem::total,
                Comparator.nullsLast(Comparator.naturalOrder()));
        results.sort(in.minPrice() != null && in.maxPrice() == null ? byPrice.reversed() : byPrice);
        BigDecimal value = results.stream().map(ItemService.PricedItem::total).filter(v -> v != null).reduce(Decimals.ZERO, BigDecimal::add);
        BigDecimal weight = results.stream().map(p -> p.listing().item().netWt()).reduce(Decimals.ZERO, BigDecimal::add);
        String answer = results.size() + " piece(s) in stock" + (results.isEmpty() ? "" : ", net " + Decimals.round(weight)
                + " g, worth " + Rupees.format(value) + " at today's rate") + ".";
        return new Answer(text, in.intent(), chips, in, answer, results.subList(0, Math.min(MAX_RESULTS, results.size())), null,
                results.size(), Decimals.round(value), Decimals.round(weight));
    }

    private static List<String> chips(QueryInterpreter.Interpretation in, List<QueryInterpreter.Category> categories) {
        List<String> chips = new ArrayList<>();
        if (in.tag() != null) chips.add("Tag: " + in.tag());
        if (!in.families().isEmpty()) {
            chips.add("Type: " + String.join(", ", in.families()).toLowerCase().replace('_', ' '));
        }
        if (in.metal() != null) chips.add("Metal: " + in.metal().toLowerCase());
        if (in.purity() != null) chips.add("Purity: " + in.purity());
        if (!in.categoryIds().isEmpty()) {
            chips.add("Category: " + String.join(", ", categories.stream().filter(c -> in.categoryIds().contains(c.id()))
                    .map(QueryInterpreter.Category::name).toList()));
        } else if (!in.typeWords().isEmpty()) {
            chips.add("Item: " + String.join(", ", in.typeWords()));
        }
        if (in.minPrice() != null) chips.add("Price ≥ " + Rupees.format(in.minPrice()));
        if (in.maxPrice() != null) chips.add("Price ≤ " + Rupees.format(in.maxPrice()));
        if (in.minWt() != null) chips.add("Net wt ≥ " + Decimals.round(in.minWt()) + " g");
        if (in.maxWt() != null) chips.add("Net wt ≤ " + Decimals.round(in.maxWt()) + " g");
        if (in.intent().equals("SEARCH") || in.intent().equals("COUNT")) chips.add("In stock");
        return chips;
    }
}
