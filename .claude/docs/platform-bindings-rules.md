---
paths:
  - "android/**"
  - "ios/**"
apply: always
---

## Platform Bindings

### Android
- Kotlin, Jetpack Compose, Gradle (Kotlin DSL), UniFFI bindings via group Maven registry (published from core)
- Use Compose for all new UI
- Pre-MR: `just check-android` (or `./gradlew lint assembleDebug test`)

### iOS
- SwiftUI, Xcode/SPM, UniFFI bindings via `vauchi-platform-swift`
- Use SwiftUI for all new UI
- Snapshot tests run on 2x simulator (iPhone SE 3) for baselines to match
- Pre-MR: `just check-ios` (or `xcodegen generate && xcodebuild ... build test`)
