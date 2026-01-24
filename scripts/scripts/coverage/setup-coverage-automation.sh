#!/bin/bash

# Vauchi Coverage Automation Script
# Sets up automated coverage reporting with trend tracking and policy enforcement

set -e

echo "🚀 Setting up automated coverage reporting..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MINIMUM_COVERAGE=80
COVERAGE_TARGETS=(
    "vauchi-core:90"
    "vauchi-relay:75" 
    "vauchi-tui:70"
    "vauchi-mobile:65"
    "vauchi-desktop:60"
)

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Setup coverage tools
setup_coverage_tools() {
    print_info "Installing coverage tools..."
    
    # Install cargo-llvm-cov for Rust coverage
    if ! command -v cargo-llvm-cov &> /dev/null; then
        cargo install cargo-llvm-cov
    fi
    
    # Install Python dependencies for coverage reporting
    pip3 install --user coverage>=7.0 pytest-cov>=4.0 codecov>=2.5
    
    # Install Node.js dependencies for frontend coverage
    if [ -d "code/vauchi-desktop/ui" ]; then
        cd code/vauchi-desktop/ui
        npm install --save-dev @vitest/coverage-v8 nyc istanbul
    fi
}

# Generate Rust coverage reports
generate_rust_coverage() {
    print_info "Generating Rust coverage reports..."
    
    cd code
    
    # Run coverage for each crate
    for crate in vauchi-core vauchi-relay vauchi-tui vauchi-mobile; do
        echo "Processing $crate..."
        
        # Clean previous coverage data
        cargo llvm-cov clean --package $crate
        
        # Run tests with coverage
        CARGO_INCREMENTAL=0 cargo llvm-cov --package $crate --lcov --output-path coverage-reports/$crate
        
        # Generate HTML report
        cargo llvm-cov --package $crate --html --output-path coverage-reports/$crate
        
        # Generate JSON for trend tracking
        cargo llvm-cov --package $crate --json --output-path coverage-reports/$crate
        
        # Generate summary for quick checking
        cargo llvm-cov --package $crate --summary --output-path coverage-reports/$crate
    done
}

# Generate frontend coverage reports
generate_frontend_coverage() {
    if [ -d "code/vauchi-desktop/ui" ]; then
        print_info "Generating frontend coverage reports..."
        
        cd code/vauchi-desktop/ui
        
        # Run tests with coverage
        npm run test:coverage
        
        # Generate HTML report
        npx nyc report --reporter=html --report-dir=coverage-reports/desktop
        
        # Generate JSON for trend tracking
        npx nyc report --reporter=json --report-dir=coverage-reports/desktop
    fi
}

# Parse coverage percentages from reports
parse_coverage_percentages() {
    local coverage_data=()
    
    # Parse Rust coverage
    for crate in vauchi-core vauchi-relay vauchi-tui vauchi-mobile; do
        if [ -f "coverage-reports/$crate/coverage.json" ]; then
            local percentage=$(python3 -c "
import json
with open('coverage-reports/$crate/coverage.json') as f:
    data = json.load(f)
    percent = data.get('percent', 0)
    print(f'{percent:.1f}')
" 2>/dev/null)
            coverage_data+=("$crate:$percentage")
        fi
    done
    
    # Parse frontend coverage
    if [ -f "coverage-reports/desktop/coverage-summary.json" ]; then
        local percentage=$(python3 -c "
import json
with open('coverage-reports/desktop/coverage-summary.json') as f:
    data = json.load(f)
    percent = data.get('total', {}).get('lines', {}).get('pct', 0)
    print(f'{percent:.1f}')
" 2>/dev/null)
        coverage_data+=("vauchi-desktop:$percentage")
    fi
    
    echo "${coverage_data[@]}"
}

# Check coverage against targets
check_coverage_targets() {
    print_info "Checking coverage against targets..."
    
    local coverage_data=($(parse_coverage_percentages))
    local failed_targets=()
    local passed_targets=()
    
    for target in "${COVERAGE_TARGETS[@]}"; do
        local crate_name="${target%%:*}"
        local target_percentage="${target##*:}"
        local actual_percentage=0
        
        # Find actual percentage for this crate
        for data in "${coverage_data[@]}"; do
            local data_crate="${data%%:*}"
            local data_percentage="${data##*:}"
            
            if [ "$data_crate" = "$crate_name" ]; then
                actual_percentage="$data_percentage"
                break
            fi
        done
        
        # Compare with target
        if (( $(echo "$actual_percentage < $target_percentage" | bc -l) )); then
            failed_targets+=("$crate_name: ${actual_percentage}% (target: ${target_percentage}%)")
        else
            passed_targets+=("$crate_name: ${actual_percentage}% (target: ${target_percentage}%)")
        fi
    done
    
    # Report results
    if [ ${#failed_targets[@]} -gt 0 ]; then
        print_error "Coverage targets failed:"
        for target in "${failed_targets[@]}"; do
            echo "  ❌ $target"
        done
        return 1
    else
        print_status "All coverage targets met:"
        for target in "${passed_targets[@]}"; do
            echo "  ✅ $target"
        done
    fi
}

# Generate trend tracking data
generate_trend_data() {
    print_info "Generating trend tracking data..."
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local coverage_data=($(parse_coverage_percentages))
    local trend_file="coverage-reports/trend-data.json"
    
    # Create or update trend data
    local trend_entry="{\"timestamp\": \"$timestamp\""
    
    for data in "${coverage_data[@]}"; do
        local crate="${data%%:*}"
        local percentage="${data##*:}"
        trend_entry+=", \"$crate\": $percentage"
    done
    
    trend_entry+="}"
    
    # Append to trend file
    if [ -f "$trend_file" ]; then
        # Append to existing array
        local temp_file=$(mktemp)
        python3 -c "
import json
with open('$trend_file') as f:
    data = json.load(f)
    data['measurements'].append($trend_entry)
with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
"
        mv "$temp_file" "$trend_file"
    else
        # Create new trend file
        python3 -c "
import json
data = {
    'timestamps': [],
    'measurements': []
}
data['measurements'].append($trend_entry)
with open('$trend_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
}

# Generate coverage badges
generate_coverage_badges() {
    print_info "Generating coverage badges..."
    
    local coverage_data=($(parse_coverage_percentages))
    
    for data in "${coverage_data[@]}"; do
        local crate="${data%%:*}"
        local percentage="${data##*:}"
        local color="red"
        
        # Determine badge color based on coverage
        if (( $(echo "$percentage >= 90" | bc -l) )); then
            color="brightgreen"
        elif (( $(echo "$percentage >= 80" | bc -l) )); then
            color="green"
        elif (( $(echo "$percentage >= 70" | bc -l) )); then
            color="yellow"
        elif (( $(echo "$percentage >= 60" | bc -l) )); then
            color="orange"
        fi
        
        # Generate SVG badge
        cat > "coverage-reports/${crate}-badge.svg" << EOF
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="20" viewBox="0 0 100 20">
  <rect width="100" height="20" rx="3" fill="${color}"/>
  <text x="50" y="10" font-family="monospace" font-size="12" fill="white" text-anchor="middle">
    ${percentage}%
  </text>
</svg>
EOF
    done
}

# Upload coverage to codecov
upload_coverage() {
    print_info "Uploading coverage to Codecov..."
    
    # Combine coverage reports
    local combined_file="coverage-reports/combined-coverage.json"
    python3 -c "
import json
import glob

combined = {}
for crate in ['vauchi-core', 'vauchi-relay', 'vauchi-tui', 'vauchi-mobile']:
    pattern = f'coverage-reports/{crate}*/coverage.json'
    files = glob.glob(pattern)
    
    for file in files:
        with open(file) as f:
            data = json.load(f)
            combined[crate] = data

with open('$combined_file', 'w') as f:
    json.dump(combined, f, indent=2)
"
    
    # Upload to codecov
    if command -v codecov &> /dev/null; then
        codecov --file coverage-reports/combined-coverage.json \
                --flags rust,frontend \
                --name vauchi-coverage \
                --verbose
    else
        print_warning "Codecov not found, skipping upload"
    fi
}

# Main execution
main() {
    print_status "Starting Vauchi coverage automation setup"
    
    # Setup tools
    setup_coverage_tools
    
    # Generate coverage reports
    generate_rust_coverage
    generate_frontend_coverage
    
    # Check coverage against targets
    if ! check_coverage_targets; then
        print_error "Coverage targets not met. Failing..."
        exit 1
    fi
    
    # Generate additional artifacts
    generate_trend_data
    generate_coverage_badges
    
    # Upload coverage
    upload_coverage

    print_status "Coverage automation setup complete!"
    print_info "Reports generated in: coverage-reports/"
    print_info "Trend data: coverage-reports/trend-data.json"
}

# Execute main function
main "$@"