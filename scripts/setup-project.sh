#!/bin/bash
# setup-project.sh - Complete project setup for VoiceInk
# This script handles the entire setup process from clone to ready-to-build

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
WHISPER_DIR="${PROJECT_ROOT}/../whisper.cpp"
FRAMEWORK_PATH="${WHISPER_DIR}/build-apple/whisper.xcframework"
VOICEINK_REPO="https://github.com/Beingpax/VoiceInk.git"

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

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

show_progress() {
    local current=$1
    local total=$2
    local task=$3
    echo ""
    echo -e "${CYAN}Progress: [$current/$total]${NC} $task"
    echo "================================================"
}

check_environment() {
    show_progress 1 7 "Checking development environment..."

    print_status "Running environment check (may prompt for installations)..."
    if "${SCRIPT_DIR}/setup-environment.sh"; then
        print_success "Environment check passed"
        return 0
    else
        print_error "Environment check failed"
        echo "Please fix the issues above and run this script again"
        return 1
    fi
}

setup_whisper_cpp() {
    show_progress 2 7 "Setting up whisper.cpp framework..."

    # Check if whisper.cpp exists
    if [ ! -d "$WHISPER_DIR" ]; then
        print_status "Cloning whisper.cpp repository..."
        cd "$(dirname "$WHISPER_DIR")"
        if ! git clone https://github.com/ggerganov/whisper.cpp.git; then
            print_error "Failed to clone whisper.cpp repository"
            return 1
        fi
        cd - > /dev/null
        print_success "whisper.cpp cloned successfully"
    else
        print_success "whisper.cpp already exists at $WHISPER_DIR"
    fi

    # Check if framework is already built
    if [ -d "$FRAMEWORK_PATH" ]; then
        print_success "whisper.xcframework already built"
        printf "Do you want to rebuild the framework? (Y/n): "
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if ! "${SCRIPT_DIR}/build-whisper.sh"; then
                print_error "Failed to build whisper.xcframework"
                return 1
            fi
        fi
    else
        print_status "Building whisper.xcframework..."
        if ! "${SCRIPT_DIR}/build-whisper.sh"; then
            print_error "Failed to build whisper.xcframework"
            return 1
        fi
    fi
    return 0
}

configure_xcode_project() {
    show_progress 3 7 "Configuring Xcode project..."

    print_status "Checking Xcode project file..."
    if [ ! -f "${PROJECT_ROOT}/VoiceInk.xcodeproj/project.pbxproj" ]; then
        print_error "VoiceInk.xcodeproj not found"
        echo "Please ensure you're running this script from the VoiceInk directory"
        exit 1
    fi

    print_success "Xcode project found"

    # Check if framework reference exists in project
    if grep -q "whisper.xcframework" "${PROJECT_ROOT}/VoiceInk.xcodeproj/project.pbxproj"; then
        print_success "whisper.xcframework reference found in project"
    else
        print_warning "whisper.xcframework not linked in project"
        echo ""
        echo "Please add the framework manually in Xcode:"
        echo "1. Open VoiceInk.xcodeproj"
        echo "2. Select VoiceInk target → General → Frameworks, Libraries, and Embedded Content"
        echo "3. Click '+' and add: ${FRAMEWORK_PATH}"
        echo "4. Set to 'Embed & Sign'"
    fi
}

resolve_swift_packages() {
    show_progress 4 7 "Resolving Swift Package dependencies..."

    print_status "Resolving package dependencies..."

    # Use xcodebuild to resolve packages
    if xcodebuild -project "${PROJECT_ROOT}/VoiceInk.xcodeproj" \
                  -resolvePackageDependencies \
                  -clonedSourcePackagesDirPath "${PROJECT_ROOT}/.build" \
                  2>&1 | grep -v "note:" > /dev/null; then
        print_success "Swift packages resolved successfully"
    else
        print_warning "Package resolution had warnings or errors"
        echo "Xcode will attempt to resolve packages when you open the project"
    fi
}

setup_code_signing() {
    show_progress 5 7 "Configuring code signing..."

    print_status "Checking code signing configuration..."

    # Check for development certificates
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development\|Mac Developer"; then
        print_success "Development certificate found"
        CERT_NAME=$(security find-identity -v -p codesigning | grep -E "Apple Development|Mac Developer" | head -1 | sed 's/.*"\(.*\)".*/\1/')
        echo "  Certificate: $CERT_NAME"
        return 0
    else
        print_warning "No development certificate found"
        echo ""
        echo "For local development:"
        echo "1. Open VoiceInk.xcodeproj in Xcode"
        echo "2. Select VoiceInk target → Signing & Capabilities"
        echo "3. Enable 'Automatically manage signing'"
        echo "4. Select your personal team (or add your Apple ID)"
        return 1  # Return failure for code signing
    fi
}

create_local_config() {
    show_progress 6 7 "Creating local configuration..."

    # Create a local config file for build settings (optional)
    LOCAL_CONFIG="${PROJECT_ROOT}/.env"

    if [ ! -f "$LOCAL_CONFIG" ]; then
        print_status "Creating local build configuration..."
        cat > "$LOCAL_CONFIG" << EOF
# VoiceInk Local Build Configuration
# Generated by setup-project.sh on $(date)

# Build settings
BUILD_CONFIGURATION="Debug"
BUILD_ARCH="$(uname -m)"
DERIVED_DATA_PATH="${PROJECT_ROOT}/build"

# Code signing (update with your values)
CODE_SIGN_IDENTITY=""
DEVELOPMENT_TEAM=""

# Paths
WHISPER_FRAMEWORK_PATH="${FRAMEWORK_PATH}"
EOF
        print_success "Local configuration created at .env"
    else
        print_success "Local configuration already exists"
    fi

    # Create .gitignore entry for local config
    if ! grep -q ".env" "${PROJECT_ROOT}/.gitignore" 2>/dev/null; then
        echo "" >> "${PROJECT_ROOT}/.gitignore"
        echo "# Local build configuration" >> "${PROJECT_ROOT}/.gitignore"
        echo ".env" >> "${PROJECT_ROOT}/.gitignore"
        print_success "Added .env to .gitignore"
    fi
}

verify_setup() {
    print_status "Verifying setup configuration..."

    local VERIFICATION_SUCCESS=true
    local ISSUES_FOUND=""

    # Check whisper.cpp framework
    if [ ! -d "$FRAMEWORK_PATH" ]; then
        print_error "whisper.xcframework not found at $FRAMEWORK_PATH"
        VERIFICATION_SUCCESS=false
        ISSUES_FOUND="${ISSUES_FOUND}  - Missing whisper.xcframework\n"
    else
        print_success "whisper.xcframework verified"
    fi

    # Check CMake (required for rebuilds)
    if ! command -v cmake &> /dev/null; then
        print_error "CMake not installed (required for building whisper.cpp)"
        VERIFICATION_SUCCESS=false
        ISSUES_FOUND="${ISSUES_FOUND}  - CMake not installed\n"
    else
        print_success "CMake available"
    fi

    # Check Xcode project
    if [ ! -f "${PROJECT_ROOT}/VoiceInk.xcodeproj/project.pbxproj" ]; then
        print_error "Xcode project file not found"
        VERIFICATION_SUCCESS=false
        ISSUES_FOUND="${ISSUES_FOUND}  - Xcode project missing\n"
    else
        print_success "Xcode project verified"
    fi

    # Check build tools
    if ! xcodebuild -version &> /dev/null; then
        print_error "xcodebuild not available"
        VERIFICATION_SUCCESS=false
        ISSUES_FOUND="${ISSUES_FOUND}  - Xcode command line tools issue\n"
    else
        print_success "Build tools verified"
    fi

    if [ "$VERIFICATION_SUCCESS" = false ]; then
        echo ""
        echo -e "${RED}Setup verification failed. Issues found:${NC}"
        echo -e "$ISSUES_FOUND"
        return 1
    else
        print_success "All critical components verified!"
        return 0
    fi
}

run_initial_build() {
    show_progress 7 7 "Running initial build test..."

    printf "Do you want to run a test build now? (Y/n): "
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        print_status "Running test build..."

        if "${SCRIPT_DIR}/build-app.sh" --configuration Debug; then
            print_success "Test build completed successfully!"
            return 0
        else
            print_warning "Test build failed"
            echo "This might be due to code signing or framework linking issues"
            echo "Try opening the project in Xcode to resolve any issues"
            return 1
        fi
    else
        print_status "Skipping test build"
        return 0
    fi
}

create_shortcuts() {
    print_status "Creating convenience shortcuts..."

    # Create a simple 'build' command in project root
    cat > "${PROJECT_ROOT}/build" << 'EOF'
#!/bin/bash
# Quick build command
exec "${0%/*}/scripts/build-app.sh" "$@"
EOF
    chmod +x "${PROJECT_ROOT}/build"

    # Create a simple 'test' command in project root
    cat > "${PROJECT_ROOT}/test" << 'EOF'
#!/bin/bash
# Quick test command
exec "${0%/*}/scripts/run-tests.sh" "$@"
EOF
    chmod +x "${PROJECT_ROOT}/test"

    print_success "Created shortcuts: ./build and ./test"
}

show_success_message() {
    echo ""
    echo "================================================"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo "================================================"
    echo ""
    echo "Your VoiceInk development environment is ready!"
    echo ""
    echo -e "${CYAN}Quick Commands:${NC}"
    echo "  ./build           - Build the app (debug)"
    echo "  ./build --release - Build the app (release)"
    echo "  ./test            - Run all tests"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "1. Open the project in Xcode:"
    echo "   open VoiceInk.xcodeproj"
    echo ""
    echo "2. Configure code signing:"
    echo "   - Select VoiceInk target"
    echo "   - Go to Signing & Capabilities"
    echo "   - Enable automatic signing"
    echo "   - Select your team"
    echo ""
    echo "3. Build and run:"
    echo "   - Press Cmd+R in Xcode"
    echo "   - Or use: ./build"
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "  See docs/build.md for detailed build instructions"
    echo ""
    echo -e "${GREEN}Happy coding! 🚀${NC}"
}

show_failure_message() {
    echo ""
    echo "================================================"
    echo -e "${RED}  Setup Failed${NC}"
    echo "================================================"
    echo ""
    echo -e "${RED}Critical issues were found that will prevent builds from succeeding.${NC}"
    echo ""
    echo "Please review the errors above and:"
    echo "1. Fix the reported issues"
    echo "2. Run this setup script again"
    echo ""
    echo "For help, see docs/build.md or open an issue on GitHub"
}

# Main execution
main() {
    echo "================================================"
    echo "  VoiceInk Project Setup"
    echo "================================================"
    echo ""
    echo "This script will:"
    echo "  1. Check your development environment"
    echo "  2. Clone and build whisper.cpp"
    echo "  3. Configure the Xcode project"
    echo "  4. Resolve Swift Package dependencies"
    echo "  5. Set up code signing"
    echo "  6. Create local configuration"
    echo "  7. Run a test build (optional)"
    echo ""

    printf "Continue with setup? (Y/n): "
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Setup cancelled"
        exit 0
    fi

    echo ""

    # Track setup status
    SETUP_SUCCESS=true
    CRITICAL_FAILURES=""
    WARNINGS=""

    # Run setup steps
    if ! check_environment; then
        SETUP_SUCCESS=false
        CRITICAL_FAILURES="${CRITICAL_FAILURES}Environment check failed\n"
    fi

    if ! setup_whisper_cpp; then
        SETUP_SUCCESS=false
        CRITICAL_FAILURES="${CRITICAL_FAILURES}Whisper.cpp framework setup failed\n"
    fi

    configure_xcode_project

    resolve_swift_packages

    if ! setup_code_signing; then
        WARNINGS="${WARNINGS}Code signing not configured (required for distribution)\n"
    fi

    create_local_config
    create_shortcuts

    # Run verification
    echo ""
    if ! verify_setup; then
        SETUP_SUCCESS=false
        CRITICAL_FAILURES="${CRITICAL_FAILURES}Setup verification failed\n"
    fi

    # Only run build test if everything else succeeded
    if [ "$SETUP_SUCCESS" = true ]; then
        run_initial_build
    fi

    # Show summary
    echo ""
    echo "================================================"
    echo "  Setup Summary"
    echo "================================================"
    echo ""

    # Show status of each component
    echo -e "${CYAN}Component Status:${NC}"
    echo ""

    # Environment
    if command -v xcodebuild &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Xcode installed"
    else
        echo -e "  ${RED}✗${NC} Xcode missing"
    fi

    if command -v cmake &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} CMake installed"
    else
        echo -e "  ${RED}✗${NC} CMake missing (REQUIRED)"
    fi

    # Whisper framework
    if [ -d "$FRAMEWORK_PATH" ]; then
        echo -e "  ${GREEN}✓${NC} whisper.xcframework built"
    else
        echo -e "  ${RED}✗${NC} whisper.xcframework missing (REQUIRED)"
    fi

    # Code signing
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development\|Mac Developer"; then
        echo -e "  ${GREEN}✓${NC} Code signing configured"
    else
        echo -e "  ${YELLOW}!${NC} Code signing not configured (needed for distribution)"
    fi

    # Project
    if [ -f "${PROJECT_ROOT}/VoiceInk.xcodeproj/project.pbxproj" ]; then
        echo -e "  ${GREEN}✓${NC} Xcode project configured"
    else
        echo -e "  ${RED}✗${NC} Xcode project not found"
    fi

    # Show appropriate completion message and exit with correct code
    if [ "$SETUP_SUCCESS" = true ]; then
        show_success_message
        exit 0
    else
        echo ""
        if [ -n "$CRITICAL_FAILURES" ]; then
            echo -e "${RED}Critical Failures:${NC}"
            echo -e "$CRITICAL_FAILURES"
        fi
        if [ -n "$WARNINGS" ]; then
            echo -e "${YELLOW}Warnings:${NC}"
            echo -e "$WARNINGS"
        fi
        show_failure_message
        exit 1
    fi
}

# Handle script arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-env-check)
            SKIP_ENV_CHECK=true
            ;;
        --skip-build)
            SKIP_BUILD=true
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-env-check   Skip environment verification"
            echo "  --skip-build       Skip the test build at the end"
            echo "  --help             Show this help message"
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
