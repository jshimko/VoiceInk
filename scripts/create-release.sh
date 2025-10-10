#!/bin/bash
# create-release.sh - Create a release build of VoiceInk
# This script handles creating production-ready releases including archiving and notarization

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
ARCHIVE_PATH="${PROJECT_ROOT}/archives"
EXPORT_PATH="${PROJECT_ROOT}/releases"

# Release configuration
CONFIGURATION="Release"
VERSION=""
BUILD_NUMBER=""
NOTARIZE=false
CREATE_DMG=false
SIGN_DMG=false
TEAM_ID=""
APPLE_ID=""
APP_PASSWORD=""

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

print_release() {
    echo -e "${MAGENTA}[RELEASE]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [options]

Create a release build of VoiceInk for distribution.

Options:
    --version <version>      Set version number (e.g., 1.2.0)
    --build <number>         Set build number (e.g., 42)
    --notarize              Submit for Apple notarization
    --dmg                   Create DMG installer
    --sign-dmg              Sign the DMG (requires --dmg)
    --team-id <id>          Developer Team ID for signing
    --apple-id <email>      Apple ID for notarization
    --password <pass>       App-specific password for notarization
    --help                  Show this help message

Examples:
    $0 --version 1.0.0 --build 1           # Basic release
    $0 --dmg --sign-dmg                    # Create signed DMG
    $0 --notarize --apple-id me@example.com  # With notarization

Environment Variables:
    VOICEINK_TEAM_ID        Developer Team ID
    VOICEINK_APPLE_ID       Apple ID for notarization
    VOICEINK_APP_PASSWORD   App-specific password

EOF
}

load_environment() {
    # Load from environment variables if not provided
    TEAM_ID="${TEAM_ID:-$VOICEINK_TEAM_ID}"
    APPLE_ID="${APPLE_ID:-$VOICEINK_APPLE_ID}"
    APP_PASSWORD="${APP_PASSWORD:-$VOICEINK_APP_PASSWORD}"

    # Load from local config if exists
    if [ -f "${PROJECT_ROOT}/.build-config" ]; then
        source "${PROJECT_ROOT}/.build-config"
    fi
}

check_prerequisites() {
    print_status "Checking release prerequisites..."

    # Check Xcode
    if ! command -v xcodebuild &> /dev/null; then
        print_error "xcodebuild not found"
        exit 1
    fi

    # Check project
    if [ ! -d "$PROJECT_FILE" ]; then
        print_error "Project file not found: $PROJECT_FILE"
        exit 1
    fi

    # Check code signing
    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        print_warning "No 'Developer ID Application' certificate found"
        echo "Required for distribution outside the App Store"
        echo "Visit https://developer.apple.com to create one"
    fi

    # Check notarization tools if needed
    if [ "$NOTARIZE" = true ]; then
        if ! command -v xcrun &> /dev/null; then
            print_error "xcrun not found (required for notarization)"
            exit 1
        fi

        if [ -z "$APPLE_ID" ] || [ -z "$APP_PASSWORD" ]; then
            print_error "Apple ID and app-specific password required for notarization"
            echo "Set --apple-id and --password or use environment variables"
            exit 1
        fi
    fi

    # Check DMG tools if needed
    if [ "$CREATE_DMG" = true ]; then
        if ! command -v hdiutil &> /dev/null; then
            print_error "hdiutil not found (required for DMG creation)"
            exit 1
        fi
    fi

    print_success "Prerequisites check passed"
}

update_version() {
    if [ -n "$VERSION" ] || [ -n "$BUILD_NUMBER" ]; then
        print_status "Updating version information..."

        # Get current values
        CURRENT_VERSION=$(xcodebuild -project "$PROJECT_FILE" -showBuildSettings 2>/dev/null | \
                         grep "MARKETING_VERSION" | head -1 | awk '{print $3}')
        CURRENT_BUILD=$(xcodebuild -project "$PROJECT_FILE" -showBuildSettings 2>/dev/null | \
                       grep "CURRENT_PROJECT_VERSION" | head -1 | awk '{print $3}')

        # Use current if not specified
        VERSION="${VERSION:-$CURRENT_VERSION}"
        BUILD_NUMBER="${BUILD_NUMBER:-$CURRENT_BUILD}"

        print_status "Version: $VERSION (Build $BUILD_NUMBER)"

        # Update Info.plist
        INFO_PLIST="${PROJECT_ROOT}/VoiceInk/Info.plist"
        if [ -f "$INFO_PLIST" ]; then
            # Update version
            /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
            # Update build
            /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
            print_success "Version updated in Info.plist"
        fi
    fi
}

run_tests() {
    print_status "Running tests before release..."

    read -p "Run tests before building release? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if "${SCRIPT_DIR}/run-tests.sh" --type all; then
            print_success "All tests passed"
        else
            print_error "Tests failed"
            read -p "Continue with release anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

clean_build() {
    print_status "Cleaning previous builds..."

    # Clean build folder
    "${SCRIPT_DIR}/clean-build.sh" --level normal

    # Create directories
    mkdir -p "$ARCHIVE_PATH"
    mkdir -p "$EXPORT_PATH"

    print_success "Build environment cleaned"
}

build_archive() {
    print_release "Building release archive..."

    # Archive name with timestamp
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ARCHIVE_NAME="VoiceInk_${VERSION}_${BUILD_NUMBER}_${TIMESTAMP}"
    FULL_ARCHIVE_PATH="${ARCHIVE_PATH}/${ARCHIVE_NAME}.xcarchive"

    # Build archive
    xcodebuild archive \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$FULL_ARCHIVE_PATH" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        2>&1 | while IFS= read -r line; do
            # Filter output
            if echo "$line" | grep -E "Archive Succeeded|Building|Archiving" > /dev/null; then
                echo "$line"
            fi
        done

    if [ -d "$FULL_ARCHIVE_PATH" ]; then
        print_success "Archive created: $FULL_ARCHIVE_PATH"
    else
        print_error "Archive creation failed"
        exit 1
    fi

    echo "$FULL_ARCHIVE_PATH"
}

export_app() {
    local archive_path="$1"

    print_release "Exporting application..."

    # Create export options plist
    EXPORT_OPTIONS="${PROJECT_ROOT}/ExportOptions.plist"

    cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>provisioningProfiles</key>
    <dict/>
</dict>
</plist>
EOF

    # Export archive
    xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        2>&1 | tail -20

    # Clean up
    rm -f "$EXPORT_OPTIONS"

    APP_PATH="${EXPORT_PATH}/VoiceInk.app"
    if [ -d "$APP_PATH" ]; then
        print_success "App exported to: $APP_PATH"
    else
        print_error "Export failed"
        exit 1
    fi

    echo "$APP_PATH"
}

notarize_app() {
    local app_path="$1"

    if [ "$NOTARIZE" = false ]; then
        return
    fi

    print_release "Submitting app for notarization..."

    # Create ZIP for notarization
    ZIP_PATH="${EXPORT_PATH}/VoiceInk_${VERSION}.zip"
    print_status "Creating ZIP for notarization..."
    ditto -c -k --keepParent "$app_path" "$ZIP_PATH"

    # Submit for notarization
    print_status "Submitting to Apple..."

    NOTARIZE_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait 2>&1)

    echo "$NOTARIZE_OUTPUT"

    # Check if successful
    if echo "$NOTARIZE_OUTPUT" | grep -q "Successfully uploaded"; then
        REQUEST_UUID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | awk '{print $2}')
        print_success "Notarization submitted: $REQUEST_UUID"

        # Wait for notarization
        print_status "Waiting for notarization to complete..."

        xcrun notarytool wait "$REQUEST_UUID" \
            --apple-id "$APPLE_ID" \
            --password "$APP_PASSWORD" \
            --team-id "$TEAM_ID"

        # Staple the notarization
        print_status "Stapling notarization..."
        xcrun stapler staple "$app_path"

        print_success "App notarized and stapled"
    else
        print_error "Notarization failed"
        echo "Check the output above for details"
        exit 1
    fi

    # Clean up ZIP
    rm -f "$ZIP_PATH"
}

create_dmg() {
    local app_path="$1"

    if [ "$CREATE_DMG" = false ]; then
        return
    fi

    print_release "Creating DMG installer..."

    DMG_NAME="VoiceInk_${VERSION}.dmg"
    DMG_PATH="${EXPORT_PATH}/${DMG_NAME}"
    TEMP_DMG="${EXPORT_PATH}/temp.dmg"
    VOLUME_NAME="VoiceInk ${VERSION}"

    # Create temporary directory for DMG contents
    DMG_CONTENTS="${EXPORT_PATH}/dmg_contents"
    rm -rf "$DMG_CONTENTS"
    mkdir -p "$DMG_CONTENTS"

    # Copy app
    cp -R "$app_path" "$DMG_CONTENTS/"

    # Create Applications symlink
    ln -s /Applications "$DMG_CONTENTS/Applications"

    # Create README if exists
    if [ -f "${PROJECT_ROOT}/README.md" ]; then
        cp "${PROJECT_ROOT}/README.md" "$DMG_CONTENTS/"
    fi

    # Create DMG
    print_status "Building DMG..."
    hdiutil create -volname "$VOLUME_NAME" \
        -srcfolder "$DMG_CONTENTS" \
        -ov -format UDZO \
        "$TEMP_DMG"

    # Convert to compressed DMG
    hdiutil convert "$TEMP_DMG" \
        -format UDZO \
        -o "$DMG_PATH"

    # Clean up
    rm -f "$TEMP_DMG"
    rm -rf "$DMG_CONTENTS"

    print_success "DMG created: $DMG_PATH"

    # Sign DMG if requested
    if [ "$SIGN_DMG" = true ]; then
        print_status "Signing DMG..."

        codesign --force --sign "Developer ID Application" \
            --timestamp \
            "$DMG_PATH"

        print_success "DMG signed"

        # Notarize DMG if notarization is enabled
        if [ "$NOTARIZE" = true ]; then
            notarize_dmg "$DMG_PATH"
        fi
    fi

    # Show DMG info
    DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
    echo "  Size: $DMG_SIZE"
}

notarize_dmg() {
    local dmg_path="$1"

    print_status "Notarizing DMG..."

    NOTARIZE_OUTPUT=$(xcrun notarytool submit "$dmg_path" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait 2>&1)

    if echo "$NOTARIZE_OUTPUT" | grep -q "Successfully"; then
        # Staple notarization
        xcrun stapler staple "$dmg_path"
        print_success "DMG notarized and stapled"
    else
        print_warning "DMG notarization failed"
    fi
}

generate_release_notes() {
    print_status "Generating release notes..."

    RELEASE_NOTES="${EXPORT_PATH}/RELEASE_NOTES_${VERSION}.md"

    cat > "$RELEASE_NOTES" << EOF
# VoiceInk Release ${VERSION}

**Version:** ${VERSION}
**Build:** ${BUILD_NUMBER}
**Date:** $(date +"%Y-%m-%d")

## Release Information

- **Configuration:** ${CONFIGURATION}
- **Architecture:** Universal (arm64, x86_64)
- **macOS Requirement:** 14.0+
- **Notarized:** $([ "$NOTARIZE" = true ] && echo "Yes" || echo "No")

## Files

EOF

    # List release files
    ls -la "$EXPORT_PATH" | grep -v "^total" | grep -v "^d" | awk '{print "- " $9 " (" $5 " bytes)"}' >> "$RELEASE_NOTES"

    cat >> "$RELEASE_NOTES" << EOF

## Installation

1. Download VoiceInk_${VERSION}.dmg
2. Open the DMG file
3. Drag VoiceInk to Applications folder
4. Launch VoiceInk from Applications

## Verification

To verify the app signature:
\`\`\`bash
codesign -vvv --deep --strict /Applications/VoiceInk.app
\`\`\`

## Changes

See CHANGELOG.md for detailed changes in this release.

---
Generated on $(date)
EOF

    print_success "Release notes created: $RELEASE_NOTES"
}

release_summary() {
    echo ""
    echo "================================================"
    echo -e "${GREEN}  Release Build Complete!${NC}"
    echo "================================================"
    echo ""
    echo "Version: ${VERSION} (Build ${BUILD_NUMBER})"
    echo "Configuration: ${CONFIGURATION}"
    echo ""
    echo "Release artifacts in: ${EXPORT_PATH}/"

    # List created files
    echo ""
    echo "Created files:"
    ls -lah "$EXPORT_PATH" | grep -v "^total" | grep -v "^d" | while IFS= read -r line; do
        echo "  $line"
    done

    echo ""
    echo "Next steps:"

    if [ "$NOTARIZE" = false ]; then
        echo "  1. Consider notarizing the app for distribution"
        echo "     Run with --notarize option"
    fi

    if [ "$CREATE_DMG" = false ]; then
        echo "  2. Create a DMG for easier distribution"
        echo "     Run with --dmg option"
    fi

    echo "  3. Upload to your distribution channel"
    echo "  4. Update release notes and changelog"
    echo "  5. Tag the release in Git:"
    echo "     git tag -a v${VERSION} -m \"Release ${VERSION}\""
    echo "     git push origin v${VERSION}"
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --dmg)
            CREATE_DMG=true
            shift
            ;;
        --sign-dmg)
            SIGN_DMG=true
            shift
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --password)
            APP_PASSWORD="$2"
            shift 2
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
    echo -e "${MAGENTA}  Creating VoiceInk Release Build${NC}"
    echo "================================================"
    echo ""

    # Load environment
    load_environment

    # Check prerequisites
    check_prerequisites

    # Update version if specified
    update_version

    # Get current version if not specified
    if [ -z "$VERSION" ]; then
        VERSION=$(xcodebuild -project "$PROJECT_FILE" -showBuildSettings 2>/dev/null | \
                 grep "MARKETING_VERSION" | head -1 | awk '{print $3}')
        BUILD_NUMBER=$(xcodebuild -project "$PROJECT_FILE" -showBuildSettings 2>/dev/null | \
                      grep "CURRENT_PROJECT_VERSION" | head -1 | awk '{print $3}')
    fi

    print_status "Building release version ${VERSION} (${BUILD_NUMBER})"
    echo ""

    # Run tests
    run_tests

    # Clean previous builds
    clean_build

    # Build archive
    ARCHIVE_PATH=$(build_archive)

    # Export app
    APP_PATH=$(export_app "$ARCHIVE_PATH")

    # Notarize if requested
    notarize_app "$APP_PATH"

    # Create DMG if requested
    create_dmg "$APP_PATH"

    # Generate release notes
    generate_release_notes

    # Show summary
    release_summary

    exit 0
}

# Run main function
main
