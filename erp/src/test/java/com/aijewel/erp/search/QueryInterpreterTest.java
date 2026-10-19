package com.aijewel.erp.search;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.Test;

class QueryInterpreterTest {
    private final QueryInterpreter q = new QueryInterpreter();
    private final List<QueryInterpreter.Category> cats = List.of(
            new QueryInterpreter.Category(1, "GCH", "Gold Chain", "GOLD", "GOLD"),
            new QueryInterpreter.Category(2, "LGR", "Ladies Gold Ring", "GOLD", "GOLD"),
            new QueryInterpreter.Category(3, "GE", "Gold Earring", "GOLD", "GOLD"),
            new QueryInterpreter.Category(4, "DRG", "Diamond Ring", "DIAMOND", "GOLD"),
            new QueryInterpreter.Category(5, "SAN", "Silver Anklet (Payal)", "SILVER_ORNAMENT", "SILVER"),
            new QueryInterpreter.Category(6, "STR", "Silver Toe Ring", "SILVER_ORNAMENT", "SILVER"),
            new QueryInterpreter.Category(7, "PTC", "Platinum Chain", "PLATINUM", "PLATINUM"));

    @Test
    void diamondBelowPrice() {
        var i = q.interpret("diamond jewellery below 50000", cats);
        assertThat(i.intent()).isEqualTo("SEARCH");
        assertThat(i.families()).containsExactly("DIAMOND");
        assertThat(i.maxPrice()).isEqualByComparingTo("50000");
        assertThat(i.minPrice()).isNull();
    }

    @Test
    void purityTypeAndWeightRange() {
        var i = q.interpret("22 carat gold chains between 20 and 30 grams", cats);
        assertThat(i.purity()).isEqualTo("22K");
        assertThat(i.metal()).isEqualTo("GOLD");
        assertThat(i.categoryIds()).containsExactly(1L);
        assertThat(i.minWt()).isEqualByComparingTo("20");
        assertThat(i.maxWt()).isEqualByComparingTo("30");
        assertThat(i.maxPrice()).isNull();
    }

    @Test
    void hinglishRingUnderFiftyThousand() {
        var i = q.interpret("sone ki angoothi 50 hazar se kam", cats);
        assertThat(i.metal()).isEqualTo("GOLD");
        assertThat(i.categoryIds()).containsExactly(2L);   // not earrings, not diamond or toe rings
        assertThat(i.maxPrice()).isEqualByComparingTo("50000");
    }

    @Test
    void devanagariDiamondRing() {
        var i = q.interpret("हीरे की अंगूठी 1 लाख से कम", cats);
        assertThat(i.families()).contains("DIAMOND");
        assertThat(i.categoryIds()).containsExactly(4L);
        assertThat(i.maxPrice()).isEqualByComparingTo("100000");
    }

    @Test
    void countSilverAnklets() {
        var i = q.interpret("how many silver anklets are in stock", cats);
        assertThat(i.intent()).isEqualTo("COUNT");
        assertThat(i.categoryIds()).containsExactly(5L);
    }

    @Test
    void tagLookupAsDictated() {
        assertThat(q.interpret("show tag T000012", cats).tag()).isEqualTo("T000012");
        assertThat(q.interpret("tag number t 000045", cats).tag()).isEqualTo("T000045");
        assertThat(q.interpret("show tag 10452", cats).intent()).isEqualTo("TAG");
    }

    @Test
    void rateQuestion() {
        var i = q.interpret("aaj ka 22 carat rate kya hai", cats);
        assertThat(i.intent()).isEqualTo("RATE");
        assertThat(i.purity()).isEqualTo("22K");
    }

    @Test
    void priceAboveAndLakhScaling() {
        var i = q.interpret("gold necklace above 1.5 lakh", cats);
        assertThat(i.minPrice()).isEqualByComparingTo("150000");
        var k = q.interpret("platinum chain under 40k", cats);
        assertThat(k.maxPrice()).isEqualByComparingTo("40000");
        assertThat(k.categoryIds()).containsExactly(7L);
    }

    @Test
    void hallmarkNumberMeansPurity() {
        assertThat(q.interpret("916 chains", cats).purity()).isEqualTo("22K");
    }
}
