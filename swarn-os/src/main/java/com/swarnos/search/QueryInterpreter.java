package com.swarnos.search;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Turns a spoken or typed request such as "diamond jewellery below 50000",
 * "22 carat gold chains between 20 and 30 grams" or "sone ki angoothi 50 hazar
 * se kam" into structured filters (BRD §13.1). Pure Java with no I/O, so it
 * can be swapped for an LLM-backed interpreter behind the same output.
 */
public class QueryInterpreter {

    public record Category(long id, String code, String name, String family, String metal) {}

    public record Interpretation(
            String intent,                 // SEARCH | COUNT | RATE | REPAIR | TAG
            String tag,
            String metal,
            Set<String> families,
            String purity,
            Set<Long> categoryIds,
            List<String> typeWords,
            BigDecimal minPrice,
            BigDecimal maxPrice,
            BigDecimal minWt,
            BigDecimal maxWt,
            String stoneType,
            String text,
            String normalized) {}

    // Spoken Hindi (Devanagari) and Hinglish words mapped to the English words the rules below understand.
    private static final Map<String, String> SYNONYMS = new LinkedHashMap<>();

    static {
        String[][] pairs = {
                {"हीरे", "diamond"}, {"हीरा", "diamond"}, {"डायमंड", "diamond"}, {"heere", "diamond"}, {"heera", "diamond"},
                {"hira", "diamond"}, {"सोने", "gold"}, {"सोना", "gold"}, {"गोल्ड", "gold"}, {"sone", "gold"}, {"sona", "gold"},
                {"चांदी", "silver"}, {"चाँदी", "silver"}, {"सिल्वर", "silver"}, {"chandi", "silver"}, {"chaandi", "silver"},
                {"प्लैटिनम", "platinum"}, {"अंगूठी", "ring"}, {"अँगूठी", "ring"}, {"angoothi", "ring"}, {"anguthi", "ring"},
                {"अंगूठियां", "ring"}, {"चेन", "chain"}, {"zanjeer", "chain"}, {"कंगन", "bangle"}, {"चूड़ी", "bangle"},
                {"chudi", "bangle"}, {"choodi", "bangle"}, {"kangan", "bangle"}, {"हार", "necklace"}, {"haar", "necklace"},
                {"झुमके", "earring"}, {"झुमका", "earring"}, {"jhumka", "earring"}, {"jhumke", "earring"}, {"baali", "earring"},
                {"bali", "earring"}, {"tops", "earring"}, {"कान", "earring"}, {"पायल", "anklet"}, {"payal", "anklet"},
                {"paayal", "anklet"}, {"बिछिया", "toe ring"}, {"bichhiya", "toe ring"}, {"bichiya", "toe ring"},
                {"मंगलसूत्र", "mangalsutra"}, {"लॉकेट", "pendant"}, {"locket", "pendant"}, {"सिक्का", "coin"}, {"sikka", "coin"},
                {"घड़ी", "watch"}, {"ghadi", "watch"}, {"तोहफा", "gift"}, {"उपहार", "gift"},
                {"कैरेट", "carat"}, {"कैरट", "carat"}, {"ग्राम", "gram"}, {"हज़ार", "thousand"}, {"हजार", "thousand"},
                {"hazar", "thousand"}, {"hazaar", "thousand"}, {"hajar", "thousand"}, {"लाख", "lakh"}, {"lac", "lakh"},
                {"से कम", "below"}, {"se kam", "below"}, {"से नीचे", "below"}, {"se neeche", "below"}, {"tak", "below"},
                {"तक", "below"}, {"ke andar", "below"}, {"से ज्यादा", "above"}, {"से ज़्यादा", "above"}, {"से अधिक", "above"},
                {"se zyada", "above"}, {"se jyada", "above"}, {"se upar", "above"}, {"से ऊपर", "above"}, {"ke beech", "between"},
                {"के बीच", "between"}, {"कितने", "how many"}, {"कितनी", "how many"}, {"kitne", "how many"}, {"kitni", "how many"},
                {"रेट", "rate"}, {"भाव", "rate"}, {"bhav", "rate"}, {"bhaav", "rate"}, {"टैग", "tag"}, {"नंबर", "number"},
                {"दिखाओ", "show"}, {"dikhao", "show"}, {"रिपेयर", "repair"}, {"मरम्मत", "repair"}, {"aur", "and"}, {"और", "and"},
                {"rupaye", "rupees"}, {"रुपये", "rupees"}, {"रुपए", "rupees"}, {"jewellery", "jewelry"}
        };
        for (String[] p : pairs) SYNONYMS.put(p[0], p[1]);
    }

    // Words for item types, matched against category names. Longer phrases first.
    private static final String[][] TYPE_WORDS = {
            {"toe ring", "toe ring"}, {"necklace set", "necklace"}, {"pendant set", "pendant set"}, {"earring", "earring"},
            {"ear ring", "earring"}, {"mangalsutra", "mangalsutra"}, {"necklace", "necklace"}, {"pendant", "pendant"},
            {"bangle", "bangle"}, {"kada", "bangle"}, {"bracelet", "bracelet"}, {"anklet", "anklet"}, {"chain", "chain"},
            {"ring", "ring"}, {"coin", "coin"}, {"utensil", "utensil"}, {"watch", "watch"}, {"gift", "gift"}};

    private static final String NUM = "(\\d+(?:\\.\\d+)?)";
    private static final Pattern TAG = Pattern.compile("\\b(?:tag|tag number|tag no|item|code|number)\\s*(?:number|no)?\\s*#?\\s*([a-z]{0,3}\\d{2,}[a-z0-9]*)\\b");
    private static final Pattern BARE_TAG = Pattern.compile("^\\s*([a-z]{1,3}\\d{3,})\\s*$");
    private static final Pattern PURITY = Pattern.compile("\\b(24|22|20|18|14|9)\\s*(?:k|kt|kt\\.|carat|karat|caret|ct)\\b");
    private static final Pattern HALLMARK = Pattern.compile("\\b(916|750|585|375|999|925)\\b");
    private static final String WT_UNIT = "\\s*(?:grams|gram|gms|gm|g)\\b";

    public Interpretation interpret(String text, List<Category> categories) {
        String s = normalize(text);

        String intent = "SEARCH";
        if (s.contains("how many") || s.matches(".*\\b(count|kitna)\\b.*")) intent = "COUNT";
        if (s.matches(".*\\b(rate|price of gold|gold price|silver price)\\b.*") && !s.matches(".*\\b(below|above|under|between)\\b.*")) intent = "RATE";
        if (s.matches(".*\\brepair\\b.*")) intent = "REPAIR";

        String tag = null;
        Matcher tm = TAG.matcher(s);
        if (tm.find()) tag = tm.group(1).toUpperCase(Locale.ROOT);
        else {
            Matcher bm = BARE_TAG.matcher(s);
            if (bm.find()) tag = bm.group(1).toUpperCase(Locale.ROOT);
        }
        if (tag != null && !intent.equals("REPAIR")) intent = "TAG";

        // Weight first, so "20 grams" is not taken as a price.
        BigDecimal minWt = null, maxWt = null;
        Matcher m;
        if ((m = find(s, "between\\s*" + NUM + "\\s*(?:and|to|-)\\s*" + NUM + WT_UNIT)) != null
                || (m = find(s, NUM + "\\s*(?:to|-)\\s*" + NUM + WT_UNIT)) != null) {
            minWt = dec(m.group(1));
            maxWt = dec(m.group(2));
            s = s.replace(m.group(0), " ");
        } else if ((m = find(s, "(?:below|under|less than|upto|up to|within|max)\\s*" + NUM + WT_UNIT)) != null
                || (m = find(s, NUM + WT_UNIT + "\\s*(?:below|or less)")) != null) {
            maxWt = dec(m.group(1));
            s = s.replace(m.group(0), " ");
        } else if ((m = find(s, "(?:above|over|more than|min|at least)\\s*" + NUM + WT_UNIT)) != null
                || (m = find(s, NUM + WT_UNIT + "\\s*(?:above|or more)")) != null) {
            minWt = dec(m.group(1));
            s = s.replace(m.group(0), " ");
        } else if ((m = find(s, NUM + WT_UNIT)) != null) {
            BigDecimal w = dec(m.group(1));
            minWt = w.multiply(new BigDecimal("0.95"));
            maxWt = w.multiply(new BigDecimal("1.05"));
            s = s.replace(m.group(0), " ");
        }

        String purity = null;
        String metal = null;
        Matcher pm = PURITY.matcher(s);
        if (pm.find()) {
            purity = pm.group(1) + "K";
            metal = "GOLD";
            s = s.replace(pm.group(0), " ");
        } else {
            Matcher hm = HALLMARK.matcher(s);
            if (hm.find() && !hasPriceContext(s, hm.start())) {
                purity = switch (hm.group(1)) {
                    case "916" -> "22K";
                    case "750" -> "18K";
                    case "585" -> "14K";
                    case "375" -> "9K";
                    case "999" -> s.contains("silver") ? "999" : "24K";
                    default -> "925";
                };
                if ("925".equals(purity) || "999".equals(purity)) metal = "SILVER";
                else if (purity != null) metal = "GOLD";
                s = s.replace(hm.group(0), " ");
            }
        }

        BigDecimal minPrice = null, maxPrice = null;
        if ((m = find(s, "between\\s*" + NUM + "\\s*(?:and|to|-)\\s*" + NUM)) != null
                || (m = find(s, NUM + "\\s*(?:to|-)\\s*" + NUM)) != null) {
            minPrice = dec(m.group(1));
            maxPrice = dec(m.group(2));
        } else if ((m = find(s, "(?:below|under|less than|upto|up to|within|max|budget|cheaper than)\\s*(?:rs\\.?|inr)?\\s*" + NUM)) != null
                || (m = find(s, NUM + "\\s*(?:rupees)?\\s*(?:below|or less)")) != null) {
            maxPrice = dec(m.group(1));
        } else if ((m = find(s, "(?:above|over|more than|greater than|min|at least|costlier than)\\s*(?:rs\\.?|inr)?\\s*" + NUM)) != null
                || (m = find(s, NUM + "\\s*(?:rupees)?\\s*(?:above|or more)")) != null) {
            minPrice = dec(m.group(1));
        } else if ((m = find(s, "(?:around|about|approx|approximately|lagbhag)\\s*" + NUM)) != null) {
            BigDecimal p = dec(m.group(1));
            minPrice = p.multiply(new BigDecimal("0.9"));
            maxPrice = p.multiply(new BigDecimal("1.1"));
        }

        Set<String> families = new LinkedHashSet<>();
        String stoneType = null;
        if (s.matches(".*\\b(diamond|diamonds|dia)\\b.*")) {
            families.add("DIAMOND");
            stoneType = "DIAMOND";
        }
        if (s.matches(".*\\bplatinum\\b.*")) { families.add("PLATINUM"); metal = "PLATINUM"; }
        if (s.matches(".*\\bsilver\\b.*")) { families.add("SILVER"); families.add("SILVER_ORNAMENT"); metal = "SILVER"; }
        if (s.matches(".*\\b(gift|gifts|gifting)\\b.*")) families.add("GIFTING");
        if (s.matches(".*\\bgold\\b.*") && metal == null) metal = "GOLD";
        if (s.matches(".*\\bgold\\b.*") && families.isEmpty() && purity == null && !s.matches(".*\\bdiamond\\b.*")) {
            families.add("GOLD");
        }

        List<String> typeWords = new ArrayList<>();
        String rest = s;
        for (String[] t : TYPE_WORDS) {
            if (Pattern.compile("\\b" + t[0] + "s?\\b").matcher(rest).find()) {
                typeWords.add(t[1]);
                rest = rest.replaceAll("\\b" + t[0] + "s?\\b", " ");
            }
        }
        Set<Long> categoryIds = new LinkedHashSet<>();
        if (!typeWords.isEmpty()) {
            for (Category c : categories) {
                String name = c.name().toLowerCase(Locale.ROOT);
                boolean typeMatch = typeWords.stream().anyMatch(w -> matchesType(name, w));
                boolean familyOk = families.isEmpty() || families.contains(c.family());
                boolean metalOk = metal == null || metal.equals(c.metal());
                if (typeMatch && familyOk && metalOk) categoryIds.add(c.id());
            }
        }
        if (families.contains("GOLD") && !categoryIds.isEmpty()) families.clear();

        return new Interpretation(intent, tag, metal, families, purity, categoryIds, typeWords, minPrice, maxPrice,
                minWt, maxWt, stoneType, text, s.trim().replaceAll("\\s+", " "));
    }

    /** "ring" must not match "earring" or "toe ring" unless asked for. */
    private static boolean matchesType(String categoryName, String word) {
        if (word.equals("ring")) {
            return categoryName.matches(".*\\bring\\b.*") && !categoryName.contains("toe ring") && !categoryName.contains("earring");
        }
        return categoryName.contains(word);
    }

    private static boolean hasPriceContext(String s, int at) {
        String before = s.substring(0, at);
        return before.matches(".*(below|under|above|over|between|less than|more than|rs|rupees)\\s*$");
    }

    static String normalize(String text) {
        String s = text == null ? "" : text.toLowerCase(Locale.ROOT);
        // Devanagari digits to ASCII.
        StringBuilder sb = new StringBuilder();
        for (char ch : s.toCharArray()) sb.append(ch >= '०' && ch <= '९' ? (char) ('0' + (ch - '०')) : ch);
        s = sb.toString();
        for (Map.Entry<String, String> e : SYNONYMS.entrySet()) {
            s = e.getKey().chars().allMatch(c -> c < 128)
                    ? s.replaceAll("\\b" + Pattern.quote(e.getKey()) + "\\b", " " + e.getValue() + " ")
                    : s.replace(e.getKey(), " " + e.getValue() + " ");
        }
        s = s.replace("₹", " rs ").replaceAll("(?<=\\d),(?=\\d)", "").replace("jewellery", "jewelry");
        s = s.replaceAll("\\brs\\.?\\s*", " rs ");
        // 50k, 1.5 lakh, 50 thousand, 2 crore
        s = scale(s, "(\\d+(?:\\.\\d+)?)\\s*(?:k)\\b", 1_000);
        s = scale(s, "(\\d+(?:\\.\\d+)?)\\s*(?:thousand)\\b", 1_000);
        s = scale(s, "(\\d+(?:\\.\\d+)?)\\s*(?:lakh|lakhs|lac|lacs)\\b", 100_000);
        s = scale(s, "(\\d+(?:\\.\\d+)?)\\s*(?:crore|cr)\\b", 10_000_000);
        // "tag t 000123" as dictated -> "tag t000123"
        s = s.replaceAll("\\b(tag|code|item)\\s+(?:number\\s+|no\\s+)?([a-z])\\s+(\\d)", "$1 $2$3");
        // "18 karat" spoken as "18 carrot".
        s = s.replaceAll("\\b(24|22|20|18|14|9)\\s*(?:carrot|carets|carats|karats)\\b", "$1 carat");
        return s.replaceAll("\\s+", " ").trim();
    }

    private static String scale(String s, String regex, long factor) {
        Matcher m = Pattern.compile(regex).matcher(s);
        StringBuilder out = new StringBuilder();
        while (m.find()) {
            BigDecimal v = new BigDecimal(m.group(1)).multiply(BigDecimal.valueOf(factor));
            m.appendReplacement(out, v.stripTrailingZeros().toPlainString());
        }
        m.appendTail(out);
        return out.toString();
    }

    private static Matcher find(String s, String regex) {
        Matcher m = Pattern.compile(regex).matcher(s);
        return m.find() ? m : null;
    }

    private static BigDecimal dec(String s) {
        return new BigDecimal(s);
    }
}
