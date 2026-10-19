package com.swarnos.ledger;

import com.swarnos.auth.CurrentUser;
import com.swarnos.auth.Permission;
import com.swarnos.common.ApiException;
import com.swarnos.common.BusinessClock;
import com.swarnos.common.Num;
import com.swarnos.common.Rows;
import java.math.BigDecimal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/ledgers")
public class LedgerController {
    private final LedgerService ledgers;
    private final BusinessClock clock;

    public LedgerController(LedgerService ledgers, BusinessClock clock) {
        this.ledgers = ledgers;
        this.clock = clock;
    }

    @GetMapping
    public Map<String, Object> balances() {
        CurrentUser.require(Permission.REPORTS_LEDGER);
        Map<String, Object> out = new LinkedHashMap<>();
        for (String b : LedgerService.BOOKS) out.put(b, ledgers.balance(b));
        return out;
    }

    /** Opening cash, bank and metal balances when a shop starts using the system. */
    @PostMapping("/opening")
    public Map<String, Object> opening(@RequestBody Map<String, Object> b) {
        CurrentUser.require(Permission.CONFIG);
        String book = Rows.str(b.get("book")).toUpperCase();
        if (!LedgerService.BOOKS.contains(book)) throw ApiException.bad("Unknown book " + book);
        BigDecimal amount = Num.of(b.get("amount"));
        ledgers.post(book, null, "OPENING", 0, amount.max(Num.ZERO), amount.min(Num.ZERO).negate(), "Opening balance");
        return balances();
    }

    @GetMapping("/{book}")
    public Map<String, Object> book(@PathVariable String book, @RequestParam(required = false) String from,
                                    @RequestParam(required = false) String to) {
        CurrentUser.require(Permission.REPORTS_LEDGER);
        String b = book.toUpperCase();
        if (!LedgerService.BOOKS.contains(b)) throw ApiException.bad("Unknown book " + book);
        LocalDate t = to == null || to.isBlank() ? clock.today() : Rows.date(to);
        LocalDate f = from == null || from.isBlank() ? t.withDayOfMonth(1) : Rows.date(from);
        return ledgers.book(b, f, t);
    }
}
