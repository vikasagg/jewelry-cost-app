package com.swarnos.common.error;

/** Kinds of business failure; the API layer maps each to an HTTP status. */
public enum ErrorType {
    VALIDATION,
    NOT_FOUND,
    CONFLICT,
    FORBIDDEN,
    UNAUTHENTICATED
}
