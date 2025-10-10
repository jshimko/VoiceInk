#!/bin/bash
# install.sh - Install VoiceInk to /Applications
# This script installs VoiceInk from the release build to /Applications

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
APP_NAME="VoiceInk.app"
SOURCE_APP="${PROJECT_ROOT}/build/Build/Products/Release/${APP_NAME}"
TARGET_APP="/Applications/${APP_NAME}"

# Default values
SKIP_BUILD=false
FORCE_INSTALL=false
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

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

print_header() {
    echo ""
    echo "================================================"
    echo -e "${MAGENTA}  Installing VoiceInk${NC}"
    echo "================================================"
    echo ""
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install VoiceInk to /Applications directory

Options:
    --skip-build        Install existing release build without rebuilding
    --force            Skip confirmation prompt for replacing existing installation
    --verbose          Show detailed output
    -h, --help         Show this help message

Examples:
    $0                      # Build and install VoiceInk
    $0 --skip-build         # Install existing release build
    $0 --force             # Install without confirmation prompt

EOF
    exit 0
}

verify_build() {
    if [ ! -d "$SOURCE_APP" ]; then
        print_error "Release build not found at $SOURCE_APP"
        if [ "$SKIP_BUILD" = true ]; then
            print_warning "Run 'task build:release' first to build the app"
        else
            print_warning "The build may have failed. Check the output above."
        fi
        exit 1
    fi

    if [ "$VERBOSE" = true ]; then
        print_info "Source app: $SOURCE_APP"
        print_info "Target location: $TARGET_APP"
    fi
}

check_existing_installation() {
    if [ -d "$TARGET_APP" ]; then
        echo ""
        print_warning "VoiceInk.app already exists in /Applications"

        # Show current version
        print_info "Current version:"
        CURRENT_VERSION=$(defaults read "$TARGET_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "Unknown")
        CURRENT_BUILD=$(defaults read "$TARGET_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "Unknown")
        echo "    Version: $CURRENT_VERSION (Build $CURRENT_BUILD)"

        # Show new version
        print_info "New version:"
        NEW_VERSION=$(defaults read "$SOURCE_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "Unknown")
        NEW_BUILD=$(defaults read "$SOURCE_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "Unknown")
        echo "    Version: $NEW_VERSION (Build $NEW_BUILD)"

        if [ "$FORCE_INSTALL" = false ]; then
            echo ""
            read -p "Replace existing installation? (y/N) " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Installation cancelled"
                exit 0
            fi
        else
            print_info "Force install enabled, replacing existing installation"
        fi

        # Remove old version
        print_status "Removing old version..."
        rm -rf "$TARGET_APP"
        print_success "Old version removed"
    fi
}

install_app() {
    print_status "Installing VoiceInk to /Applications..."

    # Copy new version
    cp -R "$SOURCE_APP" "$TARGET_APP"

    # Verify installation
    if [ -d "$TARGET_APP" ]; then
        print_success "VoiceInk successfully installed to /Applications"

        # Show installed version info
        VERSION=$(defaults read "$TARGET_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 'Unknown')
        BUILD=$(defaults read "$TARGET_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo 'Unknown')

        echo ""
        print_info "Installed version: $VERSION (Build $BUILD)"

        # Show app size
        APP_SIZE=$(du -sh "$TARGET_APP" | awk '{print $1}')
        print_info "Application size: $APP_SIZE"

        echo ""
        echo -e "${BLUE}You can now launch VoiceInk from:${NC}"
        echo "  • Applications folder"
        echo "  • Spotlight (⌘ Space)"
        echo "  • Terminal: open '$TARGET_APP'"
        echo ""
    else
        print_error "Installation failed"
        exit 1
    fi
}

build_release() {
    if [ "$SKIP_BUILD" = false ]; then
        print_status "Building release version..."

        BUILD_SCRIPT="${SCRIPT_DIR}/build-app.sh"
        if [ ! -f "$BUILD_SCRIPT" ]; then
            print_error "Build script not found: $BUILD_SCRIPT"
            exit 1
        fi

        # Run the build script with release configuration
        if ! "$BUILD_SCRIPT" --configuration Release; then
            print_error "Build failed"
            exit 1
        fi

        print_success "Release build completed"
    fi
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Main execution
print_header

# Build if needed
build_release

# Verify the build exists
verify_build

# Check for existing installation
check_existing_installation

# Install the app
install_app

print_success "Installation complete!"