package com.swarnos.inventory.service;

import com.swarnos.common.error.BusinessException;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.domain.StatusMismatch;
import com.swarnos.inventory.domain.StockMove;
import com.swarnos.inventory.domain.StockMovement;
import com.swarnos.inventory.repository.ItemRepository;
import com.swarnos.inventory.repository.StockMovementRepository;
import com.swarnos.security.CurrentUser;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * The only place stock changes (BRD FR-STK-01..04): every change is a movement
 * row, and the item's status is updated with it. Runs inside the caller's transaction.
 */
@Service
public class StockLedgerService {
    private final ItemRepository items;
    private final StockMovementRepository movements;
    private final BusinessClock clock;

    public StockLedgerService(ItemRepository items, StockMovementRepository movements, BusinessClock clock) {
        this.items = items;
        this.movements = movements;
        this.clock = clock;
    }

    public void post(StockMove move) {
        Item item = items.findById(move.itemId()).orElseThrow(() -> BusinessException.notFound("Item not found"));
        if (!move.allowedFrom().contains(item.status())) {
            throw BusinessException.conflict("Tag " + item.tagCode() + " is " + item.status().name().replace('_', ' ').toLowerCase()
                    + " and cannot be used here.");
        }
        String idemKey = move.type() + ":" + (move.docType() == null ? "-" : move.docType()) + ":"
                + (move.docId() == null ? UUID.randomUUID() : move.docId()) + ":" + move.itemId();
        movements.insert(new StockMovement(0, item.id(), move.type(), move.qty(), item.grossWt(), item.netWt(), move.statusAfter(),
                move.docType(), move.docId(), clock.today(), CurrentUser.usernameOrSystem(), null, idemKey, move.note()));
        items.updateStatus(item.id(), move.statusAfter(), move.toLocationId());
    }

    public List<StockMovement> history(long itemId) {
        return movements.findByItem(itemId);
    }

    /** Items whose cached status disagrees with the ledger (scheduled check). */
    public List<StatusMismatch> verify() {
        return items.findStatusMismatches();
    }
}
