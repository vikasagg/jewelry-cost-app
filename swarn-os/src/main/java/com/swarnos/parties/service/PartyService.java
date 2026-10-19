package com.swarnos.parties.service;

import com.swarnos.accounting.domain.Direction;
import com.swarnos.accounting.domain.DocumentType;
import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.accounting.service.LedgerService;
import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.parties.domain.Party;
import com.swarnos.parties.domain.PartyDetails;
import com.swarnos.parties.domain.PartyType;
import com.swarnos.parties.repository.PartyRepository;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Customers, vendors and karigars, and settling their accounts (BRD §10). */
@Service
public class PartyService {
    private static final int SEARCH_LIMIT = 300;

    private final PartyRepository parties;
    private final LedgerService ledger;
    private final AuditService audit;

    public PartyService(PartyRepository parties, LedgerService ledger, AuditService audit) {
        this.parties = parties;
        this.ledger = ledger;
        this.audit = audit;
    }

    public record PartyWithBalance(Party party, BigDecimal balance) {}

    public List<PartyWithBalance> search(PartyType type, String text) {
        Map<Long, BigDecimal> balances = ledger.partyBalances();
        return parties.search(type, text, SEARCH_LIMIT).stream()
                .map(p -> new PartyWithBalance(p, balances.getOrDefault(p.id(), BigDecimal.ZERO)))
                .toList();
    }

    public Party require(long id) {
        return parties.findById(id).orElseThrow(() -> BusinessException.notFound("Party not found"));
    }

    public Party requireType(long id, PartyType type, String message) {
        Party p = require(id);
        if (p.partyType() != type) throw BusinessException.validation(message);
        return p;
    }

    @Transactional
    public Party create(PartyDetails details) {
        CurrentUser.require(Permission.PARTY_EDIT);
        long id = parties.insert(details);
        audit.record("PARTY_CREATE", "party", id, details.partyType() + " " + details.name());
        return require(id);
    }

    @Transactional
    public Party update(long id, PartyDetails details) {
        CurrentUser.require(Permission.PARTY_EDIT);
        require(id);
        parties.update(id, details);
        audit.record("PARTY_UPDATE", "party", id, details.name());
        return require(id);
    }

    /** Money received from or paid to a party outside a bill (settling dues). */
    @Transactional
    public Party settle(long id, Direction direction, PaymentMode mode, BigDecimal amount, String reference) {
        CurrentUser.require(Permission.PAYMENT);
        Party party = require(id);
        boolean in = direction != Direction.OUT;
        ledger.recordPayment(in ? DocumentType.RECEIPT : DocumentType.VOUCHER, id, id, in ? Direction.IN : Direction.OUT, mode,
                amount, reference, in ? "Received from party" : "Paid to party");
        audit.record("PARTY_SETTLE", "party", id, direction + " " + amount);
        return party;
    }
}
