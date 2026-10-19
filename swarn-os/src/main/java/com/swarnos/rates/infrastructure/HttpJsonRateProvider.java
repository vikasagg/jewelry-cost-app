package com.swarnos.rates.infrastructure;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.swarnos.common.error.BusinessException;
import com.swarnos.rates.domain.BaseRates;
import java.io.IOException;
import java.math.BigDecimal;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import org.springframework.stereotype.Component;

/** Any licensed JSON feed: three per-gram values read from configurable (dotted) fields. */
@Component
public class HttpJsonRateProvider implements MetalRateProvider {
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final ObjectMapper json = new ObjectMapper();

    @Override
    public String code() {
        return "HTTP";
    }

    @Override
    public LiveQuote fetch(LiveFeedConfig config, BaseRates last) {
        if (config.url() == null || config.url().isBlank()) throw BusinessException.validation("Set rate.live.url in Settings first.");
        try {
            HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(config.url()))
                    .timeout(Duration.ofSeconds(15)).GET().build(), HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() != 200) throw BusinessException.validation("Rate provider answered HTTP " + res.statusCode());
            JsonNode root = json.readTree(res.body());
            return new LiveQuote(new BaseRates(read(root, config.goldField()), read(root, config.silverField()),
                    read(root, config.platinumField())), URI.create(config.url()).getHost());
        } catch (IOException e) {
            throw BusinessException.validation("Could not read the live rate: " + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw BusinessException.validation("Live rate request was interrupted.");
        }
    }

    private static BigDecimal read(JsonNode root, String path) {
        JsonNode n = root;
        for (String part : path.split("\\.")) n = n == null ? null : n.get(part);
        if (n == null || n.isNull()) throw BusinessException.validation("Rate provider response has no field " + path);
        return new BigDecimal(n.asText());
    }
}
