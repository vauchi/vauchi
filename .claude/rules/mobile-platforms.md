---
paths:
  - "android/**"
  - "ios/**"
apply: always
---

## Mobile Platforms

### Android
- Kotlin, Jetpack Compose, Gradle (Kotlin DSL), UniFFI bindings via `vauchi-mobile-android`
- Use Compose for all new UI
- Pre-MR: `just check-android` (or `./gradlew lint assembleDebug test`)

### iOS
- SwiftUI, Xcode/SPM, UniFFI bindings via `vauchi-mobile-swift`
- Use SwiftUI for all new UI
- Snapshot tests run on 2x simulator (iPhone SE 3) for baselines to match
- Pre-MR: `just check-ios` (or `xcodegen generate && xcodebuild ... build test`)
