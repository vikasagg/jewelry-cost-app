package com.aijewel.erp.rates;

import com.aijewel.erp.common.ApiException;
import com.aijewel.erp.common.Num;
import com.aijewel.erp.config.ConfigService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.math.BigDecimal;
import java.time.Duration;
import org.springframework.stereotype.Component;

/**
 * Generic JSON feed: reads three per-gram values from configurable fields
 * (dotted paths such as "data.gold.24k"), so any licensed provider can be
 * plugged in through Settings without code changes.
 */
@Component
public class HttpJsonRateProvider implements MetalRateProvider {
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final ObjectMapper json = new ObjectMapper();

    @Override
    public String code() {
        return "HTTP";
    }

    @Override
    public LiveRates fetch(ConfigService config, LiveRates last) {
        String url = config.get("rate.live.url", null);
        if (url == null) throw ApiException.bad("Set rate.live.url in Settings first.");
        try {
            HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(15)).GET().build(), HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() != 200) throw ApiException.bad("Rate provider answered HTTP " + res.statusCode());
            JsonNode root = json.readTree(res.body());
            return new LiveRates(
                    read(root, config.get("rate.live.goldField", "gold24k")),
                    read(root, config.get("rate.live.silverField", "silver")),
                    read(root, config.get("rate.live.platinumField", "platinum")),
                    URI.create(url).getHost());
        } catch (ApiException e) {
            throw e;
        } catch (Exception e) {
            throw ApiException.bad("Could not read the live rate: " + e.getMessage());
        }
    }

    private static BigDecimal read(JsonNode root, String path) {
        JsonNode n = root;
        for (String part : path.split("\\.")) n = n == null ? null : n.get(part);
        if (n == null || n.isNull()) throw ApiException.bad("Rate provider response has no field " + path);
        return Num.of(n.asText());
    }
}
