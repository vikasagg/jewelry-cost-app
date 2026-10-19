package com.swarnos.purchase.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonUnwrapped;
import com.swarnos.purchase.domain.Purchase;
import com.swarnos.purchase.domain.PurchaseLine;
import com.swarnos.purchase.domain.PurchaseView;
import com.swarnos.purchase.service.PurchaseService;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import java.util.List;

/** A purchase with its lines; the Seen/Unseen class is left out for roles that may not see it. */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record PurchaseResponse(@JsonUnwrapped Purchase purchase, String partyName, String partyPhone, Long lineCount,
                               List<PurchaseLine> lines, List<String> warnings) {

    public static PurchaseResponse summary(PurchaseView v) {
        return new PurchaseResponse(mask(v.purchase()), v.partyName(), null, v.lineCount(), null, null);
    }

    public static PurchaseResponse of(PurchaseService.PurchaseDetail d, List<String> warnings) {
        PurchaseView v = d.view();
        return new PurchaseResponse(mask(v.purchase()), v.partyName(), v.partyPhone(), v.lineCount(), d.lines(), warnings);
    }

    private static Purchase mask(Purchase p) {
        return CurrentUser.can(Permission.VIEW_PURCHASE_CLASS) ? p : p.withoutClass();
    }
}
