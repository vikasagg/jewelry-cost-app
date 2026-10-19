package com.swarnos.common.api;

/** Error body returned by every endpoint: {"error": "..."} */
public record ApiError(String error) {}
