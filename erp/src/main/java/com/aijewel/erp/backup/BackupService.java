package com.aijewel.erp.backup;

import com.aijewel.erp.auth.CurrentUser;
import com.aijewel.erp.auth.Permission;
import com.aijewel.erp.common.ApiException;
import com.aijewel.erp.common.AuditService;
import com.aijewel.erp.common.Db;
import com.aijewel.erp.config.ConfigService;
import com.aijewel.erp.tenant.TenantContext;
import com.aijewel.erp.tenant.TenantInfo;
import com.aijewel.erp.tenant.TenantProvisioner;
import com.aijewel.erp.tenant.TenantRegistry;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSetMetaData;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;
import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import javax.sql.DataSource;
import org.springframework.stereotype.Service;

/**
 * One-step encrypted full backup of a shop's database to a USB drive or any
 * folder (BRD FR-SEE-06, owner decision on USB backup). Every backup is
 * checksummed, read back and decrypted as a restore test, and logged.
 * Format: "AIJWBK01" | salt(16) | iv(12) | AES-256-GCM(gzip(JSON)).
 */
@Service
public class BackupService {
    /** Parents before children, so a restore never breaks a foreign key. */
    static final List<String> TABLES = List.of(
            "app_config", "app_user", "audit_log", "doc_sequence", "location", "category", "purity", "party",
            "rate_set", "rate_line", "item", "stone", "stock_movement", "purchase", "purchase_line", "sale", "sale_line",
            "sale_exchange", "payment", "ledger_entry", "repair_job", "repair_event", "tally_session", "tally_expected",
            "tally_scan", "tally_variance", "backup_log");
    private static final byte[] MAGIC = "AIJWBK01".getBytes(StandardCharsets.US_ASCII);

    private final Db db;
    private final ConfigService config;
    private final AuditService audit;
    private final TenantRegistry registry;
    private final TenantProvisioner provisioner;
    private final ObjectMapper json = new ObjectMapper().findAndRegisterModules()
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    public BackupService(Db db, ConfigService config, AuditService audit, TenantRegistry registry,
                         TenantProvisioner provisioner) {
        this.db = db;
        this.config = config;
        this.audit = audit;
        this.registry = registry;
        this.provisioner = provisioner;
    }

    public Path targetDir() {
        String configured = config.get("backup.targetDir", null);
        return configured != null ? Path.of(configured)
                : registry.dataDir().resolve("backups").resolve(TenantContext.require());
    }

    public Map<String, Object> backup(String password, String targetOverride) {
        CurrentUser.require(Permission.BACKUP);
        checkPassword(password);
        String shop = TenantContext.require();
        Path dir = targetOverride == null || targetOverride.isBlank() ? targetDir() : Path.of(targetOverride.trim());
        try {
            Files.createDirectories(dir);
        } catch (Exception e) {
            throw ApiException.bad("Cannot write to " + dir + " - is the USB drive plugged in? (" + e.getMessage() + ")");
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("format", "AI Jewellery ERP backup v1");
        payload.put("shop", shop);
        payload.put("created_at", LocalDateTime.now().toString());
        payload.put("created_by", CurrentUser.usernameOrSystem());
        Map<String, List<Map<String, Object>>> tables = new LinkedHashMap<>();
        long rows = 0;
        for (String t : TABLES) {
            List<Map<String, Object>> data = db.rows("SELECT * FROM " + t);
            tables.put(t, data);
            rows += data.size();
        }
        payload.put("tables", tables);

        try {
            byte[] encrypted = encrypt(json.writeValueAsBytes(payload), password);
            String name = shop + "_" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss")) + ".jbk";
            Path file = dir.resolve(name);
            Files.write(file, encrypted);
            String sha = sha256(encrypted);
            Files.writeString(dir.resolve(name + ".sha256"), sha + "  " + name + System.lineSeparator());

            // Restore test: read the file back from the drive, check the checksum, decrypt and count every row.
            byte[] readBack = Files.readAllBytes(file);
            Map<String, Object> check = inspect(readBack, password);
            boolean verified = sha.equals(sha256(readBack)) && ((Number) check.get("rows")).longValue() == rows;

            db.update("INSERT INTO backup_log (username, file_name, target, size_bytes, sha256, row_count, verified) VALUES (?,?,?,?,?,?,?)",
                    CurrentUser.usernameOrSystem(), name, dir.toAbsolutePath().toString(), (long) encrypted.length, sha, rows, verified);
            audit.log("BACKUP", "backup", name, "rows " + rows + ", verified " + verified + ", to " + dir.toAbsolutePath());
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("file", name);
            out.put("path", file.toAbsolutePath().toString());
            out.put("size_bytes", encrypted.length);
            out.put("sha256", sha);
            out.put("rows", rows);
            out.put("verified", verified);
            return out;
        } catch (ApiException e) {
            throw e;
        } catch (Exception e) {
            throw ApiException.bad("Backup failed: " + e.getMessage());
        }
    }

    public byte[] download(String fileName) {
        CurrentUser.require(Permission.BACKUP);
        Map<String, Object> log = db.one("SELECT * FROM backup_log WHERE file_name = ? ORDER BY id DESC", "Backup not found", fileName);
        try {
            return Files.readAllBytes(Path.of((String) log.get("target")).resolve(fileName));
        } catch (Exception e) {
            throw ApiException.notFound("The backup file is no longer at " + log.get("target") + " (USB removed?).");
        }
    }

    /** Opens a backup file and reports what is inside, without changing anything. */
    public Map<String, Object> inspect(byte[] file, String password) {
        Map<String, Object> payload = read(file, password);
        Map<?, ?> tables = (Map<?, ?>) payload.get("tables");
        Map<String, Object> counts = new LinkedHashMap<>();
        long rows = 0;
        for (Map.Entry<?, ?> e : tables.entrySet()) {
            int n = ((List<?>) e.getValue()).size();
            counts.put(e.getKey().toString(), n);
            rows += n;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("shop", payload.get("shop"));
        out.put("created_at", payload.get("created_at"));
        out.put("created_by", payload.get("created_by"));
        out.put("sha256", sha256(file));
        out.put("rows", rows);
        out.put("tables", counts);
        return out;
    }

    /**
     * Restores a backup as a new shop (platform operator). Restoring into a new
     * shop code never overwrites live data; the operator switches over once checked.
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> restoreAsNewShop(byte[] file, String password, String newCode, String storageMode) {
        Map<String, Object> payload = read(file, password);
        Map<String, List<Map<String, Object>>> tables = (Map<String, List<Map<String, Object>>>) payload.get("tables");
        String tempPassword = HexFormat.of().formatHex(new SecureRandom().generateSeed(6));
        TenantInfo t = provisioner.create(new TenantProvisioner.NewTenant(newCode, "Restored " + payload.get("shop"),
                storageMode, "restore-admin", "Restore admin", tempPassword));
        DataSource ds = registry.dataSource(t.code());
        try (Connection c = ds.getConnection()) {
            c.setAutoCommit(false);
            List<String> reversed = new ArrayList<>(TABLES);
            java.util.Collections.reverse(reversed);
            for (String table : reversed) {
                try (var st = c.createStatement()) {
                    st.executeUpdate("DELETE FROM " + table);
                }
            }
            long rows = 0;
            for (String table : TABLES) {
                List<Map<String, Object>> data = tables.getOrDefault(table, List.of());
                rows += insertAll(c, table, data);
            }
            for (String table : TABLES) resetIdentity(c, table, t.storageMode());
            c.commit();
            return Map.of("code", t.code(), "rows", rows, "note",
                    "Restored. Sign in with the users from the backup (the original passwords).");
        } catch (Exception e) {
            throw ApiException.bad("Restore failed: " + e.getMessage());
        }
    }

    private long insertAll(Connection c, String table, List<Map<String, Object>> data) throws Exception {
        if (data.isEmpty()) return 0;
        Map<String, Integer> types = new LinkedHashMap<>();
        try (var st = c.createStatement(); var rs = st.executeQuery("SELECT * FROM " + table + " WHERE 1 = 0")) {
            ResultSetMetaData md = rs.getMetaData();
            for (int i = 1; i <= md.getColumnCount(); i++) types.put(md.getColumnName(i).toLowerCase(), md.getColumnType(i));
        }
        List<String> cols = new ArrayList<>(types.keySet());
        String sql = "INSERT INTO " + table + " (" + String.join(",", cols) + ") VALUES ("
                + String.join(",", java.util.Collections.nCopies(cols.size(), "?")) + ")";
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            for (Map<String, Object> row : data) {
                for (int i = 0; i < cols.size(); i++) {
                    Object v = row.get(cols.get(i));
                    int type = types.get(cols.get(i));
                    if (v == null) ps.setNull(i + 1, type);
                    else ps.setObject(i + 1, convert(v, type), type);
                }
                ps.addBatch();
            }
            ps.executeBatch();
        }
        return data.size();
    }

    private static Object convert(Object v, int type) {
        String s = v.toString();
        return switch (type) {
            case Types.NUMERIC, Types.DECIMAL -> new BigDecimal(s);
            case Types.INTEGER, Types.SMALLINT -> Integer.valueOf(s);
            case Types.BIGINT -> Long.valueOf(s);
            case Types.BOOLEAN, Types.BIT -> Boolean.valueOf(s);
            case Types.DATE -> java.sql.Date.valueOf(s.substring(0, 10));
            case Types.TIMESTAMP, Types.TIMESTAMP_WITH_TIMEZONE -> v instanceof Number n ? new Timestamp(n.longValue())
                    : Timestamp.from(java.time.OffsetDateTime.parse(s.length() == 19 ? s + "Z" : s.replace("+0000", "+00:00")).toInstant());
            default -> s;
        };
    }

    private static void resetIdentity(Connection c, String table, String mode) throws Exception {
        boolean hasId;
        try (var st = c.createStatement(); var rs = st.executeQuery("SELECT * FROM " + table + " WHERE 1 = 0")) {
            hasId = rs.getMetaData().getColumnName(1).equalsIgnoreCase("id")
                    && rs.getMetaData().getColumnType(1) == Types.BIGINT;
        }
        if (!hasId) return;
        long next;
        try (var st = c.createStatement(); var rs = st.executeQuery("SELECT COALESCE(MAX(id), 0) + 1 FROM " + table)) {
            rs.next();
            next = rs.getLong(1);
        }
        try (var st = c.createStatement()) {
            if (mode.equals("CLOUD")) {
                st.execute("SELECT setval(pg_get_serial_sequence('" + table + "', 'id'), " + next + ", false)");
            } else {
                st.execute("ALTER TABLE " + table + " ALTER COLUMN id RESTART WITH " + next);
            }
        }
    }

    // ---------- file format ----------

    static byte[] encrypt(byte[] plain, String password) throws Exception {
        SecureRandom random = new SecureRandom();
        byte[] salt = new byte[16], iv = new byte[12];
        random.nextBytes(salt);
        random.nextBytes(iv);
        ByteArrayOutputStream zipped = new ByteArrayOutputStream();
        try (GZIPOutputStream gz = new GZIPOutputStream(zipped)) {
            gz.write(plain);
        }
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key(password, salt), new GCMParameterSpec(128, iv));
        byte[] body = cipher.doFinal(zipped.toByteArray());
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(MAGIC);
        out.write(salt);
        out.write(iv);
        out.write(body);
        return out.toByteArray();
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> read(byte[] file, String password) {
        if (file.length < MAGIC.length + 28 || !Arrays.equals(Arrays.copyOf(file, MAGIC.length), MAGIC)) {
            throw ApiException.bad("This is not an AI Jewellery ERP backup file.");
        }
        try {
            byte[] salt = Arrays.copyOfRange(file, 8, 24);
            byte[] iv = Arrays.copyOfRange(file, 24, 36);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(password, salt), new GCMParameterSpec(128, iv));
            byte[] zipped = cipher.doFinal(file, 36, file.length - 36);
            try (GZIPInputStream gz = new GZIPInputStream(new ByteArrayInputStream(zipped))) {
                return json.readValue(gz.readAllBytes(), Map.class);
            }
        } catch (javax.crypto.AEADBadTagException e) {
            throw ApiException.bad("Wrong backup password, or the file is damaged.");
        } catch (Exception e) {
            throw ApiException.bad("Could not read the backup: " + e.getMessage());
        }
    }

    private static SecretKeySpec key(String password, byte[] salt) throws Exception {
        SecretKeyFactory f = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256");
        byte[] k = f.generateSecret(new PBEKeySpec(password.toCharArray(), salt, 120_000, 256)).getEncoded();
        return new SecretKeySpec(k, "AES");
    }

    static String sha256(byte[] data) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static void checkPassword(String password) {
        if (password == null || password.length() < 6) throw ApiException.bad("Backup password must have at least 6 characters.");
    }

    public List<Map<String, Object>> log() {
        CurrentUser.require(Permission.BACKUP);
        return db.rows("SELECT * FROM backup_log ORDER BY id DESC");
    }
}
