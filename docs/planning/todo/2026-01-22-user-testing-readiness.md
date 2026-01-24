# User Testing Readiness

**Status**: TODO
**Priority**: HIGH
**Effort**: ~1 week

## Goal

Prepare vauchi for user testing by implementing features that:
1. Help users understand the value proposition without needing a second person
2. Provide self-serve answers to common questions
3. Create "aha moments" that reinforce why vauchi matters

## Current State

- **Onboarding**: Implemented (P17) - 6-step wizard, ~45 seconds to complete
- **Demo contact**: Not implemented (listed in P17 Phase 2)
- **Exchange celebration**: Not implemented
- **In-app help**: Not implemented
- **Contextual feedback**: Minimal - no micro-celebrations or explanatory moments

### The Problem

Users drop off within 3-5 minutes. Vauchi's core value ("I updated my info and everyone sees it instantly") requires:
1. Creating a card
2. Finding someone else with vauchi
3. Exchanging QR codes in person
4. One person updates
5. Other person sees the update

This could take days/weeks before value is demonstrated. For user testing, we need to accelerate the "aha moment" and provide help without human intervention.

## Proposed Solution

Three interconnected features:

### 1. Aha Moments System

Micro-celebrations and explanatory feedback at key points:

| Trigger | Message | Visual |
|---------|---------|--------|
| Card creation complete | "Your card is ready. Anyone who scans this will always have your latest info." | Card preview with subtle pulse |
| First edit after creation | "If anyone had your card, they'd see this change instantly." | Ripple animation |
| First contact added | "You now have [Name]'s card. When they update it, you'll see the change automatically." | Success checkmark |
| First received update | "[Name] updated their card" | Before/after diff, celebration UI |
| First outbound update (with contacts) | "Your update was delivered to X contacts" | Delivery confirmation |

### 2. Demo Contact

A "Vauchi Tips" contact that demonstrates the update flow for solo users:

- Appears after onboarding if no contacts exist
- Periodically "updates" with rotating tips/info
- User experiences the update notification flow
- Clearly marked as demo, dismissible
- Auto-removed after first real exchange

### 3. In-App Help System

Self-serve answers without leaving the app:

| Component | Description |
|-----------|-------------|
| **Contextual tooltips** | First-time hints on key UI elements, dismissible, don't repeat |
| **FAQ section** | Settings > Help with common questions (bundled offline) |
| **Privacy explainer** | Visual diagram of E2E encryption |
| **Onboarding replay** | Settings > Help > Show onboarding again |

#### FAQ Content (Initial)
- "What happens if I lose my phone?"
- "Can someone track me through vauchi?"
- "How do I remove a contact?"
- "What data is stored where?"
- "How do updates reach my contacts?"

## Files to Create/Modify

### Core (vauchi-core)

```
core/vauchi-core/src/
├── aha_moments.rs          # NEW: Aha moment event definitions
├── demo_contact.rs         # NEW: Demo contact logic
└── lib.rs                  # Export new modules
```

### iOS

```
ios/Vauchi/
├── Services/
│   ├── AhaMomentService.swift      # NEW: Track and trigger aha moments
│   └── DemoContactService.swift    # NEW: Manage demo contact
├── Views/
│   ├── AhaMoments/
│   │   ├── AhaMomentOverlay.swift  # NEW: Celebration/feedback overlays
│   │   └── UpdateDiffView.swift    # NEW: Before/after comparison
│   └── Help/
│       ├── HelpView.swift          # NEW: Main help screen
│       ├── FAQView.swift           # NEW: FAQ list with expandable items
│       ├── PrivacyExplainerView.swift  # NEW: E2E visual diagram
│       └── TooltipView.swift       # NEW: Contextual tooltip component
└── Resources/
    └── help_content.json           # NEW: Bundled FAQ content
```

### Android

```
android/app/src/main/kotlin/com/vauchi/
├── service/
│   ├── AhaMomentService.kt         # NEW
│   └── DemoContactService.kt       # NEW
├── ui/
│   ├── aha/
│   │   ├── AhaMomentOverlay.kt     # NEW
│   │   └── UpdateDiffView.kt       # NEW
│   └── help/
│       ├── HelpScreen.kt           # NEW
│       ├── FAQScreen.kt            # NEW
│       ├── PrivacyExplainerScreen.kt   # NEW
│       └── TooltipComponent.kt     # NEW
└── res/raw/
    └── help_content.json           # NEW
```

### Feature Specs

```
features/
├── aha_moments.feature     # NEW: Aha moment scenarios
└── in_app_help.feature     # NEW: Help system scenarios
```

## Implementation Phases

### Phase 1: Aha Moments Foundation (2 days)
1. Define aha moment events in core
2. Create overlay component (iOS + Android)
3. Implement "card creation complete" moment
4. Implement "first edit" moment with ripple animation

### Phase 2: Demo Contact (1.5 days)
1. Implement demo contact in core (static contact with scheduled "updates")
2. iOS: Add demo contact service, integrate with contact list
3. Android: Same
4. Auto-dismiss logic after first real exchange

### Phase 3: Exchange Celebrations (1 day)
1. "First contact added" celebration
2. "First received update" with before/after diff
3. "First outbound update" delivery confirmation

### Phase 4: Help System (1.5 days)
1. Create help content JSON (FAQ items)
2. iOS: HelpView, FAQView, PrivacyExplainerView
3. Android: Equivalent screens
4. Onboarding replay from Settings > Help
5. Contextual tooltips (2-3 key locations)

### Phase 5: Polish & Test (1 day)
1. Animations and transitions
2. Accessibility (VoiceOver/TalkBack for overlays)
3. Integration testing
4. Manual QA walkthrough

## Verification

### Automated Tests

```gherkin
# Aha Moments
Scenario: Card creation shows completion message
Scenario: First edit shows "would update" feedback
Scenario: First received update shows diff view

# Demo Contact
Scenario: Demo contact appears for users with no contacts
Scenario: Demo contact updates trigger notification
Scenario: Demo contact removed after first real exchange

# Help System
Scenario: FAQ accessible from Settings
Scenario: FAQ works offline
Scenario: Onboarding can be replayed
```

### Manual Testing Checklist

- [ ] New user sees all aha moments in sequence
- [ ] Demo contact updates show notification
- [ ] Help FAQ is readable and complete
- [ ] Privacy diagram renders correctly
- [ ] Onboarding replay doesn't lose data
- [ ] Tooltips show once, don't repeat
- [ ] All overlays are dismissible
- [ ] Accessibility: screen readers announce overlays

### Success Metrics (Post User Testing)

- Users can articulate vauchi's value proposition
- <10% of users contact support for basic questions
- Demo contact helps users understand update flow (qualitative feedback)
- Onboarding + first aha moment completion >80%

## Open Questions

1. **Demo contact update frequency**: Daily? On app open? Random interval?
   - Recommendation: On first app open each day, max once per 24h

2. **Aha moment persistence**: Store seen moments locally or show every time?
   - Recommendation: Store locally, show once per milestone

3. **Tooltip locations**: Which UI elements get first-time tooltips?
   - Recommendation: Exchange button, contact list empty state, settings gear

4. **Help content translation**: Include i18n for FAQ from the start?
   - Recommendation: English only initially, structure for future i18n

5. **Demo contact appearance**: Should it look like a real contact or obviously fake?
   - Recommendation: Real appearance with small "Demo" badge

## Dependencies

- P17 Onboarding (done)
- Contact list views (exist)
- Settings screen (exists)

## Risks

| Risk | Mitigation |
|------|------------|
| Aha overlays feel intrusive | Make dismissible, subtle animations, don't block user |
| Demo contact confuses users | Clear "Demo" badge, explain in FAQ |
| Help content becomes stale | Keep FAQ minimal, link to website for detailed docs |
| Scope creep | Stick to listed features, defer telemetry/analytics |

## Not In Scope

- Usage telemetry/analytics (privacy concerns, defer)
- Trust metrics/indicators (nice-to-have, defer)
- 2-of-N contact introduction (requires network effects)
- Website explainer video (marketing, separate effort)

## References

- `features/ideas/in-app-aha-moments.md`
- `features/ideas/in-app-help.md`
- `features/ideas/engineering-the-time-to-value.md`
- `features/onboarding.feature` (@demo, @first-exchange scenarios)
- `docs/planning/done/17-onboarding-experience.md` (Phase 2 pending items)
