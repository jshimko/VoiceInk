#!/bin/bash
# setup-environment.sh - Check and setup development environment for VoiceInk
# This script verifies all prerequisites are met and helps install missing components

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MIN_MACOS_VERSION="14.0"
MIN_XCODE_VERSION="15.0"
MIN_CMAKE_VERSION="3.20"
REQUIRED_DISK_SPACE_GB=5

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

version_ge() {
    # Compare version strings (returns 0 if $1 >= $2)
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

check_disk_space() {
    print_status "Checking available disk space..."

    # Get available space in GB
    AVAILABLE_GB=$(df -H / | awk 'NR==2 {print $4}' | sed 's/G//')

    if (( $(echo "$AVAILABLE_GB >= $REQUIRED_DISK_SPACE_GB" | bc -l) )); then
        print_success "Disk space: ${AVAILABLE_GB}GB available (minimum: ${REQUIRED_DISK_SPACE_GB}GB)"
        return 0
    else
        print_error "Insufficient disk space: ${AVAILABLE_GB}GB available (minimum: ${REQUIRED_DISK_SPACE_GB}GB)"
        return 1
    fi
}

check_macos_version() {
    print_status "Checking macOS version..."

    # Get macOS version
    MACOS_VERSION=$(sw_vers -productVersion)
    MACOS_MAJOR=$(echo $MACOS_VERSION | cut -d. -f1)
    MACOS_MINOR=$(echo $MACOS_VERSION | cut -d. -f2)

    if version_ge "$MACOS_VERSION" "$MIN_MACOS_VERSION"; then
        print_success "macOS $MACOS_VERSION (minimum: $MIN_MACOS_VERSION)"
        return 0
    else
        print_error "macOS $MACOS_VERSION is too old (minimum: $MIN_MACOS_VERSION)"
        echo "Please update to macOS Sonoma (14.0) or later"
        return 1
    fi
}

check_xcode() {
    print_status "Checking Xcode installation..."

    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode is not installed"
        echo "Please install Xcode from the Mac App Store:"
        echo "  https://apps.apple.com/us/app/xcode/id497799835"
        return 1
    fi

    # Get Xcode version
    XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -n1 | awk '{print $2}')

    if version_ge "$XCODE_VERSION" "$MIN_XCODE_VERSION"; then
        print_success "Xcode $XCODE_VERSION (minimum: $MIN_XCODE_VERSION)"
    else
        print_warning "Xcode $XCODE_VERSION may be too old (recommended: $MIN_XCODE_VERSION+)"
    fi

    # Check Xcode license
    if ! xcodebuild -checkFirstLaunchStatus &> /dev/null; then
        print_warning "Xcode license needs to be accepted"
        echo "Run: sudo xcodebuild -license accept"
    fi

    return 0
}

check_command_line_tools() {
    print_status "Checking Command Line Tools..."

    if ! xcode-select -p &> /dev/null; then
        print_error "Xcode Command Line Tools are not installed"
        echo "Installing Command Line Tools..."
        xcode-select --install
        echo "Please complete the installation and run this script again"
        return 1
    fi

    CLT_PATH=$(xcode-select -p)
    print_success "Command Line Tools installed at: $CLT_PATH"
    return 0
}

check_git() {
    print_status "Checking Git installation..."

    if ! command -v git &> /dev/null; then
        print_error "Git is not installed"
        echo "Git should be installed with Xcode Command Line Tools"
        echo "Try: xcode-select --install"
        return 1
    fi

    GIT_VERSION=$(git --version | awk '{print $3}')
    print_success "Git $GIT_VERSION installed"
    return 0
}

check_cmake() {
    print_status "Checking CMake installation..."

    if ! command -v cmake &> /dev/null; then
        print_warning "CMake is not installed (REQUIRED)"
        echo "CMake is required for building whisper.cpp from source"

        # Check if Homebrew is available for automatic installation
        if command -v brew &> /dev/null; then
            echo ""
            printf "Would you like to install CMake using Homebrew? (Y/n): "
            read -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                print_status "Installing CMake via Homebrew..."
                if brew install cmake; then
                    print_success "CMake installed successfully!"
                    # Verify installation
                    CMAKE_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
                    print_success "CMake $CMAKE_VERSION installed"
                    return 0
                else
                    print_error "Failed to install CMake via Homebrew"
                    echo "Please try installing manually from: https://cmake.org/download/"
                    return 1
                fi
            else
                print_error "CMake installation declined"
                echo "Please install CMake manually:"
                echo "  brew install cmake"
                echo "  or download from: https://cmake.org/download/"
                return 1
            fi
        else
            # Homebrew not available
            echo ""
            echo "Homebrew is not installed. To install CMake:"
            echo "  1. Install Homebrew first:"
            echo '     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
            echo "  2. Then install CMake:"
            echo "     brew install cmake"
            echo ""
            echo "Or download CMake from: https://cmake.org/download/"
            return 1
        fi
    fi

    CMAKE_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
    if version_ge "$CMAKE_VERSION" "$MIN_CMAKE_VERSION"; then
        print_success "CMake $CMAKE_VERSION (minimum: $MIN_CMAKE_VERSION)"
        return 0
    else
        print_warning "CMake $CMAKE_VERSION is too old (minimum required: $MIN_CMAKE_VERSION)"

        if command -v brew &> /dev/null; then
            echo ""
            printf "Would you like to upgrade CMake using Homebrew? (Y/n): "
            read -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                print_status "Upgrading CMake via Homebrew..."
                if brew upgrade cmake; then
                    CMAKE_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
                    print_success "CMake upgraded to $CMAKE_VERSION"
                    return 0
                else
                    print_error "Failed to upgrade CMake"
                    return 1
                fi
            else
                print_error "CMake upgrade declined"
                echo "Please upgrade CMake manually to version $MIN_CMAKE_VERSION or newer"
                return 1
            fi
        else
            echo "Please update CMake to version $MIN_CMAKE_VERSION or newer"
            echo "Download from: https://cmake.org/download/"
            return 1
        fi
    fi
}

check_homebrew() {
    print_status "Checking Homebrew installation..."

    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew is not installed (optional)"
        echo "Homebrew can help install additional tools"
        echo "Install with:"
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        return 1
    fi

    BREW_VERSION=$(brew --version | head -n1 | awk '{print $2}')
    print_success "Homebrew $BREW_VERSION installed"

    # Check if Homebrew needs updating
    if [ -z "${SKIP_BREW_UPDATE:-}" ]; then
        print_status "Checking for Homebrew updates..."
        brew update &> /dev/null || true
    fi

    return 0
}

check_xcpretty() {
    print_status "Checking xcpretty installation..."

    if ! command -v xcpretty &> /dev/null; then
        print_warning "xcpretty is not installed (optional)"
        echo "xcpretty provides better formatting for xcodebuild output"
        echo "Install with: gem install xcpretty"
        return 1
    fi

    print_success "xcpretty installed"
    return 0
}

check_code_signing() {
    print_status "Checking code signing configuration..."

    # Check if user has any development certificates
    if security find-identity -v -p codesigning | grep -q "Apple Development\|iPhone Developer\|Mac Developer\|Apple Distribution"; then
        print_success "Code signing certificates found"

        # List available identities
        echo "Available signing identities:"
        security find-identity -v -p codesigning | grep -E "Apple Development|iPhone Developer|Mac Developer|Apple Distribution" | head -5
    else
        print_warning "No code signing certificates found"
        echo "For local development, you can use automatic signing with a free Apple ID"
        echo "For distribution, you'll need an Apple Developer Program membership ($99/year)"
    fi

    return 0
}

install_missing_tools() {
    print_status "Checking for tool installation options..."

    if command -v brew &> /dev/null; then
        echo ""
        echo "You can install missing tools using Homebrew:"

        if ! command -v cmake &> /dev/null; then
            echo "  brew install cmake      # For building whisper.cpp"
        fi

        if ! command -v xcpretty &> /dev/null; then
            echo "  gem install xcpretty    # For better build output"
        fi
    fi
}

check_whisper_cpp() {
    print_status "Checking for whisper.cpp..."

    WHISPER_DIR="../whisper.cpp"

    if [ -d "$WHISPER_DIR" ]; then
        print_success "whisper.cpp found at $WHISPER_DIR"

        # Check if already built
        if [ -d "$WHISPER_DIR/build-apple/whisper.xcframework" ]; then
            print_success "whisper.xcframework already built"
        else
            print_warning "whisper.xcframework not built yet"
            echo "Run: ./build-whisper.sh to build the framework"
        fi
    else
        print_warning "whisper.cpp not found at $WHISPER_DIR"
        echo "Run: ./setup-project.sh to clone and build whisper.cpp"
    fi

    return 0
}

# Main execution
main() {
    echo "================================================"
    echo "  VoiceInk Development Environment Check"
    echo "================================================"
    echo ""

    # Track if all requirements are met
    ALL_REQUIREMENTS_MET=true

    # Run required checks
    check_disk_space || ALL_REQUIREMENTS_MET=false
    check_macos_version || ALL_REQUIREMENTS_MET=false
    check_xcode || ALL_REQUIREMENTS_MET=false
    check_command_line_tools || ALL_REQUIREMENTS_MET=false
    check_git || ALL_REQUIREMENTS_MET=false
    check_cmake || ALL_REQUIREMENTS_MET=false

    echo ""
    echo "Optional components:"
    check_homebrew || true
    check_xcpretty || true

    echo ""
    check_code_signing

    echo ""
    check_whisper_cpp

    # Summary
    echo ""
    echo "================================================"
    echo "  Summary"
    echo "================================================"

    if [ "$ALL_REQUIREMENTS_MET" = true ]; then
        print_success "All required components are installed!"
        echo ""
        echo "Next steps:"
        echo "1. Run ./setup-project.sh to set up the project"
        echo "2. Run ./build-app.sh to build VoiceInk"
        echo "3. Or open VoiceInk.xcodeproj in Xcode"

        install_missing_tools

        exit 0
    else
        print_error "Some required components are missing"
        echo ""
        echo "Please install the missing components and run this script again"

        install_missing_tools

        exit 1
    fi
}

# Run main function
main "$@"
