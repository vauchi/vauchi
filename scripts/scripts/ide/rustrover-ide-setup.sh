#!/bin/bash
# RustRover Setup Script for Vauchi
# This script prepares the environment for developing Vauchi in RustRover.
#
# Usage:
#   ./_dev-tools/scripts/ide/rustrover-ide-setup.sh
#
# After running this script:
#   1. Open RustRover
#   2. Select 'Open' and choose the core/ directory
#   3. Run configurations will be available in the Run menu

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CODE_DIR="$WORKSPACE_ROOT/core"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

echo -e "${YELLOW}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║            Vauchi RustRover IDE Setup                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. Check for Rust toolchain
print_step "Checking Rust installation..."
if ! command -v rustup &> /dev/null; then
    print_error "rustup is not installed"
    echo "Please install it from https://rustup.rs/"
    exit 1
fi

RUST_VERSION=$(rustc --version)
print_success "Rust found: $RUST_VERSION"

# 2. Install required Android targets
print_step "Installing Android targets..."
for target in aarch64-linux-android x86_64-linux-android; do
    if ! rustup target list --installed | grep -q "^$target$"; then
        echo "Installing $target..."
        rustup target add $target
    else
        print_success "$target already installed"
    fi
done

# 3. Check for Android NDK (required for vauchi-mobile build)
print_step "Checking for Android NDK..."
NDK_HOME=""
if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
    NDK_HOME="$ANDROID_NDK_HOME"
elif [ -d "$HOME/Android/Sdk/ndk" ]; then
    NDK_HOME=$(ls -d "$HOME/Android/Sdk/ndk/"* 2>/dev/null | sort -V -r | head -n 1)
fi

if [ -z "$NDK_HOME" ]; then
    print_warning "Android NDK not found"
    echo "This is required for 'code/scripts/build-android.sh'."
    echo "Set ANDROID_NDK_HOME or install via Android Studio SDK Manager."
else
    print_success "Android NDK found: $NDK_HOME"
fi

# 4. Create RustRover run configurations
print_step "Creating RustRover run configurations..."

RUN_CONFIG_DIR="$CODE_DIR/.idea/runConfigurations"
mkdir -p "$RUN_CONFIG_DIR"

# Test All
cat > "$RUN_CONFIG_DIR/Test_All.xml" << 'EOF'
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Test All" type="CargoCommandRunConfiguration" factoryName="Cargo Command">
    <option name="command" value="test --workspace" />
    <option name="workingDirectory" value="file://$PROJECT_DIR$" />
    <option name="emulateTerminal" value="true" />
    <option name="channel" value="DEFAULT" />
    <envs />
    <method v="2" />
  </configuration>
</component>
EOF
print_success "Created: Test All"

# Test Core
cat > "$RUN_CONFIG_DIR/Test_Core.xml" << 'EOF'
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Test Core" type="CargoCommandRunConfiguration" factoryName="Cargo Command">
    <option name="command" value="test -p vauchi-core" />
    <option name="workingDirectory" value="file://$PROJECT_DIR$" />
    <option name="emulateTerminal" value="true" />
    <option name="channel" value="DEFAULT" />
    <envs />
    <method v="2" />
  </configuration>
</component>
EOF
print_success "Created: Test Core"

# Run Relay
cat > "$RUN_CONFIG_DIR/Run_Relay.xml" << 'EOF'
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Run Relay" type="CargoCommandRunConfiguration" factoryName="Cargo Command">
    <option name="command" value="run -p vauchi-relay" />
    <option name="workingDirectory" value="file://$PROJECT_DIR$" />
    <option name="emulateTerminal" value="true" />
    <option name="channel" value="DEFAULT" />
    <envs />
    <method v="2" />
  </configuration>
</component>
EOF
print_success "Created: Run Relay"

# Run CLI Init
cat > "$RUN_CONFIG_DIR/Run_CLI_Init.xml" << 'EOF'
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Run CLI Init" type="CargoCommandRunConfiguration" factoryName="Cargo Command">
    <option name="command" value="run -p vauchi-cli -- init &quot;Test User&quot;" />
    <option name="workingDirectory" value="file://$PROJECT_DIR$" />
    <option name="emulateTerminal" value="true" />
    <option name="channel" value="DEFAULT" />
    <envs />
    <method v="2" />
  </configuration>
</component>
EOF
print_success "Created: Run CLI Init"

# Clippy
cat > "$RUN_CONFIG_DIR/Clippy.xml" << 'EOF'
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Clippy" type="CargoCommandRunConfiguration" factoryName="Cargo Command">
    <option name="command" value="clippy --workspace -- -D warnings" />
    <option name="workingDirectory" value="file://$PROJECT_DIR$" />
    <option name="emulateTerminal" value="true" />
    <option name="channel" value="DEFAULT" />
    <envs />
    <method v="2" />
  </configuration>
</component>
EOF
print_success "Created: Clippy"

# Format Check
cat > "$RUN_CONFIG_DIR/Format_Check.xml" << 'EOF'
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Format Check" type="CargoCommandRunConfiguration" factoryName="Cargo Command">
    <option name="command" value="fmt --all -- --check" />
    <option name="workingDirectory" value="file://$PROJECT_DIR$" />
    <option name="emulateTerminal" value="true" />
    <option name="channel" value="DEFAULT" />
    <envs />
    <method v="2" />
  </configuration>
</component>
EOF
print_success "Created: Format Check"

# Build All
cat > "$RUN_CONFIG_DIR/Build_All.xml" << 'EOF'
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Build All" type="CargoCommandRunConfiguration" factoryName="Cargo Command">
    <option name="command" value="build --workspace" />
    <option name="workingDirectory" value="file://$PROJECT_DIR$" />
    <option name="emulateTerminal" value="true" />
    <option name="channel" value="DEFAULT" />
    <envs />
    <method v="2" />
  </configuration>
</component>
EOF
print_success "Created: Build All"

# Summary
echo ""
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                   Setup Complete!                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Run configurations created:"
echo "  - Test All        : cargo test --workspace"
echo "  - Test Core       : cargo test -p vauchi-core"
echo "  - Run Relay       : cargo run -p vauchi-relay"
echo "  - Run CLI Init    : cargo run -p vauchi-cli -- init \"Test User\""
echo "  - Clippy          : cargo clippy --workspace -- -D warnings"
echo "  - Format Check    : cargo fmt --all -- --check"
echo "  - Build All       : cargo build --workspace"
echo ""
echo "Next steps:"
echo "  1. Open RustRover"
echo "  2. Select 'Open' and navigate to: $CODE_DIR"
echo "  3. Wait for indexing to complete"
echo "  4. Run configurations are in the 'Run' menu (top-right dropdown)"
echo ""
echo "Note: The .idea/ folder in code/ is gitignored, so these"
echo "      configurations are local to your machine."
echo ""
