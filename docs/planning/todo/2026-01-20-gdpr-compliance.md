# P16: GDPR & Privacy Compliance

**Priority**: HIGH (for EU launch)
**Status**: Planning
**Effort**: 1 week

## Goal

Ensure Vauchi complies with GDPR and other privacy regulations, with clear user controls over their data.

## Current State

| Requirement | Status | Notes |
|-------------|--------|-------|
| E2E encryption | ✓ Complete | No server-side access to content |
| Minimal data collection | ✓ By design | Only encrypted blobs on relay |
| Data export | ✗ Missing | No user export feature |
| Data deletion | ✗ Missing | No self-service deletion |
| Privacy policy | Partial | Exists but needs review |
| Consent flows | ✗ Missing | No explicit consent collection |

## GDPR Requirements

| Article | Requirement | Vauchi Status |
|---------|-------------|---------------|
| Art. 5 | Lawfulness, purpose limitation | ✓ Clear purpose |
| Art. 6 | Lawful basis for processing | ✓ Legitimate interest / consent |
| Art. 7 | Conditions for consent | ✗ Need consent flow |
| Art. 12-14 | Transparent information | ✓ Privacy policy |
| Art. 15 | Right of access | ✗ Need export |
| Art. 16 | Right to rectification | ✓ Users edit their own data |
| Art. 17 | Right to erasure | ✗ Need deletion |
| Art. 20 | Right to data portability | ✗ Need export |
| Art. 25 | Privacy by design | ✓ E2E encryption |
| Art. 32 | Security of processing | ✓ Encryption, access control |

## Feature Scenarios to Add

### Add to `features/identity_management.feature` or new `features/privacy_compliance.feature`:

```gherkin
@gdpr @privacy
Feature: Privacy Compliance
  As a Vauchi user
  I want control over my personal data
  So that my privacy rights are respected

  # Data Export

  @export
  Scenario: Export all my data
    Given I have an identity with contacts and settings
    When I go to Settings > Privacy > Export My Data
    And I confirm the export
    Then I should receive a downloadable file
    And the file should contain all my personal data
    And the file should be in a machine-readable format (JSON)

  @export
  Scenario: Export includes all data types
    When I export my data
    Then the export should include:
      | Data Type | Included |
      | My contact card | Yes |
      | My contacts list | Yes |
      | My settings | Yes |
      | My device list | Yes |
      | My visibility labels | Yes |
      | Update history | Yes |
      | Recovery configuration | Yes |
    And the export should NOT include contacts' private data
    And the export should be encrypted with my key

  @export
  Scenario: Export is protected
    Given I request a data export
    Then I should be required to authenticate
    And the export file should be encrypted
    And a notification should be sent to all my devices

  # Data Deletion

  @deletion
  Scenario: Delete my account
    Given I have an identity
    When I go to Settings > Privacy > Delete Account
    And I confirm deletion twice
    Then my identity should be deleted locally
    And my data should be removed from all relays
    And my contacts should be notified I'm gone
    And I should return to the welcome screen

  @deletion
  Scenario: Deletion is thorough
    When I delete my account
    Then all local data should be wiped
    And keychain/keystore entries should be removed
    And cached files should be deleted
    And no personal data should remain on device

  @deletion
  Scenario: Deletion notifies contacts
    Given Alice has my contact
    When I delete my account
    Then Alice should receive a notification
    And my card in Alice's contacts should be marked "Deleted"
    And Alice cannot send me updates

  @deletion
  Scenario: Grace period before permanent deletion
    When I request account deletion
    Then there should be a 7-day grace period
    And I should be able to cancel during this period
    And after 7 days deletion should be permanent

  # Consent

  @consent
  Scenario: Consent collected on first launch
    Given I am launching the app for the first time
    When I reach the terms screen
    Then I should see a clear privacy policy summary
    And I should explicitly agree to the terms
    And my consent should be recorded with timestamp

  @consent
  Scenario: Consent for optional features
    Given I want to enable usage telemetry
    When I toggle the telemetry option
    Then I should see what data would be collected
    And I should explicitly consent
    And I should be able to withdraw consent later

  @consent
  Scenario: Consent withdrawal
    Given I previously consented to telemetry
    When I disable telemetry in settings
    Then data collection should stop immediately
    And I should be able to request deletion of collected data

  # Privacy Information

  @transparency
  Scenario: View privacy policy in app
    When I go to Settings > Privacy Policy
    Then I should see the full privacy policy
    And it should be in my language
    And it should be understandable

  @transparency
  Scenario: View what data is stored
    When I go to Settings > Privacy > My Data
    Then I should see a summary of stored data:
      | Category | Description |
      | Identity | Your contact card and keys |
      | Contacts | People you've exchanged with |
      | Devices | Your linked devices |
      | Settings | Your preferences |
    And I should see data is E2E encrypted

  # Data Retention

  @retention
  Scenario: Relay data expires
    Given I sent an update via relay
    When 30 days pass without delivery
    Then the update should be automatically deleted
    And no personal data should persist on relays

  @retention
  Scenario: Local data persists until deleted
    Given I have contacts and settings
    Then local data should persist indefinitely
    Until I explicitly delete it
    And no automatic purging should occur

  # Third-Party Sharing

  @sharing
  Scenario: No data sold to third parties
    Then Vauchi should never sell personal data
    And no advertising profiles should be created
    And no data should be shared for marketing

  @sharing
  Scenario: No tracking across apps
    Then Vauchi should not track users across apps
    And no device fingerprinting should occur
    And no advertising IDs should be used
```

## Implementation Plan

### Phase 1: Data Export (3 days)

**Tasks:**
- [ ] Create export format specification (JSON schema)
- [ ] Implement export function in core
- [ ] Add Settings > Privacy > Export My Data UI
- [ ] Encrypt export with user's key
- [ ] Add authentication requirement
- [ ] Add multi-device notification

**Export Format:**
```json
{
  "version": "1.0",
  "exported_at": "2026-01-22T12:00:00Z",
  "identity": {
    "public_id": "...",
    "card": { /* full card data */ },
    "created_at": "..."
  },
  "contacts": [
    {
      "public_id": "...",
      "display_name": "...",
      "card": { /* their card as I see it */ },
      "added_at": "...",
      "visibility_label": "..."
    }
  ],
  "devices": [ /* linked devices */ ],
  "settings": { /* all settings */ },
  "visibility_labels": [ /* label definitions */ ],
  "recovery_config": { /* recovery setup */ }
}
```

### Phase 2: Account Deletion (2 days)

**Tasks:**
- [ ] Implement local data wipe
- [ ] Implement relay data deletion request
- [ ] Add contact notification on deletion
- [ ] Add 7-day grace period
- [ ] Add confirmation flow (2-step)
- [ ] Test thorough deletion (forensic check)

### Phase 3: Consent Flows (2 days)

**Tasks:**
- [ ] Add terms acceptance on first launch
- [ ] Record consent with timestamp
- [ ] Add consent for optional features (telemetry)
- [ ] Implement consent withdrawal
- [ ] Add privacy policy viewer in-app

### Phase 4: Privacy Dashboard (1 day)

**Tasks:**
- [ ] Add Settings > Privacy section
- [ ] Show data categories stored
- [ ] Link to export/delete
- [ ] Show relay data status
- [ ] Show consent status

## Privacy Policy Updates

The privacy policy should clearly state:
1. What data is collected (minimal: encrypted blobs)
2. What data is stored locally (identity, contacts, settings)
3. How data is protected (E2E encryption)
4. User rights (export, delete, correct)
5. Third-party sharing (none)
6. Data retention (relay TTL, local until deleted)
7. Contact information for privacy requests

## Testing

### Manual Testing
- [ ] Export data, verify completeness
- [ ] Delete account, verify thorough wipe
- [ ] Forensic check: no data remains in SQLite, caches, logs
- [ ] Consent flow works correctly
- [ ] Privacy dashboard shows accurate info

### Automated Testing
```gherkin
# Run all privacy compliance scenarios
just test-features --tags=@gdpr
```

## Dependencies

- Legal review of privacy policy
- Consent recording mechanism
- Relay deletion API

## References

- [GDPR Full Text](https://gdpr.eu/)
- [Apple App Store Privacy Guidelines](https://developer.apple.com/app-store/app-privacy-details/)
- [Google Play Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469)
