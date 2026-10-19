package com.swarnos.identity.domain;

import com.swarnos.security.AuthUser;
import java.util.Map;

/** What a signed-in client needs: its token, who it is, which shop, and what it may do. */
public record Session(String token, AuthUser user, ShopInfo shop, Map<String, Boolean> permissions) {
    public record ShopInfo(String code, String name, String storageMode) {}
}
