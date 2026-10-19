package com.swarnos.backup.api;

import com.swarnos.backup.api.dto.BackupOverview;
import com.swarnos.backup.api.dto.BackupRequest;
import com.swarnos.backup.domain.BackupInspection;
import com.swarnos.backup.domain.BackupResult;
import com.swarnos.backup.domain.RestoreResult;
import com.swarnos.backup.service.BackupService;
import com.swarnos.tenant.domain.StorageMode;
import java.io.IOException;
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
    public BackupOverview overview() {
        return new BackupOverview(backups.targetDir().toAbsolutePath().toString(), backups.history());
    }

    /** Owner takes a full encrypted backup to the USB folder in one step. */
    @PostMapping("/api/backup")
    public BackupResult backup(@RequestBody BackupRequest req) {
        return backups.backup(req.password(), req.targetDir());
    }

    /** A copy through the browser, for saving to a USB drive on any computer or phone. */
    @GetMapping("/api/backup/download")
    public ResponseEntity<byte[]> download(@RequestParam String file) {
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + file.replaceAll("[^A-Za-z0-9_.-]", "") + "\"")
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(backups.download(file));
    }

    @PostMapping("/api/backup/verify")
    public BackupInspection verify(@RequestParam("file") MultipartFile file, @RequestParam String password) throws IOException {
        return backups.inspect(file.getBytes(), password);
    }

    @PostMapping("/api/platform/restore")
    public RestoreResult restore(@RequestParam("file") MultipartFile file, @RequestParam String password,
                                 @RequestParam String code,
                                 @RequestParam(name = "storage_mode", defaultValue = "LOCAL") StorageMode storageMode) throws IOException {
        return backups.restoreAsNewShop(file.getBytes(), password, code, storageMode);
    }
}
