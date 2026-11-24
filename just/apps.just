# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Application running recipes

# Run an application: just run [cli|tui|gtk-display|qt-display|android|ios|relay]
[group('apps')]
[script]
run platform *args:
    set -e
    case "{{platform}}" in
        cli|cli-display)
            cd cli-display && cargo run -- {{args}}
            ;;
        # tui-display is a library; linux-app builds the binary (private#1233).
        tui|tui-display)
            cd linux-app && cargo run --no-default-features --features tui --bin vauchi-tui -- {{args}}
            ;;
        gtk-display)
            cd gtk-display && cargo run -- {{args}}
            ;;
        qt-display)
            # Build vauchi-cabi if needed
            CABI_LIB="core/target/release/libvauchi_cabi.so"
            if [ ! -f "$CABI_LIB" ]; then
                echo "Building vauchi-cabi..."
                cd core && cargo build --release -p vauchi-cabi && cd ..
            fi
            # Build Qt app
            mkdir -p qt-display/build
            cd qt-display/build
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
        windows-app|windows)
            # Build vauchi-cabi if the DLL is missing
            CABI_DLL="windows-app/cabi/vauchi_cabi.dll"
            if [ ! -f "$CABI_DLL" ]; then
                echo "Building vauchi-cabi..."
                cd core && cargo build --release -p vauchi-cabi && cd ..
                mkdir -p windows-app/cabi
                cp core/target/release/vauchi_cabi.dll "$CABI_DLL"
            fi
            # WinUI 3 needs Visual Studio's MSBuild — the dotnet CLI's
            # bundled MSBuild lacks Microsoft.Build.Packaging.Pri.Tasks.dll
            # so the PRI/MRT resource step fails. Locate VS via vswhere
            # (handles 2022 / 18.x / future versions) and use its MSBuild.
            VSWHERE="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
            if [ ! -x "$VSWHERE" ]; then
                echo "ERROR: vswhere.exe not found — install Visual Studio 2022+ with the"
                echo "  '.NET desktop development' + 'Universal Windows Platform' workloads."
                exit 1
            fi
            VS_INSTALL=$("$VSWHERE" -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath)
            if [ -z "$VS_INSTALL" ]; then
                echo "ERROR: no Visual Studio install with MSBuild found. Install the"
                echo "  '.NET desktop development' workload."
                exit 1
            fi
            MSBUILD="$VS_INSTALL/MSBuild/Current/Bin/MSBuild.exe"
            if [ ! -x "$MSBUILD" ]; then
                echo "ERROR: MSBuild not found at $MSBUILD"
                exit 1
            fi
            # Build and run
            cd windows-app
            "$MSBUILD" Vauchi.sln -p:Configuration=Release -p:Platform=x64 -restore -v:quiet -nologo
            ./Vauchi/bin/x64/Release/net8.0-windows10.0.22621.0/win-x64/Vauchi.exe {{args}}
            ;;
        *)
            echo "Usage: just run [cli|tui|gtk-display|qt-display|android|ios|relay|windows-app]"
            echo ""
            echo "Platforms:"
            echo "  cli         Run CLI (pass args after platform)"
            echo "  tui         Run TUI terminal interface"
            echo "  gtk-display   Run Linux GTK4 app"
            echo "  qt-display    Run Linux Qt6 app (builds vauchi-cabi if needed)"
            echo "  windows-app Run Windows WinUI 3 app (builds vauchi-cabi if needed)"
            echo "  android     Build and install on Android emulator"
            echo "  ios         Build and install on iOS simulator"
            echo "  relay       Start relay server"
            echo ""
            echo "Examples:"
            echo "  just run cli init Alice"
            echo "  just run tui"
            echo "  just run gtk-display"
            echo "  just run qt-display"
            echo "  just run windows-app"
            echo "  just run relay --port 8080"
            exit 1
            ;;
    esac

# Start relay server
[group('apps')]
relay:
    cd relay && cargo run

# Run TUI application (linux-app builds vauchi-tui; tui-display is its library)
[group('apps')]
tui:
    cd linux-app && cargo run --no-default-features --features tui --bin vauchi-tui
