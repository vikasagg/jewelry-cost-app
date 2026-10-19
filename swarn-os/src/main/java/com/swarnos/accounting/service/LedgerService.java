package com.swarnos.accounting.service;

import com.swarnos.accounting.domain.Book;
import com.swarnos.accounting.domain.BookStatement;
import com.swarnos.accounting.domain.Direction;
import com.swarnos.accounting.domain.DocumentType;
import com.swarnos.accounting.domain.LedgerEntry;
import com.swarnos.accounting.domain.Payment;
import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.accounting.repository.LedgerRepository;
import com.swarnos.accounting.repository.PaymentRepository;
import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Posts to the books and reads balances. Callers run inside their document's transaction. */
@Service
public class LedgerService {
    private final LedgerRepository ledger;
    private final PaymentRepository payments;
    private final AuditService audit;
    private final BusinessClock clock;

    public LedgerService(LedgerRepository ledger, PaymentRepository payments, AuditService audit, BusinessClock clock) {
        this.ledger = ledger;
        this.payments = payments;
        this.audit = audit;
        this.clock = clock;
    }

    /** A money (or fine-metal) movement; zero amounts are skipped. */
    public void post(Book book, Long partyId, DocumentType docType, long docId, BigDecimal debit, BigDecimal credit,
                     String narration) {
        BigDecimal d = Decimals.orZero(debit), c = Decimals.orZero(credit);
        if (d.signum() == 0 && c.signum() == 0) return;
        ledger.insert(book, clock.today(), partyId, docType, docId, d, c, narration);
    }

    /** Money received (IN) or paid (OUT) against a document, posted to cash/bank and to the party's account. */
    public void recordPayment(DocumentType docType, long docId, Long partyId, Direction direction, PaymentMode mode,
                              BigDecimal amount, String reference, String narration) {
        BigDecimal amt = Decimals.orZero(amount);
        if (amt.signum() == 0) return;
        if (amt.signum() < 0) throw BusinessException.validation("Payment amount cannot be negative.");
        if (mode == null) throw BusinessException.validation("Choose the payment mode.");
        payments.insert(new Payment(0, docType, docId, partyId, direction, mode, amt, reference, clock.today(),
                CurrentUser.usernameOrSystem(), null));
        boolean in = direction == Direction.IN;
        String suffix = " (" + mode + (reference == null || reference.isBlank() ? "" : " " + reference) + ")";
        post(mode.book(), partyId, docType, docId, in ? amt : null, in ? null : amt, narration + suffix);
        if (partyId != null) post(Book.PARTY, partyId, docType, docId, in ? null : amt, in ? amt : null, narration);
    }

    public List<Payment> paymentsFor(long docId, DocumentType... types) {
        return payments.forDocument(docId, types);
    }

    public BigDecimal balance(Book book) {
        return ledger.balance(book);
    }

    public Map<Book, BigDecimal> shopBalances() {
        CurrentUser.require(Permission.REPORTS_LEDGER);
        Map<Book, BigDecimal> out = new LinkedHashMap<>();
        for (Book b : Book.SHOP_BOOKS) out.put(b, ledger.balance(b));
        return out;
    }

    public BigDecimal partyBalance(long partyId) {
        return ledger.partyBalance(partyId);
    }

    public Map<Long, BigDecimal> partyBalances() {
        return ledger.partyBalances();
    }

    public List<LedgerEntry> partyEntries(long partyId) {
        return ledger.partyEntries(partyId);
    }

    public BookStatement statement(Book book, LocalDate from, LocalDate to) {
        CurrentUser.require(Permission.REPORTS_LEDGER);
        if (!Book.SHOP_BOOKS.contains(book)) throw BusinessException.validation("Unknown book " + book);
        BigDecimal opening = ledger.balanceBefore(book, from);
        BigDecimal running = opening, debit = Decimals.ZERO, credit = Decimals.ZERO;
        List<BookStatement.Line> lines = new ArrayList<>();
        for (LedgerRepository.NamedEntry n : ledger.entries(book, from, to)) {
            LedgerEntry e = n.entry();
            debit = debit.add(e.debit());
            credit = credit.add(e.credit());
            running = running.add(e.debit()).subtract(e.credit());
            lines.add(new BookStatement.Line(e.businessDate(), e.docType(), e.docId(), e.narration(), n.partyName(),
                    e.debit(), e.credit(), Decimals.round(running)));
        }
        return new BookStatement(book, from, to, opening, Decimals.round(debit), Decimals.round(credit), Decimals.round(running), lines);
    }

    /** Opening cash, bank or metal when a shop starts using the system. */
    @Transactional
    public Map<Book, BigDecimal> postOpening(Book book, BigDecimal amount) {
        CurrentUser.require(Permission.CONFIG);
        if (!Book.SHOP_BOOKS.contains(book)) throw BusinessException.validation("Unknown book " + book);
        BigDecimal a = Decimals.orZero(amount);
        post(book, null, DocumentType.OPENING, 0, a.max(Decimals.ZERO), a.min(Decimals.ZERO).negate(), "Opening balance");
        audit.record("OPENING_BALANCE", "ledger", book, a.toPlainString());
        return shopBalances();
    }

    /** Opening balance during demo set-up (no signed-in user). */
    public void postOpeningUnchecked(Book book, BigDecimal amount) {
        post(book, null, DocumentType.OPENING, 0, amount, null, "Opening balance");
    }
}
