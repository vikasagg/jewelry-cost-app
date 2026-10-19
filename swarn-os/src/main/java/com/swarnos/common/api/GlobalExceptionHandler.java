package com.swarnos.common.api;

import com.swarnos.common.error.BusinessException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/** Translates business and framework errors into HTTP responses. */
@RestControllerAdvice
public class GlobalExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(BusinessException.class)
    ResponseEntity<ApiError> business(BusinessException e) {
        HttpStatus status = switch (e.type()) {
            case VALIDATION -> HttpStatus.BAD_REQUEST;
            case NOT_FOUND -> HttpStatus.NOT_FOUND;
            case CONFLICT -> HttpStatus.CONFLICT;
            case FORBIDDEN -> HttpStatus.FORBIDDEN;
            case UNAUTHENTICATED -> HttpStatus.UNAUTHORIZED;
        };
        return ResponseEntity.status(status).body(new ApiError(e.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ApiError> invalid(MethodArgumentNotValidException e) {
        String msg = e.getBindingResult().getFieldErrors().stream()
                .map(f -> f.getField() + " " + f.getDefaultMessage()).findFirst().orElse("Invalid request.");
        return ResponseEntity.badRequest().body(new ApiError(msg));
    }

    @ExceptionHandler(DuplicateKeyException.class)
    ResponseEntity<ApiError> duplicate(DuplicateKeyException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ApiError("This record already exists (duplicate code or number)."));
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class,
            MissingServletRequestParameterException.class})
    ResponseEntity<ApiError> unreadable(Exception e) {
        return ResponseEntity.badRequest().body(new ApiError("The request could not be read: " + e.getMessage()));
    }

    @ExceptionHandler(NoResourceFoundException.class)
    ResponseEntity<ApiError> noResource(NoResourceFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ApiError("Not found"));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiError> unexpected(Exception e) {
        log.error("Unexpected error", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(new ApiError("Something went wrong: " + e.getMessage()));
    }
}
