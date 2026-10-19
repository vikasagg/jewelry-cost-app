package com.swarnos.backup.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

class BackupCodecTest {
    private static final byte[] PLAIN = "{\"shop\":\"demo\",\"rows\":[1,2,3]}".getBytes(StandardCharsets.UTF_8);

    @Test
    void roundTripWithTheRightPassword() {
        byte[] file = BackupCodec.encrypt(PLAIN, "secret99");
        assertThat(new String(file, StandardCharsets.ISO_8859_1)).startsWith("SWARNOS1").doesNotContain("demo");
        assertThat(BackupCodec.decrypt(file, "secret99")).isEqualTo(PLAIN);
    }

    @Test
    void wrongPasswordOrForeignFileIsRejected() {
        byte[] file = BackupCodec.encrypt(PLAIN, "secret99");
        assertThatThrownBy(() -> BackupCodec.decrypt(file, "wrong-pass")).hasMessageContaining("Wrong backup password");
        assertThatThrownBy(() -> BackupCodec.decrypt("not a backup at all, really".getBytes(), "x"))
                .hasMessageContaining("not a Swarn-OS backup");
    }

    @Test
    void shortPasswordsAreRefused() {
        assertThatThrownBy(() -> BackupCodec.encrypt(PLAIN, "123")).hasMessageContaining("at least 6");
    }

    @Test
    void checksumIsStable() {
        assertThat(BackupCodec.sha256(PLAIN)).hasSize(64).isEqualTo(BackupCodec.sha256(PLAIN.clone()));
    }
}
