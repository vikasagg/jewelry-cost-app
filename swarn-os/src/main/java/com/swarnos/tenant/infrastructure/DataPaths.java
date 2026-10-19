package com.swarnos.tenant.infrastructure;

import com.swarnos.common.config.AppProperties;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.springframework.stereotype.Component;

/** The data folder: control database, local shop databases and default backup folder. */
@Component
public class DataPaths {
    private final Path root;

    public DataPaths(AppProperties props) {
        this.root = Path.of(props.dataDir()).toAbsolutePath().normalize();
        try {
            Files.createDirectories(root.resolve("tenants"));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Path root() {
        return root;
    }

    public Path defaultBackupDir(String tenant) {
        return root.resolve("backups").resolve(tenant);
    }

    public static String h2Url(Path file) {
        return "jdbc:h2:file:" + file + ";MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DEFAULT_NULL_ORDERING=HIGH";
    }
}
