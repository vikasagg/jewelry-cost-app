package com.swarnos.common.error;

/** A rule was broken; the message is shown to the user as is. Carries no HTTP knowledge. */
public class BusinessException extends RuntimeException {
    private final ErrorType type;

    public BusinessException(ErrorType type, String message) {
        super(message);
        this.type = type;
    }

    public ErrorType type() {
        return type;
    }

    public static BusinessException validation(String message) {
        return new BusinessException(ErrorType.VALIDATION, message);
    }

    public static BusinessException notFound(String message) {
        return new BusinessException(ErrorType.NOT_FOUND, message);
    }

    public static BusinessException conflict(String message) {
        return new BusinessException(ErrorType.CONFLICT, message);
    }

    public static BusinessException forbidden(String message) {
        return new BusinessException(ErrorType.FORBIDDEN, message);
    }

    public static BusinessException unauthenticated(String message) {
        return new BusinessException(ErrorType.UNAUTHENTICATED, message);
    }
}
