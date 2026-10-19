package com.swarnos.accounting.api;

import com.swarnos.accounting.api.dto.OpeningBalanceRequest;
import com.swarnos.accounting.domain.Book;
import com.swarnos.accounting.domain.BookStatement;
import com.swarnos.accounting.service.LedgerService;
import com.swarnos.common.api.DateRange;
import com.swarnos.common.time.BusinessClock;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Map;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
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
    public Map<Book, BigDecimal> balances() {
        return ledgers.shopBalances();
    }

    @GetMapping("/{book}")
    public BookStatement statement(@PathVariable String book,
                                   @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                   @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        DateRange range = DateRange.monthToDate(from, to, clock.today());
        return ledgers.statement(Book.valueOf(book.toUpperCase()), range.from(), range.to());
    }

    @PostMapping("/opening")
    public Map<Book, BigDecimal> opening(@RequestBody OpeningBalanceRequest req) {
        return ledgers.postOpening(req.book(), req.amount());
    }
}
