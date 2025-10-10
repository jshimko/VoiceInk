#!/bin/bash
# clean-build.sh - Clean build artifacts and caches for VoiceInk
# This script provides various levels of cleaning for the build system

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_FILE="${PROJECT_ROOT}/VoiceInk.xcodeproj"
DERIVED_DATA_PATH="${PROJECT_ROOT}/build"
WHISPER_DIR="${PROJECT_ROOT}/../whisper.cpp"

# Default values
CLEAN_LEVEL="normal"  # normal, deep, full
DRY_RUN=false
VERBOSE=false
CLEAN_WHISPER=false
CLEAN_PACKAGES=false

# Helper functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

print_clean() {
    echo -e "${CYAN}[CLEAN]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [options]

Clean build artifacts and caches for VoiceInk project.

Options:
    --level <level>     Clean level: normal, deep, full [default: normal]
    --whisper          Also clean whisper.cpp build
    --packages         Also clean Swift Package cache
    --dry-run          Show what would be cleaned without doing it
    --verbose          Show detailed output
    --help             Show this help message

Clean Levels:
    normal   - Clean project build folder and Xcode derived data
    deep     - Normal + Swift Package caches and module cache
    full     - Deep + all Xcode caches and simulator data

Examples:
    $0                      # Normal clean
    $0 --level deep        # Deep clean including caches
    $0 --whisper           # Clean including whisper.cpp
    $0 --dry-run          # Preview what will be cleaned

EOF
}

calculate_size() {
    local path="$1"
    if [ -d "$path" ]; then
        du -sh "$path" 2>/dev/null | awk '{print $1}'
    else
        echo "0"
    fi
}

remove_directory() {
    local path="$1"
    local description="$2"

    if [ -d "$path" ]; then
        SIZE=$(calculate_size "$path")
        print_clean "Removing $description ($SIZE)..."

        if [ "$DRY_RUN" = true ]; then
            echo "  Would remove: $path"
        else
            if [ "$VERBOSE" = true ]; then
                echo "  Removing: $path"
            fi
            rm -rf "$path"
            print_success "$description removed"
        fi
    elif [ "$VERBOSE" = true ]; then
        echo "  Skipping $description (not found)"
    fi
}

remove_file() {
    local path="$1"
    local description="$2"

    if [ -f "$path" ]; then
        print_clean "Removing $description..."

        if [ "$DRY_RUN" = true ]; then
            echo "  Would remove: $path"
        else
            if [ "$VERBOSE" = true ]; then
                echo "  Removing: $path"
            fi
            rm -f "$path"
            print_success "$description removed"
        fi
    elif [ "$VERBOSE" = true ]; then
        echo "  Skipping $description (not found)"
    fi
}

clean_xcode_project() {
    print_status "Cleaning Xcode project..."

    if [ ! -d "$PROJECT_FILE" ]; then
        print_warning "Project file not found: $PROJECT_FILE"
        return
    fi

    if [ "$DRY_RUN" = false ]; then
        # Run xcodebuild clean
        print_clean "Running xcodebuild clean..."
        xcodebuild clean \
            -project "$PROJECT_FILE" \
            -scheme VoiceInk \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            2>&1 | tail -n 5

        print_success "Xcode project cleaned"
    else
        echo "  Would run: xcodebuild clean"
    fi
}

clean_derived_data() {
    print_status "Cleaning derived data..."

    # Local derived data
    remove_directory "$DERIVED_DATA_PATH" "local derived data"

    # Xcode's global derived data for this project
    GLOBAL_DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
    if [ -d "$GLOBAL_DERIVED_DATA" ]; then
        # Find directories related to VoiceInk
        for dir in "$GLOBAL_DERIVED_DATA"/VoiceInk-*; do
            if [ -d "$dir" ]; then
                remove_directory "$dir" "global derived data"
            fi
        done
    fi
}

clean_build_artifacts() {
    print_status "Cleaning build artifacts..."

    # Test results
    remove_directory "${PROJECT_ROOT}/test-results" "test results"

    # Coverage reports
    remove_directory "${PROJECT_ROOT}/coverage" "coverage reports"

    # Archive builds
    remove_directory "${PROJECT_ROOT}/archives" "archive builds"

    # Build logs
    remove_file "${PROJECT_ROOT}/build.log" "build log"
    remove_file "${PROJECT_ROOT}/test.log" "test log"

    # Local config files (optional)
    if [ -f "${PROJECT_ROOT}/.build-config" ]; then
        read -p "Remove local build configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remove_file "${PROJECT_ROOT}/.build-config" "local build config"
        fi
    fi
}

clean_swift_packages() {
    if [ "$CLEAN_PACKAGES" = false ] && [ "$CLEAN_LEVEL" != "deep" ] && [ "$CLEAN_LEVEL" != "full" ]; then
        return
    fi

    print_status "Cleaning Swift Package caches..."

    # SPM cache locations
    remove_directory "$HOME/Library/Caches/org.swift.swiftpm" "Swift Package Manager cache"
    remove_directory "$HOME/Library/Developer/Xcode/DerivedData/ModuleCache" "Module cache"

    # Local package resolution
    remove_file "${PROJECT_FILE}/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" "Package.resolved"

    # Package build artifacts
    remove_directory "${PROJECT_ROOT}/.build" "local package builds"
    remove_directory "${PROJECT_ROOT}/.swiftpm" "Swift package metadata"
}

clean_xcode_caches() {
    if [ "$CLEAN_LEVEL" != "full" ]; then
        return
    fi

    print_status "Cleaning Xcode caches (full clean)..."

    # Xcode caches
    remove_directory "$HOME/Library/Caches/com.apple.dt.Xcode" "Xcode cache"

    # Simulator caches (be careful with this)
    echo ""
    read -p "${YELLOW}Clean iOS Simulator data? This will reset all simulators! (y/N):${NC} " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ "$DRY_RUN" = false ]; then
            xcrun simctl shutdown all 2>/dev/null || true
            xcrun simctl erase all 2>/dev/null || true
            print_success "Simulator data reset"
        else
            echo "  Would reset all simulator data"
        fi
    fi

    # Archives
    ARCHIVES_DIR="$HOME/Library/Developer/Xcode/Archives"
    if [ -d "$ARCHIVES_DIR" ]; then
        SIZE=$(calculate_size "$ARCHIVES_DIR")
        echo ""
        read -p "${YELLOW}Clean Xcode archives ($SIZE)? (y/N):${NC} " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remove_directory "$ARCHIVES_DIR" "Xcode archives"
        fi
    fi
}

clean_whisper() {
    if [ "$CLEAN_WHISPER" = false ]; then
        return
    fi

    print_status "Cleaning whisper.cpp build..."

    if [ -d "$WHISPER_DIR" ]; then
        # Clean whisper build artifacts
        remove_directory "${WHISPER_DIR}/build-apple" "whisper.cpp build"
        remove_directory "${WHISPER_DIR}/build" "whisper.cpp CMake build"
        remove_directory "${WHISPER_DIR}/.build" "whisper.cpp local build"

        print_success "whisper.cpp cleaned"
    else
        print_warning "whisper.cpp directory not found"
    fi
}

show_disk_space() {
    print_status "Checking disk space..."

    echo ""
    echo "Disk usage before cleaning:"
    df -h / | awk 'NR<=2'

    # Calculate potential space to free
    TOTAL_SIZE=0

    add_size() {
        local path="$1"
        if [ -d "$path" ]; then
            SIZE_BYTES=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE_BYTES))
        fi
    }

    add_size "$DERIVED_DATA_PATH"
    add_size "$HOME/Library/Developer/Xcode/DerivedData/VoiceInk-"*
    add_size "$HOME/Library/Caches/org.swift.swiftpm"

    if [ "$CLEAN_WHISPER" = true ]; then
        add_size "${WHISPER_DIR}/build-apple"
    fi

    if [ $TOTAL_SIZE -gt 0 ]; then
        TOTAL_SIZE_MB=$((TOTAL_SIZE / 1024))
        echo ""
        echo "Estimated space to free: ${TOTAL_SIZE_MB}MB"
    fi
}

clean_summary() {
    echo ""
    echo "================================================"
    echo -e "${GREEN}  Clean Complete${NC}"
    echo "================================================"

    if [ "$DRY_RUN" = true ]; then
        print_warning "This was a dry run - no files were actually deleted"
        echo "Run without --dry-run to perform the clean"
    else
        print_success "All specified items have been cleaned"

        echo ""
        echo "Disk usage after cleaning:"
        df -h / | awk 'NR<=2'

        echo ""
        echo "Next steps:"
        echo "  1. Run ./setup-project.sh to rebuild dependencies"
        echo "  2. Run ./build-app.sh to build the app"
    fi
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --level)
            CLEAN_LEVEL="$2"
            shift 2
            ;;
        --whisper)
            CLEAN_WHISPER=true
            shift
            ;;
        --packages)
            CLEAN_PACKAGES=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
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
    echo -e "${CYAN}  VoiceInk Build Cleaner${NC}"
    echo "================================================"
    echo ""
    echo "Clean level: $CLEAN_LEVEL"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN MODE - No files will be deleted${NC}"
    fi

    echo ""

    # Show disk space before
    show_disk_space

    echo ""
    read -p "Proceed with cleaning? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Clean cancelled"
        exit 0
    fi

    echo ""

    # Perform cleaning based on level
    case $CLEAN_LEVEL in
        normal)
            clean_xcode_project
            clean_derived_data
            clean_build_artifacts
            ;;
        deep)
            clean_xcode_project
            clean_derived_data
            clean_build_artifacts
            clean_swift_packages
            ;;
        full)
            clean_xcode_project
            clean_derived_data
            clean_build_artifacts
            clean_swift_packages
            clean_xcode_caches
            ;;
        *)
            print_error "Invalid clean level: $CLEAN_LEVEL"
            exit 1
            ;;
    esac

    # Clean whisper if requested
    clean_whisper

    # Show summary
    clean_summary

    exit 0
}

# Run main function
main
