package com.swarnos.rates.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.rates.domain.RateSet;
import com.swarnos.rates.domain.RateSetStatus;
import com.swarnos.rates.domain.RateSource;
import com.swarnos.rates.repository.RateRepository;
import com.swarnos.security.AuthUser;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Role;
import com.swarnos.settings.service.MasterDataService;
import com.swarnos.settings.service.SettingsService;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** Business rules of the daily rate, with the repository mocked out. */
class RateServiceTest {
    private static final LocalDate TODAY = LocalDate.of(2026, 10, 19);

    private final RateRepository repository = mock(RateRepository.class);
    private final MasterDataService masters = mock(MasterDataService.class);
    private final BusinessClock clock = mock(BusinessClock.class);
    private RateService service;

    @BeforeEach
    void setUp() {
        when(clock.today()).thenReturn(TODAY);
        when(clock.now()).thenReturn(Instant.parse("2026-10-19T03:00:00Z"));
        when(masters.activePurities()).thenReturn(List.of());
        service = new RateService(repository, masters, mock(SettingsService.class), mock(AuditService.class), clock, List.of());
    }

    @AfterEach
    void signOut() {
        CurrentUser.clear();
    }

    private static RateSet set(RateSetStatus status, LocalDate date) {
        return new RateSet(5, date, RateSource.LIVE, "feed", new BigDecimal("7500"), new BigDecimal("92"), new BigDecimal("3100"),
                status, "manager", null, null, null, null);
    }

    @Test
    void approvingSupersedesTheEarlierRateOfTheDay() {
        CurrentUser.set(new AuthUser("demo", "owner", "Owner", Role.OWNER));
        when(repository.findById(5)).thenReturn(Optional.of(set(RateSetStatus.PROPOSED, TODAY)));
        service.approve(5);
        verify(repository).supersedeApproved(TODAY);
        verify(repository).replaceLines(eq(5L), anyList());
        verify(repository).decide(eq(5L), eq(RateSetStatus.APPROVED), eq("owner"), any());
    }

    @Test
    void salespersonCannotApprove() {
        CurrentUser.set(new AuthUser("demo", "sales", "Sales", Role.SALES));
        assertThatThrownBy(() -> service.approve(5)).isInstanceOf(BusinessException.class).hasMessageContaining("RATE_APPROVE");
        verify(repository, never()).decide(any(Long.class), any(), any(), any());
    }

    @Test
    void yesterdaysProposalCannotBeApprovedToday() {
        when(repository.findById(5)).thenReturn(Optional.of(set(RateSetStatus.PROPOSED, TODAY.minusDays(1))));
        assertThatThrownBy(() -> service.approve(5)).hasMessageContaining("another day");
    }

    @Test
    void billingWaitsForAnApprovedRate() {
        when(repository.findApproved(TODAY)).thenReturn(Optional.empty());
        assertThatThrownBy(service::requireTodayRates).hasMessageContaining("not approved yet");
    }
}
