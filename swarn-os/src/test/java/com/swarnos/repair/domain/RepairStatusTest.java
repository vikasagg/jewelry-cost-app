package com.swarnos.repair.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class RepairStatusTest {
    @Test
    void allowedMoves() {
        assertThat(RepairStatus.RECEIVED.canMoveTo(RepairStatus.WITH_KARIGAR)).isTrue();
        assertThat(RepairStatus.WITH_KARIGAR.canMoveTo(RepairStatus.READY)).isTrue();
        assertThat(RepairStatus.READY.canMoveTo(RepairStatus.DELIVERED)).isTrue();
        assertThat(RepairStatus.RECEIVED.canMoveTo(RepairStatus.DELIVERED)).isFalse();
        assertThat(RepairStatus.DELIVERED.canMoveTo(RepairStatus.RECEIVED)).isFalse();
    }

    @Test
    void onlyPiecesInTheShopCountInTheRepairBucket() {
        assertThat(RepairStatus.READY.isInShop()).isTrue();
        assertThat(RepairStatus.WITH_KARIGAR.isInShop()).isFalse();
        assertThat(RepairStatus.DELIVERED.isInShop()).isFalse();
    }
}
