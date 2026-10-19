package com.swarnos.security;

public enum Role {
    OWNER, MANAGER, SALES, ACCOUNTANT, STOCK, PLATFORM;

    public boolean isShopRole() {
        return this != PLATFORM;
    }
}
