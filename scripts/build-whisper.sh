#!/bin/bash
# build-whisper.sh - Build whisper.cpp framework for VoiceInk
# This script builds the whisper.xcframework needed for VoiceInk

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WHISPER_DIR="${PROJECT_ROOT}/../whisper.cpp"
FRAMEWORK_OUTPUT="${WHISPER_DIR}/build-apple/whisper.xcframework"

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

check_prerequisites() {
    print_status "Checking prerequisites for building whisper.cpp..."

    # Check if Xcode is installed
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode is not installed"
        echo "Please install Xcode from the Mac App Store"
        exit 1
    fi

    # Check if CMake is installed (optional, but helpful for manual builds)
    if ! command -v cmake &> /dev/null; then
        print_warning "CMake is not installed"
        echo "CMake is helpful for manual builds but not required for the build script"
        echo "Install with: brew install cmake"
    fi

    print_success "Prerequisites check passed"
}

clone_whisper_cpp() {
    print_status "Checking for whisper.cpp repository..."

    if [ ! -d "$WHISPER_DIR" ]; then
        print_status "Cloning whisper.cpp repository..."
        cd "$(dirname "$WHISPER_DIR")"
        git clone https://github.com/ggerganov/whisper.cpp.git
        cd - > /dev/null
        print_success "whisper.cpp cloned successfully"
    else
        print_success "whisper.cpp repository found at $WHISPER_DIR"

        # Ask if user wants to update
        printf "Do you want to update whisper.cpp to the latest version? (y/N): "
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Updating whisper.cpp..."
            cd "$WHISPER_DIR"
            git fetch origin
            git pull origin master
            cd - > /dev/null
            print_success "whisper.cpp updated to latest version"
        fi
    fi
}

check_build_script() {
    print_status "Checking for build-xcframework.sh script..."

    BUILD_SCRIPT="${WHISPER_DIR}/build-xcframework.sh"

    if [ ! -f "$BUILD_SCRIPT" ]; then
        print_error "build-xcframework.sh not found in whisper.cpp repository"
        echo "This script is required to build the framework"
        echo "Please ensure you have the latest version of whisper.cpp"
        exit 1
    fi

    # Make sure it's executable
    chmod +x "$BUILD_SCRIPT"
    print_success "Build script found and is executable"
}

clean_previous_build() {
    if [ -d "${WHISPER_DIR}/build-apple" ]; then
        printf "Do you want to clean the previous build? (y/N): "
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Cleaning previous build..."
            rm -rf "${WHISPER_DIR}/build-apple"
            print_success "Previous build cleaned"
        fi
    fi
}

build_framework() {
    print_status "Building whisper.xcframework..."
    print_status "This may take 5-10 minutes depending on your machine..."

    cd "$WHISPER_DIR"

    # Set build options (can be customized)
    export BUILD_SHARED_LIBS=OFF
    export WHISPER_BUILD_EXAMPLES=OFF
    export WHISPER_BUILD_TESTS=OFF
    export GGML_METAL=ON
    export GGML_METAL_EMBED_LIBRARY=ON

    # Run the build script
    if ./build-xcframework.sh; then
        print_success "Framework built successfully!"
    else
        print_error "Framework build failed"
        echo "Check the output above for error details"
        exit 1
    fi

    cd - > /dev/null
}

verify_framework() {
    print_status "Verifying framework build..."

    if [ ! -d "$FRAMEWORK_OUTPUT" ]; then
        print_error "Framework not found at expected location: $FRAMEWORK_OUTPUT"
        exit 1
    fi

    # Check framework structure
    if [ -d "${FRAMEWORK_OUTPUT}/ios-arm64" ] || [ -d "${FRAMEWORK_OUTPUT}/macos-arm64_x86_64" ]; then
        print_success "Framework structure verified"

        # Show framework info
        echo ""
        echo "Framework details:"
        echo "  Location: $FRAMEWORK_OUTPUT"
        echo "  Architectures:"
        ls -la "$FRAMEWORK_OUTPUT" | grep -E "ios-|macos-|tvos-|watchos-" | awk '{print "    - " $9}'

        # Check size
        FRAMEWORK_SIZE=$(du -sh "$FRAMEWORK_OUTPUT" | awk '{print $1}')
        echo "  Size: $FRAMEWORK_SIZE"
    else
        print_error "Framework structure is invalid"
        exit 1
    fi
}

link_framework() {
    print_status "Checking framework integration with VoiceInk..."

    # Check if framework is already linked in the Xcode project
    # This is informational only - actual linking happens in Xcode
    echo ""
    echo "To add the framework to VoiceInk:"
    echo "1. Open VoiceInk.xcodeproj in Xcode"
    echo "2. Select the VoiceInk target"
    echo "3. Go to 'General' tab → 'Frameworks, Libraries, and Embedded Content'"
    echo "4. Click '+' and add: ${FRAMEWORK_OUTPUT}"
    echo "5. Ensure 'Embed & Sign' is selected"
    echo ""
    echo "Or run: ./setup-project.sh for automatic setup"
}

# Main execution
main() {
    echo "================================================"
    echo "  Building whisper.cpp Framework for VoiceInk"
    echo "================================================"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Clone or update whisper.cpp
    clone_whisper_cpp

    # Check for build script
    check_build_script

    # Optional: clean previous build
    clean_previous_build

    # Build the framework
    build_framework

    # Verify the build
    verify_framework

    # Provide linking instructions
    link_framework

    echo ""
    echo "================================================"
    echo "  Build Complete!"
    echo "================================================"
    print_success "whisper.xcframework built successfully at:"
    echo "  ${FRAMEWORK_OUTPUT}"
    echo ""
    echo "Next steps:"
    echo "1. Run ./setup-project.sh to complete project setup"
    echo "2. Or manually add the framework to VoiceInk.xcodeproj"
    echo ""

    exit 0
}

# Handle script arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --clean)
            print_status "Forcing clean build..."
            rm -rf "${WHISPER_DIR}/build-apple"
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --clean    Clean previous build before building"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# Run main function
main
