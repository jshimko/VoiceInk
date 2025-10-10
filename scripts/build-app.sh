#!/bin/bash
# build-app.sh - Build VoiceInk application
# This script builds VoiceInk with various configuration options

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
BUILD_CONFIGURATION="Debug"
BUILD_ARCH=""
CLEAN_BUILD=false
OPEN_AFTER_BUILD=false
USE_XCPRETTY=false
PARALLEL_BUILD=true
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

print_build_info() {
    echo -e "${CYAN}[BUILD]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [options]

Build VoiceInk application with specified configuration.

Options:
    --configuration <config>  Build configuration (Debug|Release) [default: Debug]
    --arch <arch>            Build for specific architecture (arm64|x86_64|universal)
    --clean                  Clean before building
    --open                   Open app after successful build
    --pretty                 Use xcpretty for prettier output (if installed)
    --no-parallel           Disable parallel building
    --verbose               Show verbose build output
    --derived-data <path>    Custom derived data path
    --help                   Show this help message

Examples:
    $0                           # Build Debug configuration
    $0 --configuration Release   # Build Release configuration
    $0 --clean --open           # Clean build and open app
    $0 --arch universal         # Build universal binary

EOF
}

check_prerequisites() {
    print_status "Checking build prerequisites..."

    # Check Xcode
    if ! command -v xcodebuild &> /dev/null; then
        print_error "xcodebuild not found. Please install Xcode."
        exit 1
    fi

    # Check project file
    if [ ! -d "$PROJECT_FILE" ]; then
        print_error "Project file not found: $PROJECT_FILE"
        echo "Please run this script from the VoiceInk directory"
        exit 1
    fi

    # Check whisper framework
    WHISPER_FRAMEWORK="${PROJECT_ROOT}/../whisper.cpp/build-apple/whisper.xcframework"
    if [ ! -d "$WHISPER_FRAMEWORK" ]; then
        print_warning "whisper.xcframework not found"
        echo "Run ./setup-project.sh to build the framework"
        read -p "Do you want to build it now? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            "${SCRIPT_DIR}/build-whisper.sh"
        else
            exit 1
        fi
    fi

    # Check xcpretty if requested
    if [ "$USE_XCPRETTY" = true ]; then
        if ! command -v xcpretty &> /dev/null; then
            print_warning "xcpretty not found, falling back to standard output"
            echo "Install with: gem install xcpretty"
            USE_XCPRETTY=false
        fi
    fi

    print_success "Prerequisites check passed"
}

clean_build_folder() {
    if [ "$CLEAN_BUILD" = true ]; then
        print_status "Cleaning build folder..."
        rm -rf "$DERIVED_DATA_PATH"
        xcodebuild clean -project "$PROJECT_FILE" -scheme "$SCHEME" 2>&1 | tail -n 5
        print_success "Build folder cleaned"
    fi
}

resolve_packages() {
    print_status "Resolving Swift Package dependencies..."

    xcodebuild -project "$PROJECT_FILE" \
               -resolvePackageDependencies \
               -derivedDataPath "$DERIVED_DATA_PATH" \
               2>&1 | grep -E "Resolved|Fetching|Cloning|Checking" || true

    print_success "Package dependencies resolved"
}

get_build_settings() {
    print_build_info "Build Configuration:"
    echo "  Project: $(basename "$PROJECT_FILE")"
    echo "  Scheme: $SCHEME"
    echo "  Configuration: $BUILD_CONFIGURATION"

    if [ -n "$BUILD_ARCH" ]; then
        echo "  Architecture: $BUILD_ARCH"
    else
        echo "  Architecture: Native ($(uname -m))"
    fi

    echo "  Derived Data: $DERIVED_DATA_PATH"
    echo "  Parallel Build: $PARALLEL_BUILD"

    # Get version info from project
    MARKETING_VERSION=$(xcodebuild -project "$PROJECT_FILE" \
                                   -showBuildSettings \
                                   -configuration "$BUILD_CONFIGURATION" 2>/dev/null | \
                       grep "MARKETING_VERSION" | head -1 | awk '{print $3}')

    if [ -n "$MARKETING_VERSION" ]; then
        echo "  App Version: $MARKETING_VERSION"
    fi
}

build_app() {
    print_status "Starting build process..."
    echo ""
    get_build_settings
    echo ""

    # Prepare build command
    BUILD_CMD="xcodebuild"
    BUILD_ARGS=(
        "-project" "$PROJECT_FILE"
        "-scheme" "$SCHEME"
        "-configuration" "$BUILD_CONFIGURATION"
        "-derivedDataPath" "$DERIVED_DATA_PATH"
    )

    # Add architecture if specified
    if [ -n "$BUILD_ARCH" ]; then
        if [ "$BUILD_ARCH" = "universal" ]; then
            BUILD_ARGS+=("-arch" "arm64" "-arch" "x86_64" "ONLY_ACTIVE_ARCH=NO")
        else
            BUILD_ARGS+=("-arch" "$BUILD_ARCH")
        fi
    fi

    # Disable code signing for local builds if not configured
    if [ "$BUILD_CONFIGURATION" = "Debug" ]; then
        if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
            print_warning "No development certificate found, disabling code signing"
            BUILD_ARGS+=("CODE_SIGN_IDENTITY=" "CODE_SIGNING_REQUIRED=NO")
        fi
    fi

    # Add parallel build flag
    if [ "$PARALLEL_BUILD" = true ]; then
        BUILD_ARGS+=("-parallelizeTargets")
    fi

    # Show build command if verbose
    if [ "$VERBOSE" = true ]; then
        echo "Build command:"
        echo "  $BUILD_CMD ${BUILD_ARGS[*]}"
        echo ""
    fi

    # Execute build
    print_status "Building... (this may take a few minutes)"

    if [ "$USE_XCPRETTY" = true ]; then
        # Build with xcpretty
        set +e  # Don't exit on error immediately
        $BUILD_CMD "${BUILD_ARGS[@]}" build 2>&1 | xcpretty
        BUILD_RESULT=${PIPESTATUS[0]}
        set -e
    else
        # Build with standard output
        if [ "$VERBOSE" = true ]; then
            $BUILD_CMD "${BUILD_ARGS[@]}" build
        else
            # Show progress but limit output
            $BUILD_CMD "${BUILD_ARGS[@]}" build 2>&1 | while IFS= read -r line; do
                # Filter to show only important lines
                if echo "$line" | grep -E "Building|Compiling|Linking|Copying|Signing|Succeeded|Failed|Error|Warning" > /dev/null; then
                    echo "$line"
                elif echo "$line" | grep -E "^==|^\*\*" > /dev/null; then
                    echo "$line"
                fi
            done
            BUILD_RESULT=${PIPESTATUS[0]}
        fi
    fi

    # Check build result
    if [ "${BUILD_RESULT:-0}" -eq 0 ]; then
        print_success "Build completed successfully!"

        # Show app location
        APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${BUILD_CONFIGURATION}/VoiceInk.app"
        if [ -d "$APP_PATH" ]; then
            echo ""
            print_success "App built at:"
            echo "  $APP_PATH"

            # Show app size
            APP_SIZE=$(du -sh "$APP_PATH" | awk '{print $1}')
            echo "  Size: $APP_SIZE"
        fi
    else
        print_error "Build failed"
        echo "Check the output above for error details"
        exit 1
    fi
}

open_app() {
    if [ "$OPEN_AFTER_BUILD" = true ]; then
        APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${BUILD_CONFIGURATION}/VoiceInk.app"

        if [ -d "$APP_PATH" ]; then
            print_status "Opening VoiceInk..."
            open "$APP_PATH"
            print_success "App launched"
        else
            print_error "App not found at expected location"
        fi
    fi
}

show_build_summary() {
    echo ""
    echo "================================================"
    echo -e "${GREEN}  Build Summary${NC}"
    echo "================================================"

    APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${BUILD_CONFIGURATION}/VoiceInk.app"

    if [ -d "$APP_PATH" ]; then
        echo "Configuration: $BUILD_CONFIGURATION"
        echo "Location: $APP_PATH"

        # Get app info
        if [ -f "$APP_PATH/Contents/Info.plist" ]; then
            VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null)
            BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null)

            if [ -n "$VERSION" ]; then
                echo "Version: $VERSION (Build $BUILD)"
            fi
        fi

        echo ""
        echo "To run the app:"
        echo "  open \"$APP_PATH\""
        echo ""
        echo "Or from Xcode:"
        echo "  open $PROJECT_FILE"
        echo "  Then press Cmd+R"
    fi
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --configuration)
            BUILD_CONFIGURATION="$2"
            shift 2
            ;;
        --arch)
            BUILD_ARCH="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --open)
            OPEN_AFTER_BUILD=true
            shift
            ;;
        --pretty)
            USE_XCPRETTY=true
            shift
            ;;
        --no-parallel)
            PARALLEL_BUILD=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --derived-data)
            DERIVED_DATA_PATH="$2"
            shift 2
            ;;
        --release)
            BUILD_CONFIGURATION="Release"
            shift
            ;;
        --debug)
            BUILD_CONFIGURATION="Debug"
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
    echo -e "${MAGENTA}  Building VoiceInk${NC}"
    echo "================================================"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Clean if requested
    clean_build_folder

    # Resolve packages
    resolve_packages

    # Build the app
    build_app

    # Open if requested
    open_app

    # Show summary
    show_build_summary

    exit 0
}

# Run main function
main
