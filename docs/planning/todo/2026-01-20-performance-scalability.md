# P15: Performance & Scalability Testing

**Priority**: MEDIUM
**Status**: Planning
**Effort**: 1 week

## Goal

Ensure Vauchi performs well under real-world conditions: large contact lists, low-end devices, poor networks, and extended usage.

## Current State

No performance testing exists. Features assume happy path with small data sets.

## Gap Analysis

| Area | Current Coverage | Gap |
|------|------------------|-----|
| Large contact lists | None | 1000+ contacts not tested |
| Sync performance | None | Large batch sync not tested |
| Memory usage | None | No memory profiling |
| Battery drain | None | No battery impact testing |
| Disk space | Partial (device_management) | Not comprehensive |
| Startup time | None | Cold/warm start not measured |
| Network degradation | None | Slow/lossy network not tested |

## Feature Scenarios to Add

### Add to `features/contacts_management.feature`:

```gherkin
@performance @scale
Scenario: Handle 1000+ contacts
  Given I have 1000 contacts
  When I open the contacts list
  Then the list should render within 500ms
  And scrolling should be smooth (60fps)
  And search should return results within 200ms

@performance @scale
Scenario: Handle 5000 contacts
  Given I have 5000 contacts
  When I search for a contact
  Then results should appear within 500ms
  And the app should not become unresponsive

@performance @memory
Scenario: Memory usage with large contact list
  Given I have 1000 contacts with avatars
  Then memory usage should stay under 200MB
  And no memory warnings should occur on iOS
  And no OOM kills should occur on Android
```

### Add to `features/sync_updates.feature`:

```gherkin
@performance @sync
Scenario: Sync large batch of updates
  Given I was offline for 7 days
  And I have 100 pending updates to receive
  When I come online
  Then all updates should sync within 60 seconds
  And the UI should remain responsive during sync
  And progress should be indicated

@performance @sync
Scenario: Handle rapid successive updates
  Given Alice updates her card 10 times in 1 minute
  When I receive all updates
  Then only the final state should be stored
  And intermediate updates should be coalesced
  And the app should not lag
```

### Add to `features/device_management.feature`:

```gherkin
@performance @storage
Scenario: Handle low disk space
  Given device has less than 50MB free space
  When I try to sync updates
  Then I should see a warning about low space
  And critical operations should still work
  And cache should be cleared first

@performance @battery
Scenario: Background sync is battery efficient
  Given the app is running in background
  When background sync occurs hourly
  Then battery drain should be less than 1% per day
  And no excessive wake locks should occur
```

### Add new `features/performance.feature`:

```gherkin
@performance
Feature: Performance Requirements
  As a Vauchi user
  I want the app to be fast and efficient
  So that it doesn't impact my device negatively

  @startup
  Scenario: Cold start time
    Given the app is not in memory
    When I launch the app
    Then it should be interactive within 2 seconds
    And the contacts list should be visible within 3 seconds

  @startup
  Scenario: Warm start time
    Given the app was recently used
    When I switch back to the app
    Then it should be interactive within 500ms

  @network
  Scenario: Handle slow network
    Given network latency is 2000ms
    When I perform a sync
    Then operations should not timeout prematurely
    And progress should be indicated
    And I can cancel if needed

  @network
  Scenario: Handle packet loss
    Given network has 10% packet loss
    When I send an update
    Then the update should eventually succeed
    And retries should be automatic
    And the user should not see repeated errors

  @network
  Scenario: Handle offline gracefully
    Given I suddenly lose network
    When I try to sync
    Then I should see an offline indicator
    And operations should be queued
    And no error dialogs should spam

  @resource
  Scenario: CPU usage during idle
    Given the app is open but idle
    Then CPU usage should be near 0%
    And no unnecessary background processing

  @resource
  Scenario: Memory released on background
    Given the app moves to background
    Then memory should be released for images/cache
    And core data should be preserved
    And re-foregrounding should be fast
```

## Implementation Plan

### Phase 1: Tooling Setup (2 days)

**Tasks:**
- [ ] Set up performance test harness
- [ ] Create large contact fixture generator
- [ ] Set up memory profiling (Instruments on iOS, Android Profiler)
- [ ] Set up network condition simulation
- [ ] Define performance budgets

**Fixture Generator:**
```bash
# Generate 1000 synthetic contacts for testing
just generate-test-contacts 1000
```

### Phase 2: Contact List Performance (2 days)

**Tasks:**
- [ ] Profile contact list with 1000+ contacts
- [ ] Implement virtualized/lazy list if needed
- [ ] Optimize search indexing
- [ ] Profile memory with large avatar cache
- [ ] Test on low-end devices

**Targets:**
| Metric | Target | Low-end Target |
|--------|--------|----------------|
| List render | < 500ms | < 1000ms |
| Scroll FPS | 60 | 30+ |
| Search latency | < 200ms | < 500ms |
| Memory | < 200MB | < 150MB |

### Phase 3: Sync Performance (2 days)

**Tasks:**
- [ ] Profile sync with 100+ pending updates
- [ ] Implement batch processing
- [ ] Add sync progress indicator
- [ ] Test sync coalescing
- [ ] Measure battery impact of background sync

### Phase 4: Startup & Resource Optimization (1 day)

**Tasks:**
- [ ] Profile cold/warm start times
- [ ] Lazy load non-critical features
- [ ] Optimize asset loading
- [ ] Verify memory release on background
- [ ] Test on low-memory devices

## Testing Matrix

| Device Class | Memory | Storage | Test Priority |
|--------------|--------|---------|---------------|
| High-end | 8GB+ | 128GB+ | Medium |
| Mid-range | 4GB | 64GB | High |
| Low-end | 2-3GB | 32GB | Critical |

## Metrics & Budgets

| Metric | Budget | Measurement |
|--------|--------|-------------|
| Cold start | < 2s | Time to interactive |
| Warm start | < 500ms | Time to interactive |
| Scroll FPS | > 55fps | Frame time < 18ms |
| Search latency | < 200ms | P95 |
| Memory (idle) | < 100MB | RSS |
| Memory (active) | < 200MB | RSS |
| Battery (bg/day) | < 1% | System battery stats |
| Sync (100 updates) | < 60s | End-to-end |

## Reporting

Create automated performance report:
```bash
just perf-report

# Output:
# Performance Report - 2026-01-22
# ================================
# Cold Start: 1.8s ✓
# Warm Start: 450ms ✓
# Search (1000 contacts): 180ms ✓
# Memory Peak: 165MB ✓
# Battery (24h bg): 0.7% ✓
```

## Dependencies

- Test devices for each tier
- CI performance regression testing (optional)
