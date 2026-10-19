package com.aijewel.erp.backup;

import java.util.List;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
public class BackupController {
    private final BackupService backups;

    public BackupController(BackupService backups) {
        this.backups = backups;
    }

    @GetMapping("/api/backup")
    public Map<String, Object> log() {
        List<Map<String, Object>> log = backups.log();
        return Map.of("target_dir", backups.targetDir().toAbsolutePath().toString(), "log", log);
    }

    /** Owner takes a full encrypted backup to the USB folder in one step. */
    @PostMapping("/api/backup")
    public Map<String, Object> backup(@RequestBody Map<String, String> body) {
        return backups.backup(body.get("password"), body.get("target_dir"));
    }

    /** Copy of a backup through the browser, for saving to a USB drive on any computer or phone. */
    @GetMapping("/api/backup/download")
    public ResponseEntity<byte[]> download(@RequestParam String file) {
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + file.replaceAll("[^A-Za-z0-9_.-]", "") + "\"")
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(backups.download(file));
    }

    @PostMapping("/api/backup/verify")
    public Map<String, Object> verify(@RequestParam("file") MultipartFile file, @RequestParam String password) throws Exception {
        return backups.inspect(file.getBytes(), password);
    }

    @PostMapping("/api/platform/restore")
    public Map<String, Object> restore(@RequestParam("file") MultipartFile file, @RequestParam String password,
                                       @RequestParam("code") String code,
                                       @RequestParam(value = "storageMode", defaultValue = "LOCAL") String storageMode) throws Exception {
        return backups.restoreAsNewShop(file.getBytes(), password, code, storageMode);
    }
}
