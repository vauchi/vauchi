# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Application running recipes

# Run an application: just run [cli|tui|desktop|android|ios|relay]
run platform="" *args:
    #!/usr/bin/env bash
    set -e
    case "{{platform}}" in
        cli)
            cd cli && cargo run -- {{args}}
            ;;
        tui)
            cd tui && cargo run -- {{args}}
            ;;
        desktop|gui)
            # Build with Tauri CLI (embeds frontend assets)
            if [[ ! -f desktop/src-tauri/target/release/vauchi-desktop ]] || [[ ! -s desktop/ui/dist/index.html ]]; then
                echo "Building desktop app..."
                cd desktop/src-tauri && cargo tauri build
            fi
            desktop/src-tauri/target/release/vauchi-desktop {{args}}
            ;;
        desktop-dev)
            cd desktop && cargo tauri dev
            ;;
        android)
            just build-android release
            cd android && ./gradlew assembleRelease
            adb install -r android/app/build/outputs/apk/release/app-release.apk
            adb shell am start -n com.vauchi.app/.MainActivity
            ;;
        ios)
            just build-ios release
            cd ios && xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -configuration Release build
            xcrun simctl boot "iPhone 15 Pro" 2>/dev/null || true
            xcrun simctl install "iPhone 15 Pro" ios/build/Build/Products/Release-iphonesimulator/Vauchi.app
            xcrun simctl launch "iPhone 15 Pro" com.vauchi.app
            ;;
        relay)
            cd relay && cargo run -- {{args}}
            ;;
        *)
            echo "Usage: just run [cli|tui|desktop|android|ios|relay]"
            echo ""
            echo "Platforms:"
            echo "  cli         Run CLI (pass args after platform)"
            echo "  tui         Run TUI terminal interface"
            echo "  desktop     Run desktop app (release build)"
            echo "  desktop-dev Run desktop in dev mode (hot reload)"
            echo "  android     Build and install on Android emulator"
            echo "  ios         Build and install on iOS simulator"
            echo "  relay       Start relay server"
            echo ""
            echo "Examples:"
            echo "  just run cli init Alice"
            echo "  just run tui"
            echo "  just run desktop"
            echo "  just run relay --port 8080"
            exit 1
            ;;
    esac

# Start relay server
relay:
    cd relay && cargo run

# Run TUI application
tui:
    cd tui && cargo run

# Run desktop in dev mode
desktop-dev:
    cd desktop && cargo tauri dev
