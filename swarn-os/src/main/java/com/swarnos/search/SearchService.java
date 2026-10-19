package com.swarnos.search;

import com.swarnos.common.Db;
import com.swarnos.common.Num;
import com.swarnos.common.Rows;
import com.swarnos.items.ItemService;
import com.swarnos.rates.RateService;
import com.swarnos.repair.RepairService;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;

/**
 * Voice and natural-language search (BRD §13). The interpreted filters are
 * always returned with the results so the user can see and correct them.
 */
@Service
public class SearchService {
    private final Db db;
    private final ItemService items;
    private final RateService rates;
    private final RepairService repairs;
    private final QueryInterpreter interpreter = new QueryInterpreter();

    public SearchService(Db db, ItemService items, RateService rates, RepairService repairs) {
        this.db = db;
        this.items = items;
        this.rates = rates;
        this.repairs = repairs;
    }

    public Map<String, Object> ask(String text) {
        List<QueryInterpreter.Category> cats = db.rows("SELECT * FROM category WHERE active = TRUE").stream()
                .map(c -> new QueryInterpreter.Category(Rows.id(c), (String) c.get("code"), (String) c.get("name"),
                        (String) c.get("family"), (String) c.get("metal")))
                .toList();
        QueryInterpreter.Interpretation in = interpreter.interpret(text, cats);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("query", text);
        out.put("intent", in.intent());
        out.put("chips", chips(in, cats));
        out.put("filters", in);

        switch (in.intent()) {
            case "TAG" -> {
                Optional<Map<String, Object>> item = items.findByCode(in.tag());
                if (item.isEmpty() && in.tag().matches("\\d+")) {
                    item = db.opt("SELECT id FROM item WHERE tag_code LIKE ? ORDER BY id DESC", "%" + in.tag())
                            .map(r -> items.get(Rows.id(r)));
                }
                out.put("results", item.map(List::of).orElse(List.of()));
                out.put("answer", item.isPresent() ? "Tag " + item.get().get("tag_code") + ": " + item.get().get("name")
                        + " (" + item.get().get("status") + ")" : "No item with tag " + in.tag());
                return out;
            }
            case "RATE" -> {
                Optional<Map<String, Object>> rs = rates.approvedToday();
                if (rs.isEmpty()) {
                    out.put("answer", "Today's rate is not approved yet.");
                } else {
                    Map<String, Object> set = rates.get(Rows.id(rs.get()));
                    List<?> lines = (List<?>) set.get("lines");
                    List<String> parts = new ArrayList<>();
                    for (Object o : lines) {
                        Map<?, ?> l = (Map<?, ?>) o;
                        if (in.purity() != null && !in.purity().equals(l.get("purity_code"))) continue;
                        if (in.metal() != null && !in.metal().equals(l.get("metal"))) continue;
                        parts.add(l.get("metal") + " " + l.get("purity_code") + ": " + inr((BigDecimal) l.get("rate_per_gram")) + "/g");
                    }
                    out.put("answer", "Today's approved rate - " + String.join(", ", parts));
                }
                out.put("results", List.of());
                return out;
            }
            case "REPAIR" -> {
                String words = in.normalized().replaceAll("\\b(repair|repairs|ready|for|of|ji|show|ka|ki|ke|status|job|jobs|customer)\\b", " ").trim();
                List<Map<String, Object>> jobs = repairs.list(in.normalized().contains("ready") ? "READY" : "OPEN",
                        words.isBlank() ? null : words.split("\\s+")[0]);
                out.put("repairs", jobs);
                out.put("results", List.of());
                out.put("answer", jobs.size() + " repair job(s) found.");
                return out;
            }
            default -> { }
        }

        List<Map<String, Object>> found = items.search(new ItemService.ItemFilter(null, "IN_STOCK", null, null, in.metal(),
                in.purity(), null, in.minWt(), in.maxWt(), in.minPrice(), in.maxPrice(), null, in.stoneType(), 5000));
        List<Map<String, Object>> results = new ArrayList<>();
        BigDecimal value = Num.ZERO, weight = Num.ZERO;
        for (Map<String, Object> it : found) {
            if (!in.categoryIds().isEmpty() && !in.categoryIds().contains(Rows.id(it.get("category_id")))) continue;
            if (in.categoryIds().isEmpty() && !in.typeWords().isEmpty()) continue;   // asked for a type we do not stock
            if (!in.families().isEmpty() && !in.families().contains((String) it.get("family"))) continue;
            results.add(it);
            if (it.get("price") != null) value = value.add((BigDecimal) it.get("price"));
            weight = weight.add(Num.of(it.get("net_wt")));
        }
        results.sort((a, b) -> {
            BigDecimal pa = (BigDecimal) a.get("price"), pb = (BigDecimal) b.get("price");
            if (pa == null || pb == null) return 0;
            return in.minPrice() != null && in.maxPrice() == null ? pb.compareTo(pa) : pa.compareTo(pb);
        });
        out.put("count", results.size());
        out.put("total_value", Num.r(value));
        out.put("total_net_wt", Num.r(weight));
        out.put("results", results.size() > 100 ? results.subList(0, 100) : results);
        out.put("answer", results.size() + " piece(s) in stock" + (results.isEmpty() ? "" : ", net " + Num.r(weight)
                + " g, worth " + inr(value) + " at today's rate") + ".");
        return out;
    }

    private static List<String> chips(QueryInterpreter.Interpretation in, List<QueryInterpreter.Category> cats) {
        List<String> chips = new ArrayList<>();
        if (in.tag() != null) chips.add("Tag: " + in.tag());
        if (!in.families().isEmpty()) chips.add("Type: " + String.join(", ", in.families()).toLowerCase().replace('_', ' '));
        if (in.metal() != null) chips.add("Metal: " + in.metal().toLowerCase());
        if (in.purity() != null) chips.add("Purity: " + in.purity());
        if (!in.categoryIds().isEmpty()) {
            chips.add("Category: " + String.join(", ", cats.stream().filter(c -> in.categoryIds().contains(c.id())).map(QueryInterpreter.Category::name).toList()));
        } else if (!in.typeWords().isEmpty()) {
            chips.add("Item: " + String.join(", ", in.typeWords()));
        }
        if (in.minPrice() != null) chips.add("Price ≥ " + inr(in.minPrice()));
        if (in.maxPrice() != null) chips.add("Price ≤ " + inr(in.maxPrice()));
        if (in.minWt() != null) chips.add("Net wt ≥ " + Num.r(in.minWt()) + " g");
        if (in.maxWt() != null) chips.add("Net wt ≤ " + Num.r(in.maxWt()) + " g");
        if (in.intent().equals("SEARCH") || in.intent().equals("COUNT")) chips.add("In stock");
        return chips;
    }

    /** Rupees with Indian digit grouping, e.g. 1,15,677. */
    static String inr(BigDecimal v) {
        String digits = v.setScale(0, java.math.RoundingMode.HALF_UP).abs().toPlainString();
        StringBuilder out = new StringBuilder();
        int n = digits.length();
        for (int i = 0; i < n; i++) {
            out.append(digits.charAt(i));
            int left = n - i - 1;
            if (left > 0 && (left == 3 || (left > 3 && (left - 3) % 2 == 0))) out.append(',');
        }
        return (v.signum() < 0 ? "-₹" : "₹") + out;
    }
}
