# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# macOS device testing recipes (local Mac automation)
#
# Unlike iOS/Android where the "device" is a phone, for macOS the device
# IS this Mac. Uses native macOS APIs: screencapture, osascript, log stream.
#
# Prerequisites:
#   brew install cliclick     (optional, for click/type — falls back to osascript)
#   Accessibility permissions for Terminal/iTerm (System Settings → Privacy → Accessibility)

macos_app_name := "Vauchi"
macos_bundle_id := "app.vauchi.macos"
macos_screenshots_dir := "_private/docs/testing/screenshots/macos"

# ═══════════════════════════════════════════════════════════════════
# macOS DEVICE TESTING
# ═══════════════════════════════════════════════════════════════════

# Build and launch the macOS app for manual testing
[group('device-test-macos')]
[script]
dt-build-macos:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    printf '%b\n' "${YELLOW}═══ Build macOS App ═══${NC}"

    cd macos
    command -v xcodegen &>/dev/null && xcodegen generate 2>/dev/null

    printf '%b\n' "${YELLOW}Resolving SPM dependencies...${NC}"
    # SPM resolve/build never advances branch pins — it honors Package.resolved
    # and workspace-state.json as lock files. Delete both so SPM re-resolves to
    # the latest branch tip. The bare repo cache stays warm so this is fast.
    rm -f Vauchi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
    DD_SPM=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "Vauchi-*" 2>/dev/null | head -1)
    [[ -n "$DD_SPM" ]] && rm -f "$DD_SPM/SourcePackages/workspace-state.json"
    # Use -workspace (not -project) so SPM picks up the local
    # vauchi-platform-swift override declared in the workspace.
    xcodebuild -workspace Vauchi.xcworkspace -scheme Vauchi \
        -resolvePackageDependencies 2>&1 | tail -3

    printf '%b\n' "${YELLOW}Building macOS app (Debug)...${NC}"
    xcodebuild -workspace Vauchi.xcworkspace -scheme Vauchi \
        -configuration Debug -destination "platform=macOS" \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
        build 2>&1 | tail -5

    printf '%b\n' "${GREEN}macOS app built successfully${NC}"

# Launch the macOS app (build first if not already built)
[group('device-test-macos')]
[script]
dt-launch-macos:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Vauchi.app" \
        -path "*/Debug/*" -not -path "*iphoneos*" 2>/dev/null \
        | sort -t/ -k8 -r | head -1)

    if [[ -z "$APP_PATH" ]]; then
        printf '%b\n' "${RED}ERROR: Vauchi.app not found in DerivedData.${NC}"
        echo "Run: just dt-build-macos"
        exit 1
    fi

    echo "Launching: $APP_PATH"
    open "$APP_PATH"
    printf '%b\n' "${GREEN}macOS app launched${NC}"

# Kill and relaunch the macOS app
[group('device-test-macos')]
[script]
dt-relaunch-macos:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    echo "Killing Vauchi..."
    pkill -f "Vauchi.app/Contents/MacOS/Vauchi" 2>/dev/null || true
    sleep 1
    just dt-launch-macos

# ─── Screenshots ──────────────────────────────────────────────────

# Capture a screenshot of the Vauchi window
[group('device-test-macos')]
[script]
dt-screenshot-macos file="screenshot-macos.png":
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    # Find the Vauchi window ID
    WINDOW_ID=$(osascript -l JavaScript -e '
        const app = Application("System Events");
        const procs = app.processes.whose({name: "Vauchi"});
        if (procs.length === 0) { throw new Error("Vauchi not running"); }
        const wins = procs[0].windows();
        if (wins.length === 0) { throw new Error("No Vauchi window found"); }
        wins[0].properties().id;
    ' 2>/dev/null || true)

    if [[ -z "$WINDOW_ID" ]]; then
        printf '%b\n' "${YELLOW}Could not get window ID via System Events, falling back to screencapture...${NC}"
        # Fallback: capture by app name using CGWindowListCopyWindowInfo
        WINDOW_ID=$(osascript -e '
            tell application "System Events"
                set vauchiProc to first process whose name is "Vauchi"
                set frontmost of vauchiProc to true
            end tell
        ' 2>/dev/null && sleep 0.3 && screencapture -w "{{file}}" 2>/dev/null && echo "done" || true)

        if [[ "$WINDOW_ID" != "done" ]]; then
            # Last resort: full screen capture
            screencapture "{{file}}"
            echo "Full screen screenshot saved to {{file}}"
            exit 0
        fi
    else
        screencapture -l "$WINDOW_ID" "{{file}}"
    fi

    printf '%b\n' "${GREEN}Screenshot saved to {{file}}${NC}"

# Capture a named screenshot into the testing screenshots directory
[group('device-test-macos')]
[script]
dt-screenshot-macos-named name:
    set -euo pipefail
    mkdir -p "{{macos_screenshots_dir}}"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    FILE="{{macos_screenshots_dir}}/{{name}}-${TIMESTAMP}.png"
    just dt-screenshot-macos "$FILE"

# ─── UI Automation ────────────────────────────────────────────────

# Click at screen coordinates in the Vauchi window
[group('device-test-macos')]
[script]
dt-macos-click x y:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    osascript -e 'tell application "Vauchi" to activate' 2>/dev/null || true
    sleep 0.3

    X_POS="{{x}}"
    Y_POS="{{y}}"

    if command -v cliclick &>/dev/null; then
        cliclick "c:${X_POS},${Y_POS}"
    else
        osascript -e "tell application \"System Events\" to click at {${X_POS}, ${Y_POS}}"
    fi
    echo "Clicked at (${X_POS}, ${Y_POS})"

# Type text into the currently focused field
[group('device-test-macos')]
[script]
dt-macos-type text:
    set -euo pipefail

    # Bring Vauchi to front
    osascript -e 'tell application "Vauchi" to activate' 2>/dev/null || true
    sleep 0.2

    if command -v cliclick &>/dev/null; then
        cliclick "t:{{text}}"
    else
        osascript -e "
            tell application \"System Events\"
                keystroke \"{{text}}\"
            end tell
        "
    fi
    echo "Typed: {{text}}"

# Press a key (e.g., "return", "tab", "escape", "delete")
[group('device-test-macos')]
[script]
dt-macos-key key:
    set -euo pipefail

    osascript -e 'tell application "Vauchi" to activate' 2>/dev/null || true
    sleep 0.2

    osascript -e "
        tell application \"System Events\"
            key code (key code \"{{key}}\")
        end tell
    " 2>/dev/null || \
    osascript -e "
        tell application \"System Events\"
            keystroke return
        end tell
    "
    echo "Pressed: {{key}}"

# Press Return key
[group('device-test-macos')]
[script]
dt-macos-return:
    osascript -e 'tell application "Vauchi" to activate' 2>/dev/null || true
    sleep 0.2
    osascript -e 'tell application "System Events" to keystroke return'

# Press Tab key
[group('device-test-macos')]
[script]
dt-macos-tab:
    osascript -e 'tell application "Vauchi" to activate' 2>/dev/null || true
    sleep 0.2
    osascript -e 'tell application "System Events" to key code 48'

# Press Escape key
[group('device-test-macos')]
[script]
dt-macos-escape:
    osascript -e 'tell application "Vauchi" to activate' 2>/dev/null || true
    sleep 0.2
    osascript -e 'tell application "System Events" to key code 53'

# ─── Accessibility Tree ──────────────────────────────────────────

# Dump the accessibility tree of the Vauchi window
[group('device-test-macos')]
[script]
dt-macos-accessibility-tree:
    set -euo pipefail
    osascript -l JavaScript -e '
        function dumpElement(el, indent) {
            indent = indent || "";
            let role = "";
            let title = "";
            let value = "";
            let desc = "";
            let enabled = "";

            try { role = el.role(); } catch(e) {}
            try { title = el.title(); } catch(e) {}
            try { value = el.value(); } catch(e) {}
            try { desc = el.description(); } catch(e) {}
            try { enabled = el.enabled(); } catch(e) {}

            let line = indent + role;
            if (title) line += " title=\"" + title + "\"";
            if (value !== "" && value !== null) line += " value=\"" + value + "\"";
            if (desc) line += " desc=\"" + desc + "\"";
            if (enabled === false) line += " [disabled]";

            let result = line + "\n";

            try {
                const children = el.uiElements();
                for (let i = 0; i < children.length; i++) {
                    result += dumpElement(children[i], indent + "  ");
                }
            } catch(e) {}

            return result;
        }

        const se = Application("System Events");
        const procs = se.processes.whose({name: "Vauchi"});
        if (procs.length === 0) throw new Error("Vauchi is not running");

        const proc = procs[0];
        const wins = proc.windows();
        if (wins.length === 0) throw new Error("No Vauchi window found");

        dumpElement(wins[0], "");
    '

# Find a UI element by its accessibility label/title
[group('device-test-macos')]
[script]
dt-macos-find-element label:
    set -euo pipefail
    osascript -l JavaScript -e "
        function findByTitle(el, target, path) {
            path = path || '';
            let title = '';
            let role = '';
            let pos = null;
            let size = null;

            try { title = el.title(); } catch(e) {}
            try { role = el.role(); } catch(e) {}
            try { pos = el.position(); } catch(e) {}
            try { size = el.size(); } catch(e) {}

            let currentPath = path + '/' + role;

            if (title && title.indexOf('${label}') !== -1) {
                let result = 'Found: ' + role + ' title=\"' + title + '\"';
                if (pos) result += ' position=(' + pos[0] + ',' + pos[1] + ')';
                if (size) result += ' size=(' + size[0] + 'x' + size[1] + ')';
                result += ' path=' + currentPath;
                return result + '\n';
            }

            let results = '';
            try {
                const children = el.uiElements();
                for (let i = 0; i < children.length; i++) {
                    results += findByTitle(children[i], '${label}', currentPath);
                }
            } catch(e) {}
            return results;
        }

        const se = Application('System Events');
        const proc = se.processes.whose({name: 'Vauchi'})[0];
        const win = proc.windows()[0];
        const found = findByTitle(win, '${label}', '');
        if (!found) throw new Error('No element found with label containing: ${label}');
        found;
    "

# Click a UI element by its accessibility label/title
[group('device-test-macos')]
[script]
dt-macos-click-element label:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    osascript -e 'tell application "Vauchi" to activate' 2>/dev/null || true
    sleep 0.3

    osascript -l JavaScript -e "
        function findAndClick(el, target) {
            let title = '';
            try { title = el.title(); } catch(e) {}
            let desc = '';
            try { desc = el.description(); } catch(e) {}

            if ((title && title.indexOf('${label}') !== -1) ||
                (desc && desc.indexOf('${label}') !== -1)) {
                try {
                    const actions = el.actions();
                    for (let i = 0; i < actions.length; i++) {
                        if (actions[i].name() === 'AXPress') {
                            actions[i].perform();
                            return true;
                        }
                    }
                } catch(e) {}

                // Fallback: click at element center
                try {
                    const pos = el.position();
                    const size = el.size();
                    const x = pos[0] + size[0]/2;
                    const y = pos[1] + size[1]/2;
                    Application('System Events').click({at: [x, y]});
                    return true;
                } catch(e) {}
            }

            try {
                const children = el.uiElements();
                for (let i = 0; i < children.length; i++) {
                    if (findAndClick(children[i], target)) return true;
                }
            } catch(e) {}
            return false;
        }

        const se = Application('System Events');
        const proc = se.processes.whose({name: 'Vauchi'})[0];
        const win = proc.windows()[0];
        if (!findAndClick(win, '${label}')) {
            throw new Error('Element not found: ${label}');
        }
        'Clicked: ${label}';
    "

# ─── Logs ─────────────────────────────────────────────────────────

# Stream macOS app logs (unified logging)
[group('device-test-macos')]
[script]
dt-logs-macos:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    printf '%b\n' "${YELLOW}Streaming Vauchi macOS logs... Press Ctrl+C to stop.${NC}"
    log stream --predicate 'subsystem == "app.vauchi.macos" OR process == "Vauchi"' \
        --level info 2>/dev/null || \
    log stream --predicate 'process == "Vauchi"' --level info

# Dump recent macOS app logs (last 5 minutes)
[group('device-test-macos')]
[script]
dt-logs-macos-recent minutes="5":
    set -euo pipefail
    log show --predicate 'process == "Vauchi"' --last "{{minutes}}m" --level info

# ─── Build Verification ──────────────────────────────────────────

# Verify the installed macOS app build version
[group('device-test-macos')]
[script]
dt-verify-build-macos:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    printf '%b\n' "${BLUE}=== macOS Build Verification ===${NC}"

    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Vauchi.app" \
        -path "*/Debug/*" -not -path "*iphoneos*" 2>/dev/null \
        | sort -t/ -k8 -r | head -1)

    if [[ -z "$APP_PATH" ]]; then
        printf '%b\n' "${RED}No macOS Vauchi.app found in DerivedData${NC}"
        exit 1
    fi

    echo "App path: $APP_PATH"

    # Read Info.plist values
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")

    printf '%b\n' "  Version:   ${GREEN}$VERSION ($BUILD)${NC}"
    printf '%b\n' "  Bundle ID: $BUNDLE_ID"

    # Check binary architecture
    BINARY="$APP_PATH/Contents/MacOS/Vauchi"
    if [[ -f "$BINARY" ]]; then
        ARCH=$(file "$BINARY" | grep -oE "arm64|x86_64" | tr '\n' '+' | sed 's/+$//')
        printf '%b\n' "  Arch:      $ARCH"
    fi

    # Check if running
    if pgrep -f "Vauchi.app/Contents/MacOS/Vauchi" > /dev/null 2>&1; then
        PID=$(pgrep -f "Vauchi.app/Contents/MacOS/Vauchi" | head -1)
        printf '%b\n' "  Status:    ${GREEN}Running (PID $PID)${NC}"
    else
        printf '%b\n' "  Status:    ${YELLOW}Not running${NC}"
    fi

# ─── Workflow Automation ──────────────────────────────────────────

# Run a scripted workflow: launch app, take screenshots at each step
# Usage: just dt-macos-workflow onboarding
[group('device-test-macos')]
[script]
dt-macos-workflow name:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    SCRIPT_DIR="_private/docs/testing/workflows/macos"
    SCRIPT_FILE="$SCRIPT_DIR/{{name}}.sh"

    if [[ ! -f "$SCRIPT_FILE" ]]; then
        printf '%b\n' "${RED}Workflow script not found: $SCRIPT_FILE${NC}"
        echo ""
        echo "Available workflows:"
        ls "$SCRIPT_DIR"/*.sh 2>/dev/null | sed 's|.*/||; s|\.sh$||' | sed 's/^/  /' || echo "  (none — create one in $SCRIPT_DIR/)"
        echo ""
        echo "Workflow scripts are bash files that call dt-macos-* recipes."
        echo "Example:"
        echo "  #!/usr/bin/env bash"
        echo "  just dt-launch-macos"
        echo "  sleep 2"
        echo "  just dt-screenshot-macos-named onboarding-01-welcome"
        echo "  just dt-macos-click-element \"Get Started\""
        echo "  sleep 1"
        echo "  just dt-screenshot-macos-named onboarding-02-create-identity"
        exit 1
    fi

    printf '%b\n' "${YELLOW}╔════════════════════════════════════════════════╗${NC}"
    printf '%b\n' "${YELLOW}║     macOS Workflow: {{name}}                     ${NC}"
    printf '%b\n' "${YELLOW}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    bash "$SCRIPT_FILE"

    echo ""
    printf '%b\n' "${GREEN}Workflow '{{name}}' completed.${NC}"
    echo "Screenshots: {{macos_screenshots_dir}}/"
