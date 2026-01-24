# P01: Proximity Verification - Stop Lying

**Priority**: CRITICAL
**Status**: IN PROGRESS - Core implementation done, platform handlers needed
**Blocking**: Production launch

## Problem

`vauchi-core/src/exchange/audio.rs` contains only `MockAudioBackend`. The feature spec (`features/contact_exchange.feature:209-225`) promises ultrasonic audio verification but it doesn't exist. Every platform falls back to manual confirmation silently.

This is a security feature that's being faked.

## Decision Required

- [x] **Option A**: Implement real audio (2 weeks) ✅ CHOSEN

## Completed (2026-01-20)

### Core Implementation
- `vauchi-core/src/exchange/audio_cpal.rs` - CPAL-based desktop backend
  - FSK modulation at 18.5-18.7 kHz
  - 19 kHz preamble for sync detection
  - Goertzel algorithm for frequency detection
  - Feature flag: `audio-cpal`

### Mobile Callback Interface
- `vauchi-mobile/src/audio.rs` - UniFFI callback interface
  - `PlatformAudioHandler` trait for iOS/Android to implement
  - `MobileProximityVerifier` wrapper class
  - FSK encoding/decoding shared with core

## Remaining Work

## Option A: Real Implementation

### Files to Create/Modify

| Platform | File | Implementation |
|----------|------|----------------|
| Core | `audio.rs` | Keep trait, add platform dispatch |
| iOS | `AudioProximity.swift` | AVAudioEngine 18-20kHz |
| Android | `AudioProximity.kt` | AudioRecord/AudioTrack |
| Desktop | `audio_cpal.rs` | CPAL library |

### Core Changes (`vauchi-core/src/exchange/audio.rs`)

1. Keep `AudioBackend` trait
2. Add `#[cfg]` platform detection
3. Remove `MockAudioBackend` from production builds
4. Add real frequency detection (18-20 kHz band)

### iOS Implementation

```swift
// Services/AudioProximityService.swift
import AVFoundation
import Accelerate

class AudioProximityService {
    private let engine = AVAudioEngine()
    private let targetFrequency: Float = 19000 // Hz

    func emitChallenge(_ data: Data) async throws
    func listenForChallenge() async throws -> Data?
}
```

### Android Implementation

```kotlin
// proximity/AudioProximityService.kt
class AudioProximityService {
    private val sampleRate = 44100
    private val targetFrequency = 19000f

    suspend fun emitChallenge(data: ByteArray)
    suspend fun listenForChallenge(): ByteArray?
}
```

## Option B: Remove Feature

1. Delete audio.rs (or gut it)
2. Update `contact_exchange.feature` - remove ultrasonic scenarios
3. Update all exchange flows to use manual confirmation only
4. Document in README: "Proximity verification requires manual confirmation"

## Acceptance Criteria

If Option A:
- [ ] Real audio emitted at 18-20 kHz
- [ ] Real audio detected on receiving device
- [ ] Challenge/response verified cryptographically
- [ ] Fallback to manual only when hardware unavailable
- [ ] Tests with real audio (not mocks)

If Option B:
- [ ] No mock code pretending to be real
- [ ] Documentation updated
- [ ] Feature file updated
- [ ] UI clearly shows "manual verification"
