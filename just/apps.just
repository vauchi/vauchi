# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Application running recipes

# Run an application: just run [cli|tui|linux-gtk|linux-qt|android|ios|relay]
[group('apps')]
[script]
run platform="" *args:
    set -e
    case "{{platform}}" in
        cli)
            cd cli && cargo run -- {{args}}
            ;;
        tui)
            cd tui && cargo run -- {{args}}
            ;;
        linux-gtk)
            cd linux-gtk && cargo run -- {{args}}
            ;;
        linux-qt)
            # Build vauchi-cabi if needed
            CABI_LIB="core/target/release/libvauchi_cabi.so"
            if [ ! -f "$CABI_LIB" ]; then
                echo "Building vauchi-cabi..."
                cd core && cargo build --release -p vauchi-cabi && cd ..
            fi
            # Build Qt app
            mkdir -p linux-qt/build
            cd linux-qt/build
            cmake .. -DVAUCHI_CABI_DIR="$(pwd)/../../core/target/release"
            cmake --build . --parallel
            # Run
            LD_LIBRARY_PATH="$(pwd)/../../core/target/release:$LD_LIBRARY_PATH" ./vauchi-qt {{args}}
            ;;
        android)
            just build-android release
            cd android && ./gradlew assembleRelease
            adb install -r android/app/build/outputs/apk/release/app-release.apk
            adb shell am start -n app.vauchi/.MainActivity
            ;;
        ios)
            just build-ios release
            cd ios && xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name={{ ios_simulator }}' -configuration Release build
            xcrun simctl boot "{{ ios_simulator }}" 2>/dev/null || true
            xcrun simctl install "{{ ios_simulator }}" ios/build/Build/Products/Release-iphonesimulator/Vauchi.app
            xcrun simctl launch "{{ ios_simulator }}" app.vauchi.ios
            ;;
        relay)
            cd relay && cargo run -- {{args}}
            ;;
        *)
            echo "Usage: just run [cli|tui|linux-gtk|linux-qt|android|ios|relay]"
            echo ""
            echo "Platforms:"
            echo "  cli         Run CLI (pass args after platform)"
            echo "  tui         Run TUI terminal interface"
            echo "  linux-gtk   Run Linux GTK4 app"
            echo "  linux-qt    Run Linux Qt6 app (builds vauchi-cabi if needed)"
            echo "  android     Build and install on Android emulator"
            echo "  ios         Build and install on iOS simulator"
            echo "  relay       Start relay server"
            echo ""
            echo "Examples:"
            echo "  just run cli init Alice"
            echo "  just run tui"
            echo "  just run linux-gtk"
            echo "  just run linux-qt"
            echo "  just run relay --port 8080"
            exit 1
            ;;
    esac

# Start relay server
[group('apps')]
[working-directory('relay')]
relay:
    cargo run

# Run TUI application
[group('apps')]
[working-directory('tui')]
tui:
    cargo run

