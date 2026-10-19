package com.swarnos.search.api.dto;

/** Text from the browser's speech recognition, or typed. */
public record AskRequest(String text) {}
