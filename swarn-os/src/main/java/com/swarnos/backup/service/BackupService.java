package com.swarnos.backup.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.swarnos.backup.domain.BackupCodec;
import com.swarnos.backup.domain.BackupContents;
import com.swarnos.backup.domain.BackupInspection;
import com.swarnos.backup.domain.BackupLogEntry;
import com.swarnos.backup.domain.BackupResult;
import com.swarnos.backup.domain.BackupTables;
import com.swarnos.backup.domain.RestoreResult;
import com.swarnos.backup.repository.BackupLogRepository;
import com.swarnos.backup.repository.DatabaseSnapshotRepository;
import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.service.SettingsService;
import com.swarnos.tenant.domain.StorageMode;
import com.swarnos.tenant.domain.Tenant;
import com.swarnos.tenant.infrastructure.DataPaths;
import com.swarnos.tenant.infrastructure.TenantContext;
import com.swarnos.tenant.service.TenantProvisioningService;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;

/**
 * One-step encrypted full backup of a shop to a USB drive or any folder (owner
 * decision D-13). Each backup is checksummed, read back and decrypted as a
 * restore test, and logged. A restore always goes into a new shop.
 */
@Service
public class BackupService {
    private static final DateTimeFormatter STAMP = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss");

    private final DatabaseSnapshotRepository snapshots;
    private final BackupLogRepository log;
    private final SettingsService settings;
    private final TenantProvisioningService provisioning;
    private final DataPaths paths;
    private final AuditService audit;
    private final ObjectMapper json = new ObjectMapper().findAndRegisterModules()
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    public BackupService(DatabaseSnapshotRepository snapshots, BackupLogRepository log, SettingsService settings,
                         TenantProvisioningService provisioning, DataPaths paths, AuditService audit) {
        this.snapshots = snapshots;
        this.log = log;
        this.settings = settings;
        this.provisioning = provisioning;
        this.paths = paths;
        this.audit = audit;
    }

    public Path targetDir() {
        return settings.text(SettingKeys.BACKUP_TARGET_DIR).map(Path::of).orElse(paths.defaultBackupDir(TenantContext.require()));
    }

    public BackupResult backup(String password, String targetOverride) {
        CurrentUser.require(Permission.BACKUP);
        BackupCodec.checkPassword(password);
        String shop = TenantContext.require();
        Path dir = targetOverride == null || targetOverride.isBlank() ? targetDir() : Path.of(targetOverride.trim());
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            throw BusinessException.validation("Cannot write to " + dir + " - is the USB drive plugged in? (" + e.getMessage() + ")");
        }
        BackupContents contents = new BackupContents(BackupContents.FORMAT, shop, LocalDateTime.now().toString(),
                CurrentUser.usernameOrSystem(), snapshots.export(BackupTables.ALL));
        try {
            byte[] file = BackupCodec.encrypt(json.writeValueAsBytes(contents), password);
            String name = shop + "_" + LocalDateTime.now().format(STAMP) + BackupCodec.EXTENSION;
            Path path = dir.resolve(name);
            Files.write(path, file);
            String sha = BackupCodec.sha256(file);
            Files.writeString(dir.resolve(name + ".sha256"), sha + "  " + name + System.lineSeparator());

            // Restore test: read the file back from the drive, check its checksum, decrypt and count every row.
            byte[] readBack = Files.readAllBytes(path);
            boolean verified = sha.equals(BackupCodec.sha256(readBack)) && read(readBack, password).rowCount() == contents.rowCount();

            log.insert(CurrentUser.usernameOrSystem(), name, dir.toAbsolutePath().toString(), file.length, sha, contents.rowCount(), verified);
            audit.record("BACKUP", "backup", name, "rows " + contents.rowCount() + ", verified " + verified + ", to " + dir.toAbsolutePath());
            return new BackupResult(name, path.toAbsolutePath().toString(), file.length, sha, contents.rowCount(), verified);
        } catch (IOException e) {
            throw BusinessException.validation("Backup failed: " + e.getMessage());
        }
    }

    public byte[] download(String fileName) {
        CurrentUser.require(Permission.BACKUP);
        BackupLogEntry entry = log.findByFileName(fileName).orElseThrow(() -> BusinessException.notFound("Backup not found"));
        try {
            return Files.readAllBytes(Path.of(entry.target()).resolve(entry.fileName()));
        } catch (IOException e) {
            throw BusinessException.notFound("The backup file is no longer at " + entry.target() + " (USB removed?).");
        }
    }

    /** Opens a backup and reports what is inside, without changing anything. */
    public BackupInspection inspect(byte[] file, String password) {
        BackupContents c = read(file, password);
        Map<String, Integer> counts = new LinkedHashMap<>();
        c.tables().forEach((table, rows) -> counts.put(table, rows.size()));
        return new BackupInspection(c.shop(), c.createdAt(), c.createdBy(), BackupCodec.sha256(file), c.rowCount(), counts);
    }

    /** Loads a backup as a new shop (platform operator); live data is never overwritten. */
    public RestoreResult restoreAsNewShop(byte[] file, String password, String newCode, StorageMode mode) {
        BackupContents contents = read(file, password);
        String tempPassword = HexFormat.of().formatHex(new SecureRandom().generateSeed(6));
        Tenant tenant = provisioning.create(new TenantProvisioningService.NewShop(newCode, "Restored " + contents.shop(), mode,
                "restore-admin", "Restore admin", tempPassword));
        long rows = TenantContext.call(tenant.code(), () -> snapshots.replaceAll(BackupTables.ALL, contents.tables(), tenant.storageMode()));
        return new RestoreResult(tenant.code(), rows, "Restored. Sign in with the users from the backup (their original passwords).");
    }

    public List<BackupLogEntry> history() {
        CurrentUser.require(Permission.BACKUP);
        return log.findAll();
    }

    public Optional<Instant> lastBackupAt() {
        return log.lastBackupAt();
    }

    private BackupContents read(byte[] file, String password) {
        byte[] plain = BackupCodec.decrypt(file, password);
        try {
            return json.readValue(plain, BackupContents.class);
        } catch (IOException e) {
            throw BusinessException.validation("The backup content could not be read: " + e.getMessage());
        }
    }
}
