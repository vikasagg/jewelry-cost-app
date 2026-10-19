package com.swarnos.rates;

import com.swarnos.auth.CurrentUser;
import com.swarnos.auth.Permission;
import com.swarnos.common.ApiException;
import com.swarnos.common.AuditService;
import com.swarnos.common.BusinessClock;
import com.swarnos.common.Db;
import com.swarnos.common.Num;
import com.swarnos.config.ConfigService;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Daily metal rate (BRD §6): the 24K gold, silver and platinum base rates are
 * entered by hand or proposed from a live feed, approved once each morning,
 * and that approved set prices every bill of the day.
 */
@Service
public class RateService {
    private final Db db;
    private final BusinessClock clock;
    private final ConfigService config;
    private final AuditService audit;
    private final List<MetalRateProvider> providers;

    public RateService(Db db, BusinessClock clock, ConfigService config, AuditService audit,
                       List<MetalRateProvider> providers) {
        this.db = db;
        this.clock = clock;
        this.config = config;
        this.audit = audit;
        this.providers = providers;
    }

    public Optional<Map<String, Object>> approvedFor(LocalDate date) {
        return db.opt("SELECT * FROM rate_set WHERE business_date = ? AND status = 'APPROVED' ORDER BY id DESC", date);
    }

    public Optional<Map<String, Object>> approvedToday() {
        return approvedFor(clock.today());
    }

    /** The approved rate set billing must use today; billing waits until one exists. */
    public Map<String, Object> requireApprovedToday() {
        return approvedFor(clock.today()).orElseThrow(() -> ApiException.conflict(
                "Today's metal rate is not approved yet. Enter or approve it on the Rates screen first."));
    }

    public BigDecimal ratePerGram(long rateSetId, String metal, String purity) {
        BigDecimal r = db.value("SELECT rate_per_gram FROM rate_line WHERE rate_set_id = ? AND metal = ? AND purity_code = ?",
                BigDecimal.class, rateSetId, metal, purity);
        if (r == null) throw ApiException.bad("No rate for " + metal + " " + purity + " in today's rate set.");
        return r;
    }

    /** Derived rate for every purity: base x price factor, 3 decimals (D-01, D-04). */
    public List<Map<String, Object>> derive(BigDecimal gold, BigDecimal silver, BigDecimal platinum) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> p : db.rows("SELECT * FROM purity WHERE active = TRUE ORDER BY metal, sort_order")) {
            String metal = (String) p.get("metal");
            BigDecimal base = switch (metal) {
                case "GOLD" -> gold;
                case "SILVER" -> silver;
                default -> platinum;
            };
            BigDecimal factor = (BigDecimal) p.get("price_factor");
            Map<String, Object> line = new LinkedHashMap<>();
            line.put("metal", metal);
            line.put("purity_code", p.get("code"));
            line.put("price_factor", factor);
            line.put("rate_per_gram", Num.mul(base, factor));
            out.add(line);
        }
        return out;
    }

    @Transactional
    public Map<String, Object> propose(String source, BigDecimal gold, BigDecimal silver, BigDecimal platinum,
                                       String provider, String note) {
        CurrentUser.require(Permission.RATE_ENTER);
        if (!Num.positive(gold) || !Num.positive(silver) || !Num.positive(platinum)) {
            throw ApiException.bad("Gold, silver and platinum rates must all be more than zero.");
        }
        long id = db.insert("""
                INSERT INTO rate_set (business_date, source, provider, gold_24k, silver_base, platinum_base, status,
                                      entered_by, note) VALUES (?,?,?,?,?,?, 'PROPOSED', ?, ?)""",
                clock.today(), source, provider, Num.r(gold), Num.r(silver), Num.r(platinum),
                CurrentUser.usernameOrSystem(), note);
        writeLines(id, gold, silver, platinum);
        audit.log("RATE_PROPOSE", "rate_set", id, source + " gold24k=" + gold + " silver=" + silver + " pt=" + platinum);
        return get(id);
    }

    @Transactional
    public Map<String, Object> approve(long id) {
        CurrentUser.require(Permission.RATE_APPROVE);
        Map<String, Object> rs = db.one("SELECT * FROM rate_set WHERE id = ?", "Rate set not found", id);
        if (!"PROPOSED".equals(rs.get("status"))) throw ApiException.conflict("Only a proposed rate can be approved.");
        LocalDate date = com.swarnos.common.Rows.date(rs.get("business_date"));
        if (!date.equals(clock.today())) throw ApiException.conflict("This proposal is for another day.");
        db.update("UPDATE rate_set SET status = 'SUPERSEDED' WHERE business_date = ? AND status = 'APPROVED'", date);
        // Recalculate with the purity factors in force at approval time.
        db.update("DELETE FROM rate_line WHERE rate_set_id = ?", id);
        writeLines(id, (BigDecimal) rs.get("gold_24k"), (BigDecimal) rs.get("silver_base"), (BigDecimal) rs.get("platinum_base"));
        db.update("UPDATE rate_set SET status = 'APPROVED', approved_by = ?, approved_at = ? WHERE id = ?",
                CurrentUser.usernameOrSystem(), Timestamp.from(Instant.now()), id);
        audit.log("RATE_APPROVE", "rate_set", id, "gold24k=" + rs.get("gold_24k"));
        return get(id);
    }

    @Transactional
    public Map<String, Object> reject(long id) {
        CurrentUser.require(Permission.RATE_APPROVE);
        int n = db.update("UPDATE rate_set SET status = 'REJECTED', approved_by = ?, approved_at = ? WHERE id = ? AND status = 'PROPOSED'",
                CurrentUser.usernameOrSystem(), Timestamp.from(Instant.now()), id);
        if (n == 0) throw ApiException.conflict("Only a proposed rate can be rejected.");
        audit.log("RATE_REJECT", "rate_set", id, null);
        return get(id);
    }

    /** Asks the configured live source for a proposal. It never approves itself. */
    @Transactional
    public Map<String, Object> fetchLive() {
        String code = config.get("rate.live.provider", "NONE");
        if (code.equals("NONE")) throw ApiException.bad("No live rate source is configured. Enter the rate by hand.");
        MetalRateProvider provider = providers.stream().filter(p -> p.code().equals(code)).findFirst()
                .orElseThrow(() -> ApiException.bad("Unknown live rate source: " + code));
        LiveRates last = db.opt("SELECT * FROM rate_set WHERE status IN ('APPROVED','SUPERSEDED') ORDER BY id DESC")
                .map(r -> new LiveRates((BigDecimal) r.get("gold_24k"), (BigDecimal) r.get("silver_base"),
                        (BigDecimal) r.get("platinum_base"), null))
                .orElse(null);
        LiveRates live = provider.fetch(config, last);
        return propose("LIVE", live.gold24k(), live.silver(), live.platinum(), live.provider(),
                "Live proposal - needs approval");
    }

    public Map<String, Object> get(long id) {
        Map<String, Object> rs = new LinkedHashMap<>(db.one("SELECT * FROM rate_set WHERE id = ?", "Rate set not found", id));
        rs.put("lines", db.rows("SELECT metal, purity_code, rate_per_gram FROM rate_line WHERE rate_set_id = ? ORDER BY id", id));
        return rs;
    }

    public Map<String, Object> today() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("business_date", clock.today().toString());
        out.put("approved", approvedFor(clock.today()).map(r -> get(((Number) r.get("id")).longValue())).orElse(null));
        out.put("pending", db.rows("SELECT * FROM rate_set WHERE business_date = ? AND status = 'PROPOSED' ORDER BY id DESC",
                clock.today()));
        out.put("last_approved", db.opt("SELECT * FROM rate_set WHERE status IN ('APPROVED','SUPERSEDED') ORDER BY id DESC")
                .orElse(null));
        out.put("live_provider", config.get("rate.live.provider", "NONE"));
        return out;
    }

    public List<Map<String, Object>> history() {
        return db.rows("SELECT * FROM rate_set ORDER BY id DESC LIMIT 120");
    }

    private void writeLines(long id, BigDecimal gold, BigDecimal silver, BigDecimal platinum) {
        for (Map<String, Object> l : derive(gold, silver, platinum)) {
            db.update("INSERT INTO rate_line (rate_set_id, metal, purity_code, rate_per_gram) VALUES (?,?,?,?)",
                    id, l.get("metal"), l.get("purity_code"), l.get("rate_per_gram"));
        }
    }
}
