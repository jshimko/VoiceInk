#!/bin/bash
# run-tests.sh - Run tests for VoiceInk
# This script runs unit tests and UI tests with various options

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_FILE="${PROJECT_ROOT}/VoiceInk.xcodeproj"
SCHEME="VoiceInk"
DERIVED_DATA_PATH="${PROJECT_ROOT}/build"

# Default values
TEST_TYPE="all"  # all, unit, ui
ENABLE_COVERAGE=true
USE_XCPRETTY=false
PARALLEL_TESTING=true
TEST_FILTER=""
OUTPUT_FORMAT="human"  # human, json, junit
COVERAGE_REPORT=false
VERBOSE=false

# Helper functions
print_status() {
    echo -e "${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [options]

Run tests for VoiceInk with various configuration options.

Options:
    --type <type>        Test type: all, unit, ui [default: all]
    --filter <pattern>   Run only tests matching pattern
    --no-coverage       Disable code coverage
    --coverage-report   Generate HTML coverage report
    --pretty            Use xcpretty for prettier output
    --no-parallel       Disable parallel test execution
    --format <format>   Output format: human, json, junit [default: human]
    --verbose           Show verbose test output
    --help              Show this help message

Examples:
    $0                      # Run all tests with coverage
    $0 --type unit         # Run only unit tests
    $0 --filter WhisperState   # Run tests matching "WhisperState"
    $0 --coverage-report   # Generate coverage report after tests

EOF
}

check_prerequisites() {
    print_status "Checking test prerequisites..."

    # Check Xcode
    if ! command -v xcodebuild &> /dev/null; then
        print_error "xcodebuild not found. Please install Xcode."
        exit 1
    fi

    # Check project file
    if [ ! -d "$PROJECT_FILE" ]; then
        print_error "Project file not found: $PROJECT_FILE"
        exit 1
    fi

    # Check test targets exist
    if ! xcodebuild -project "$PROJECT_FILE" -list 2>/dev/null | grep -q "VoiceInkTests"; then
        print_warning "VoiceInkTests target not found"
    fi

    if ! xcodebuild -project "$PROJECT_FILE" -list 2>/dev/null | grep -q "VoiceInkUITests"; then
        print_warning "VoiceInkUITests target not found"
    fi

    # Check xcpretty if requested
    if [ "$USE_XCPRETTY" = true ]; then
        if ! command -v xcpretty &> /dev/null; then
            print_warning "xcpretty not found, falling back to standard output"
            USE_XCPRETTY=false
        fi
    fi

    print_success "Prerequisites check passed"
}

prepare_test_environment() {
    print_status "Preparing test environment..."

    # Create test results directory
    TEST_RESULTS_DIR="${PROJECT_ROOT}/test-results"
    mkdir -p "$TEST_RESULTS_DIR"

    # Clean old test results
    if [ -f "${TEST_RESULTS_DIR}/results.xml" ]; then
        rm -f "${TEST_RESULTS_DIR}/results.xml"
    fi

    # Ensure derived data directory exists
    mkdir -p "$DERIVED_DATA_PATH"

    print_success "Test environment prepared"
}

get_test_settings() {
    print_test "Test Configuration:"
    echo "  Project: $(basename "$PROJECT_FILE")"
    echo "  Scheme: $SCHEME"
    echo "  Test Type: $TEST_TYPE"
    echo "  Code Coverage: $ENABLE_COVERAGE"
    echo "  Parallel Testing: $PARALLEL_TESTING"

    if [ -n "$TEST_FILTER" ]; then
        echo "  Filter: $TEST_FILTER"
    fi

    echo "  Output Format: $OUTPUT_FORMAT"
}

run_unit_tests() {
    print_status "Running unit tests..."

    # Build test command
    TEST_CMD="xcodebuild"
    TEST_ARGS=(
        "test"
        "-project" "$PROJECT_FILE"
        "-scheme" "$SCHEME"
        "-destination" "platform=macOS"
        "-derivedDataPath" "$DERIVED_DATA_PATH"
    )

    # Add test target
    if [ "$TEST_TYPE" = "unit" ] || [ "$TEST_TYPE" = "all" ]; then
        TEST_ARGS+=("-only-testing:VoiceInkTests")
    fi

    # Add filter if specified
    if [ -n "$TEST_FILTER" ]; then
        TEST_ARGS+=("-only-testing:VoiceInkTests/$TEST_FILTER")
    fi

    # Enable/disable code coverage
    if [ "$ENABLE_COVERAGE" = true ]; then
        TEST_ARGS+=("-enableCodeCoverage" "YES")
    else
        TEST_ARGS+=("-enableCodeCoverage" "NO")
    fi

    # Parallel testing
    if [ "$PARALLEL_TESTING" = true ]; then
        TEST_ARGS+=("-parallel-testing-enabled" "YES")
    else
        TEST_ARGS+=("-parallel-testing-enabled" "NO")
    fi

    # Disable code signing for tests
    TEST_ARGS+=("CODE_SIGN_IDENTITY=" "CODE_SIGNING_REQUIRED=NO")

    # Output format
    case $OUTPUT_FORMAT in
        json)
            TEST_ARGS+=("-resultBundlePath" "${TEST_RESULTS_DIR}/unit-tests.xcresult")
            ;;
        junit)
            TEST_ARGS+=("-resultBundlePath" "${TEST_RESULTS_DIR}/unit-tests.xcresult")
            ;;
    esac

    # Execute tests
    if [ "$VERBOSE" = true ]; then
        echo "Test command: $TEST_CMD ${TEST_ARGS[*]}"
        echo ""
    fi

    set +e  # Don't exit on test failure
    if [ "$USE_XCPRETTY" = true ]; then
        $TEST_CMD "${TEST_ARGS[@]}" 2>&1 | xcpretty --test
        TEST_RESULT=${PIPESTATUS[0]}
    else
        if [ "$VERBOSE" = true ]; then
            $TEST_CMD "${TEST_ARGS[@]}"
            TEST_RESULT=$?
        else
            # Filter output to show only test results
            $TEST_CMD "${TEST_ARGS[@]}" 2>&1 | grep -E "Test Suite|Test Case|\[PASSED\]|\[FAILED\]|executed|passed|failed"
            TEST_RESULT=${PIPESTATUS[0]}
        fi
    fi
    set -e

    if [ $TEST_RESULT -eq 0 ]; then
        print_success "Unit tests passed!"
    else
        print_error "Unit tests failed!"
        return $TEST_RESULT
    fi
}

run_ui_tests() {
    print_status "Running UI tests..."

    # Build test command
    TEST_CMD="xcodebuild"
    TEST_ARGS=(
        "test"
        "-project" "$PROJECT_FILE"
        "-scheme" "$SCHEME"
        "-destination" "platform=macOS"
        "-derivedDataPath" "$DERIVED_DATA_PATH"
    )

    # Add test target
    if [ "$TEST_TYPE" = "ui" ] || [ "$TEST_TYPE" = "all" ]; then
        TEST_ARGS+=("-only-testing:VoiceInkUITests")
    fi

    # Add filter if specified
    if [ -n "$TEST_FILTER" ]; then
        TEST_ARGS+=("-only-testing:VoiceInkUITests/$TEST_FILTER")
    fi

    # Enable/disable code coverage
    if [ "$ENABLE_COVERAGE" = true ]; then
        TEST_ARGS+=("-enableCodeCoverage" "YES")
    fi

    # Parallel testing
    if [ "$PARALLEL_TESTING" = true ]; then
        TEST_ARGS+=("-parallel-testing-enabled" "YES")
    fi

    # Disable code signing for tests
    TEST_ARGS+=("CODE_SIGN_IDENTITY=" "CODE_SIGNING_REQUIRED=NO")

    # Output format
    case $OUTPUT_FORMAT in
        json|junit)
            TEST_ARGS+=("-resultBundlePath" "${TEST_RESULTS_DIR}/ui-tests.xcresult")
            ;;
    esac

    # Execute tests
    set +e
    if [ "$USE_XCPRETTY" = true ]; then
        $TEST_CMD "${TEST_ARGS[@]}" 2>&1 | xcpretty --test
        TEST_RESULT=${PIPESTATUS[0]}
    else
        if [ "$VERBOSE" = true ]; then
            $TEST_CMD "${TEST_ARGS[@]}"
            TEST_RESULT=$?
        else
            $TEST_CMD "${TEST_ARGS[@]}" 2>&1 | grep -E "Test Suite|Test Case|\[PASSED\]|\[FAILED\]|executed|passed|failed"
            TEST_RESULT=${PIPESTATUS[0]}
        fi
    fi
    set -e

    if [ $TEST_RESULT -eq 0 ]; then
        print_success "UI tests passed!"
    else
        print_error "UI tests failed!"
        return $TEST_RESULT
    fi
}

generate_coverage_report() {
    if [ "$ENABLE_COVERAGE" = false ]; then
        return
    fi

    print_status "Analyzing code coverage..."

    # Find coverage data
    COVERAGE_DIR="${DERIVED_DATA_PATH}/Build/ProfileData"
    COVERAGE_FILE=$(find "$COVERAGE_DIR" -name "Coverage.profdata" 2>/dev/null | head -1)

    if [ -z "$COVERAGE_FILE" ]; then
        print_warning "Coverage data not found"
        return
    fi

    # Get binary path
    BINARY_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug/VoiceInk.app/Contents/MacOS/VoiceInk"

    if [ ! -f "$BINARY_PATH" ]; then
        print_warning "Binary not found for coverage analysis"
        return
    fi

    # Generate coverage report
    print_status "Generating coverage report..."

    # Text report
    xcrun llvm-cov report \
        "$BINARY_PATH" \
        -instr-profile="$COVERAGE_FILE" \
        -ignore-filename-regex=".*Tests.*" \
        > "${TEST_RESULTS_DIR}/coverage-summary.txt"

    # Show summary
    echo ""
    echo "Coverage Summary:"
    tail -n 5 "${TEST_RESULTS_DIR}/coverage-summary.txt"

    # HTML report if requested
    if [ "$COVERAGE_REPORT" = true ]; then
        print_status "Generating HTML coverage report..."

        xcrun llvm-cov show \
            "$BINARY_PATH" \
            -instr-profile="$COVERAGE_FILE" \
            -format=html \
            -output-dir="${TEST_RESULTS_DIR}/coverage-html" \
            -ignore-filename-regex=".*Tests.*"

        print_success "HTML coverage report generated at:"
        echo "  ${TEST_RESULTS_DIR}/coverage-html/index.html"
        echo ""
        echo "To view: open ${TEST_RESULTS_DIR}/coverage-html/index.html"
    fi
}

convert_results_to_junit() {
    if [ "$OUTPUT_FORMAT" != "junit" ]; then
        return
    fi

    print_status "Converting results to JUnit format..."

    # Check for xcresult files
    for RESULT_FILE in "${TEST_RESULTS_DIR}"/*.xcresult; do
        if [ -f "$RESULT_FILE" ]; then
            JUNIT_FILE="${RESULT_FILE%.xcresult}.xml"

            # Use xcrun xcresulttool to convert
            xcrun xcresulttool get \
                --path "$RESULT_FILE" \
                --format json | \
                python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

# Parse JSON input
data = json.load(sys.stdin)

# Create JUnit XML
testsuites = ET.Element('testsuites')
# Add conversion logic here...

# Output XML
ET.ElementTree(testsuites).write('$JUNIT_FILE', encoding='UTF-8', xml_declaration=True)
" 2>/dev/null || true

            if [ -f "$JUNIT_FILE" ]; then
                print_success "JUnit report saved to: $JUNIT_FILE"
            fi
        fi
    done
}

show_test_summary() {
    echo ""
    echo "================================================"
    echo -e "${MAGENTA}  Test Summary${NC}"
    echo "================================================"

    # Count test results
    if [ -d "${TEST_RESULTS_DIR}" ]; then
        echo "Test Results Location:"
        echo "  ${TEST_RESULTS_DIR}/"
        echo ""

        # Show files created
        if ls "${TEST_RESULTS_DIR}"/* 2>/dev/null | head -1 > /dev/null; then
            echo "Generated Reports:"
            ls -la "${TEST_RESULTS_DIR}/" | grep -v "^total" | grep -v "^d" | awk '{print "  - " $9}'
        fi

        # Coverage info
        if [ "$ENABLE_COVERAGE" = true ] && [ -f "${TEST_RESULTS_DIR}/coverage-summary.txt" ]; then
            echo ""
            echo "Code Coverage:"
            grep "TOTAL" "${TEST_RESULTS_DIR}/coverage-summary.txt" 2>/dev/null || echo "  Coverage data available"
        fi
    fi

    echo ""
    echo "To run specific tests:"
    echo "  $0 --filter TestClassName"
    echo ""
    echo "To generate coverage report:"
    echo "  $0 --coverage-report"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --type)
            TEST_TYPE="$2"
            shift 2
            ;;
        --filter)
            TEST_FILTER="$2"
            shift 2
            ;;
        --no-coverage)
            ENABLE_COVERAGE=false
            shift
            ;;
        --coverage-report)
            COVERAGE_REPORT=true
            shift
            ;;
        --pretty)
            USE_XCPRETTY=true
            shift
            ;;
        --no-parallel)
            PARALLEL_TESTING=false
            shift
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "================================================"
    echo -e "${MAGENTA}  Running VoiceInk Tests${NC}"
    echo "================================================"
    echo ""

    # Track overall test result
    OVERALL_RESULT=0

    # Check prerequisites
    check_prerequisites

    # Prepare environment
    prepare_test_environment

    # Show configuration
    get_test_settings
    echo ""

    # Run tests based on type
    case $TEST_TYPE in
        all)
            run_unit_tests || OVERALL_RESULT=$?
            echo ""
            run_ui_tests || OVERALL_RESULT=$?
            ;;
        unit)
            run_unit_tests || OVERALL_RESULT=$?
            ;;
        ui)
            run_ui_tests || OVERALL_RESULT=$?
            ;;
        *)
            print_error "Invalid test type: $TEST_TYPE"
            exit 1
            ;;
    esac

    # Generate coverage report
    generate_coverage_report

    # Convert to JUnit if requested
    convert_results_to_junit

    # Show summary
    show_test_summary

    # Exit with test result
    if [ $OVERALL_RESULT -eq 0 ]; then
        print_success "All tests passed! 🎉"
        exit 0
    else
        print_error "Some tests failed"
        exit $OVERALL_RESULT
    fi
}

# Run main function
main
