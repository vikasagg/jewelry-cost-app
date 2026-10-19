package com.swarnos.security;

import static com.swarnos.security.Role.ACCOUNTANT;
import static com.swarnos.security.Role.MANAGER;
import static com.swarnos.security.Role.OWNER;
import static com.swarnos.security.Role.SALES;
import static com.swarnos.security.Role.STOCK;

import java.util.EnumSet;
import java.util.Set;

/** Default role profile from BRD §19. */
public enum Permission {
    RATE_ENTER(OWNER, MANAGER),
    RATE_APPROVE(OWNER, MANAGER),
    BILL(OWNER, MANAGER, SALES),
    DISCOUNT_OVERRIDE(OWNER, MANAGER),
    SALE_RETURN(OWNER, MANAGER),
    PURCHASE(OWNER, MANAGER, ACCOUNTANT, STOCK),
    VIEW_PURCHASE_CLASS(OWNER, ACCOUNTANT),
    CHANGE_PURCHASE_CLASS(OWNER),
    VIEW_COST(OWNER, MANAGER, ACCOUNTANT),
    ITEM_EDIT(OWNER, MANAGER, STOCK),
    TALLY_CAPTURE(OWNER, MANAGER, SALES, STOCK),
    TALLY_APPROVE(OWNER, MANAGER),
    REPAIR(OWNER, MANAGER, SALES, STOCK),
    PARTY_EDIT(OWNER, MANAGER, SALES, ACCOUNTANT, STOCK),
    PAYMENT(OWNER, MANAGER, ACCOUNTANT),
    REPORTS_LEDGER(OWNER, MANAGER, ACCOUNTANT),
    BACKUP(OWNER),
    CONFIG(OWNER),
    USERS(OWNER);

    private final Set<Role> roles;

    Permission(Role first, Role... rest) {
        this.roles = EnumSet.of(first, rest);
    }

    public boolean allows(Role role) {
        return roles.contains(role);
    }
}
