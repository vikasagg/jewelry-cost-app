package com.swarnos.repair.service;

import com.swarnos.accounting.domain.Book;
import com.swarnos.accounting.domain.Direction;
import com.swarnos.accounting.domain.DocumentType;
import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.accounting.service.LedgerService;
import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.numbering.service.DocumentNumberService;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.parties.domain.PartyType;
import com.swarnos.parties.service.PartyService;
import com.swarnos.repair.domain.RepairEvent;
import com.swarnos.repair.domain.RepairJob;
import com.swarnos.repair.domain.RepairJobView;
import com.swarnos.repair.domain.RepairStats;
import com.swarnos.repair.domain.RepairStatus;
import com.swarnos.repair.repository.RepairRepository;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.service.SettingsService;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Repair and job work (BRD §11). The customer's piece is held in repair custody,
 * never in sale stock; each hand-off records weight so metal loss or gain shows at delivery.
 */
@Service
public class RepairService {
    private final RepairRepository repairs;
    private final PartyService parties;
    private final LedgerService ledger;
    private final SettingsService settings;
    private final DocumentNumberService numbers;
    private final AuditService audit;
    private final BusinessClock clock;

    public RepairService(RepairRepository repairs, PartyService parties, LedgerService ledger, SettingsService settings,
                         DocumentNumberService numbers, AuditService audit, BusinessClock clock) {
        this.repairs = repairs;
        this.parties = parties;
        this.ledger = ledger;
        this.settings = settings;
        this.numbers = numbers;
        this.audit = audit;
        this.clock = clock;
    }

    public record Intake(Long customerId, String description, Metal metal, String purityCode, BigDecimal weightIn,
                         String itemCondition, String repairType, BigDecimal estimate, LocalDate promisedDate,
                         BigDecimal advance, PaymentMode advanceMode) {}

    public record StatusChange(RepairStatus status, Long karigarId, BigDecimal weight, BigDecimal extraMetalWt,
                               BigDecimal charges, BigDecimal amount, PaymentMode mode, String reference, String note) {}

    public record RepairDetail(RepairJobView view, List<RepairEvent> events) {}

    public record ListedJob(RepairJobView view, boolean overdue) {}

    @Transactional
    public RepairDetail intake(Intake in) {
        CurrentUser.require(Permission.REPAIR);
        if (in.customerId() == null) throw BusinessException.validation("Choose the customer.");
        parties.require(in.customerId());
        if (!Decimals.isPositive(in.weightIn())) throw BusinessException.validation("Weigh the piece: weight in is required.");
        if (in.description() == null || in.description().isBlank()) throw BusinessException.validation("Describe the piece.");
        String no = numbers.next(settings.text(SettingKeys.REPAIR_PREFIX, "REP"), clock.today());
        long id = repairs.insert(new RepairJob(0, no, in.customerId(), in.description().trim(), in.metal(), blank(in.purityCode()),
                Decimals.round(in.weightIn()), blank(in.itemCondition()), blank(in.repairType()), Decimals.orZero(in.estimate()),
                in.promisedDate(), RepairStatus.RECEIVED, null, null, null, Decimals.ZERO, null, null, Decimals.ZERO,
                CurrentUser.usernameOrSystem(), null, null));
        repairs.insertEvent(id, RepairStatus.RECEIVED, Decimals.round(in.weightIn()), "Received from customer", CurrentUser.usernameOrSystem());
        if (Decimals.isPositive(in.advance())) {
            ledger.recordPayment(DocumentType.REPAIR, id, in.customerId(), Direction.IN,
                    in.advanceMode() == null ? PaymentMode.CASH : in.advanceMode(), in.advance(), null, "Repair advance " + no);
            repairs.recordPaid(id, Decimals.round(in.advance()));
        }
        audit.record("REPAIR_INTAKE", "repair", no, "weight in " + in.weightIn());
        return detail(id);
    }

    /** Moves the job to its next step, recording the weight at each hand-off. */
    @Transactional
    public RepairDetail changeStatus(long id, StatusChange c) {
        CurrentUser.require(Permission.REPAIR);
        RepairJob job = view(id).job();
        if (c.status() == null || !job.status().canMoveTo(c.status())) {
            throw BusinessException.conflict("A job that is " + job.status() + " cannot move to " + c.status() + ".");
        }
        BigDecimal weight = Decimals.roundOrNull(c.weight());
        switch (c.status()) {
            case WITH_KARIGAR -> {
                if (c.karigarId() == null) throw BusinessException.validation("Choose a karigar");
                parties.requireType(c.karigarId(), PartyType.KARIGAR, "Choose a karigar");
                if (weight == null) throw BusinessException.validation("Weigh the piece before giving it to the karigar.");
                repairs.issueToKarigar(id, c.karigarId(), weight);
            }
            case READY -> {
                if (weight == null) throw BusinessException.validation("Weigh the finished piece.");
                if (job.status() == RepairStatus.WITH_KARIGAR) repairs.recordReturnFromKarigar(id, weight);
                repairs.recordFinished(id, weight, Decimals.orZero(c.extraMetalWt()));
            }
            case DELIVERED -> deliver(job, c);
            default -> { }
        }
        repairs.updateStatus(id, c.status());
        repairs.insertEvent(id, c.status(), weight, blank(c.note()), CurrentUser.usernameOrSystem());
        audit.record("REPAIR_" + c.status(), "repair", job.jobNo(), weight == null ? null : "weight " + weight);
        return detail(id);
    }

    private void deliver(RepairJob job, StatusChange c) {
        BigDecimal charges = Decimals.orZero(c.charges());
        BigDecimal pay = Decimals.orZero(c.amount());
        BigDecimal paid = Decimals.round(job.paid().add(pay));
        if (paid.compareTo(charges) > 0) throw BusinessException.validation("Payment is more than the charges.");
        repairs.recordDelivered(job.id(), charges, paid, clock.now());
        ledger.post(Book.PARTY, job.customerId(), DocumentType.REPAIR, job.id(), charges, null, "Repair " + job.jobNo());
        ledger.recordPayment(DocumentType.REPAIR, job.id(), job.customerId(), Direction.IN, c.mode() == null ? PaymentMode.CASH : c.mode(),
                pay, blank(c.reference()), "Repair " + job.jobNo());
    }

    public RepairDetail detail(long id) {
        return new RepairDetail(view(id), repairs.findEvents(id));
    }

    public RepairDetail byNumber(String jobNo) {
        return detail(repairs.findIdByNumber(jobNo == null ? "" : jobNo.trim())
                .orElseThrow(() -> BusinessException.notFound("No repair job " + jobNo)));
    }

    /** filter: null = all, OPEN = not delivered, or a status name. */
    public List<ListedJob> list(String filter, String text) {
        LocalDate today = clock.today();
        return repairs.list(filter, text).stream().map(v -> new ListedJob(v, v.job().isOverdue(today))).toList();
    }

    public List<RepairJob> forParty(long partyId) {
        return repairs.findByParty(partyId);
    }

    public RepairStats stats() {
        return repairs.stats(clock.today());
    }

    /** Customer pieces in the shop, and with karigars: the tally's separate buckets. */
    public long countInShop() {
        return repairs.countIn(List.of(RepairStatus.RECEIVED, RepairStatus.IN_PROGRESS, RepairStatus.READY));
    }

    public long countWithKarigar() {
        return repairs.countIn(List.of(RepairStatus.WITH_KARIGAR));
    }

    private RepairJobView view(long id) {
        return repairs.findView(id).orElseThrow(() -> BusinessException.notFound("Repair job not found"));
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
