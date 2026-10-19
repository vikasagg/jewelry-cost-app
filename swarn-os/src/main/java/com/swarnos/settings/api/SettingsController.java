package com.swarnos.settings.api;

import com.swarnos.settings.domain.Setting;
import com.swarnos.settings.service.SettingsService;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/config")
public class SettingsController {
    private final SettingsService settings;

    public SettingsController(SettingsService settings) {
        this.settings = settings;
    }

    @GetMapping
    public List<Setting> all() {
        return settings.all();
    }

    /** Body: {"setting.key": "new value", ...} */
    @PutMapping
    public Map<String, Integer> update(@RequestBody Map<String, String> values) {
        return Map.of("updated", settings.update(values));
    }
}
