#!/bin/bash

# reset-data.sh - Reset VoiceInk user data for development
# This script safely removes VoiceInk user data to simulate a fresh install
#
# Usage:
#   ./reset-data.sh [options] <mode>
#
# Modes:
#   all            - Remove all data (transcriptions, models, preferences, caches)
#   data           - Remove Application Support data (transcriptions + models)
#   transcriptions - Remove only transcription data and recordings
#   models         - Remove only downloaded models
#   preferences    - Remove only UserDefaults/preferences
#
# Options:
#   --force        - Skip confirmation prompts
#   --dry-run      - Show what would be deleted without actually deleting
#   -h, --help     - Show this help message

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Flag defaults
FORCE=false
DRY_RUN=false
MODE=""

# Known bundle IDs (we'll check all of these)
BUNDLE_IDS=(
    "com.jshimko.VoiceInk"
    "com.prakashjoshipax.VoiceInk"
    "VoiceInk"
    "com.voiceink.VoiceInk"
)

# Add custom bundle ID from Fork.plist if it exists
if [ -f "$PROJECT_ROOT/Fork.plist" ]; then
    CUSTOM_BUNDLE_PREFIX=$(plutil -extract BundleIdentifierPrefix raw "$PROJECT_ROOT/Fork.plist" 2>/dev/null || echo "")
    if [ -n "$CUSTOM_BUNDLE_PREFIX" ]; then
        BUNDLE_IDS+=("${CUSTOM_BUNDLE_PREFIX}.VoiceInk")
    fi
fi

# Helper Functions
print_header() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            VoiceInk Data Reset Tool                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_help() {
    cat << EOF
${CYAN}VoiceInk Data Reset Tool${NC}

${BLUE}Usage:${NC}
  $(basename "$0") [options] <mode>

${BLUE}Modes:${NC}
  ${GREEN}all${NC}            - Remove all data (transcriptions, models, preferences, caches)
  ${GREEN}data${NC}           - Remove Application Support data (transcriptions + models)
  ${GREEN}transcriptions${NC} - Remove only transcription data and recordings
  ${GREEN}models${NC}         - Remove only downloaded models
  ${GREEN}preferences${NC}    - Remove only UserDefaults/preferences

${BLUE}Options:${NC}
  ${GREEN}--force${NC}        - Skip confirmation prompts (use with caution)
  ${GREEN}--dry-run${NC}      - Show what would be deleted without actually deleting
  ${GREEN}-h, --help${NC}     - Show this help message

${BLUE}Examples:${NC}
  $(basename "$0") data                    # Remove all app data with confirmation
  $(basename "$0") --dry-run all          # Preview what would be deleted
  $(basename "$0") --force transcriptions # Remove transcriptions without confirmation

${YELLOW}⚠️  Warning:${NC} This action cannot be undone. Always use --dry-run first!

EOF
}

get_dir_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | awk '{print $1}'
    else
        echo "0B"
    fi
}

check_path_exists() {
    local path="$1"
    [ -e "$path" ]
}

list_items_to_delete() {
    local mode="$1"
    local found_items=false
    local total_size=0

    echo -e "${BLUE}Items to be deleted:${NC}"
    echo ""

    case "$mode" in
        all|data|transcriptions|models)
            echo -e "${YELLOW}Application Support directories:${NC}"
            for bundle_id in "${BUNDLE_IDS[@]}"; do
                local app_support="$HOME/Library/Application Support/$bundle_id"
                if check_path_exists "$app_support"; then
                    local size=$(get_dir_size "$app_support")
                    echo -e "  ${GREEN}✓${NC} $app_support ($size)"
                    found_items=true

                    # Show subdirectories based on mode
                    case "$mode" in
                        transcriptions)
                            if [ -d "$app_support/Recordings" ]; then
                                echo -e "    ${CYAN}→${NC} Recordings/ ($(get_dir_size "$app_support/Recordings"))"
                            fi
                            if [ -f "$app_support/default.store" ]; then
                                echo -e "    ${CYAN}→${NC} default.store* (SwiftData)"
                            fi
                            ;;
                        models)
                            if [ -d "$app_support/WhisperModels" ]; then
                                echo -e "    ${CYAN}→${NC} WhisperModels/ ($(get_dir_size "$app_support/WhisperModels"))"
                            fi
                            if [ -d "$app_support/ParakeetModels" ]; then
                                echo -e "    ${CYAN}→${NC} ParakeetModels/ ($(get_dir_size "$app_support/ParakeetModels"))"
                            fi
                            ;;
                        data|all)
                            if [ -d "$app_support/Recordings" ]; then
                                echo -e "    ${CYAN}→${NC} Recordings/ ($(get_dir_size "$app_support/Recordings"))"
                            fi
                            if [ -d "$app_support/WhisperModels" ]; then
                                echo -e "    ${CYAN}→${NC} WhisperModels/ ($(get_dir_size "$app_support/WhisperModels"))"
                            fi
                            if [ -d "$app_support/ParakeetModels" ]; then
                                echo -e "    ${CYAN}→${NC} ParakeetModels/ ($(get_dir_size "$app_support/ParakeetModels"))"
                            fi
                            if [ -f "$app_support/default.store" ]; then
                                echo -e "    ${CYAN}→${NC} default.store* (SwiftData)"
                            fi
                            ;;
                    esac
                fi
            done
            echo ""
            ;;
    esac

    case "$mode" in
        all|preferences)
            echo -e "${YELLOW}Preferences files:${NC}"
            for bundle_id in "${BUNDLE_IDS[@]}"; do
                local pref_file="$HOME/Library/Preferences/$bundle_id.plist"
                if check_path_exists "$pref_file"; then
                    local size=$(ls -lh "$pref_file" 2>/dev/null | awk '{print $5}')
                    echo -e "  ${GREEN}✓${NC} $pref_file ($size)"
                    found_items=true
                fi
            done
            echo ""
            ;;
    esac

    case "$mode" in
        all)
            echo -e "${YELLOW}Cache directories:${NC}"
            for bundle_id in "${BUNDLE_IDS[@]}"; do
                local cache_dir="$HOME/Library/Caches/$bundle_id"
                if check_path_exists "$cache_dir"; then
                    local size=$(get_dir_size "$cache_dir")
                    echo -e "  ${GREEN}✓${NC} $cache_dir ($size)"
                    found_items=true
                fi
            done
            echo ""
            ;;
    esac

    if [ "$found_items" = false ]; then
        echo -e "  ${YELLOW}No VoiceInk data found${NC}"
        echo ""
        return 1
    fi

    return 0
}

delete_app_support_data() {
    local mode="$1"

    for bundle_id in "${BUNDLE_IDS[@]}"; do
        local app_support="$HOME/Library/Application Support/$bundle_id"

        if ! check_path_exists "$app_support"; then
            continue
        fi

        case "$mode" in
            all|data)
                if [ "$DRY_RUN" = false ]; then
                    echo -e "${YELLOW}Removing:${NC} $app_support"
                    rm -rf "$app_support"
                    echo -e "${GREEN}✓ Removed${NC}"
                fi
                ;;
            transcriptions)
                if [ "$DRY_RUN" = false ]; then
                    [ -d "$app_support/Recordings" ] && echo -e "${YELLOW}Removing:${NC} Recordings/" && rm -rf "$app_support/Recordings"
                    [ -f "$app_support/default.store" ] && echo -e "${YELLOW}Removing:${NC} default.store*" && rm -f "$app_support/default.store"*
                    echo -e "${GREEN}✓ Removed transcription data${NC}"
                fi
                ;;
            models)
                if [ "$DRY_RUN" = false ]; then
                    [ -d "$app_support/WhisperModels" ] && echo -e "${YELLOW}Removing:${NC} WhisperModels/" && rm -rf "$app_support/WhisperModels"
                    [ -d "$app_support/ParakeetModels" ] && echo -e "${YELLOW}Removing:${NC} ParakeetModels/" && rm -rf "$app_support/ParakeetModels"
                    echo -e "${GREEN}✓ Removed models${NC}"
                fi
                ;;
        esac
    done
}

delete_preferences() {
    for bundle_id in "${BUNDLE_IDS[@]}"; do
        local pref_file="$HOME/Library/Preferences/$bundle_id.plist"

        if check_path_exists "$pref_file"; then
            if [ "$DRY_RUN" = false ]; then
                echo -e "${YELLOW}Removing:${NC} $pref_file"
                rm -f "$pref_file"
                # Also clear from defaults cache
                defaults delete "$bundle_id" 2>/dev/null || true
                echo -e "${GREEN}✓ Removed${NC}"
            fi
        fi
    done
}

delete_caches() {
    for bundle_id in "${BUNDLE_IDS[@]}"; do
        local cache_dir="$HOME/Library/Caches/$bundle_id"

        if check_path_exists "$cache_dir"; then
            if [ "$DRY_RUN" = false ]; then
                echo -e "${YELLOW}Removing:${NC} $cache_dir"
                rm -rf "$cache_dir"
                echo -e "${GREEN}✓ Removed${NC}"
            fi
        fi
    done
}

perform_reset() {
    local mode="$1"

    echo ""
    echo -e "${BLUE}Performing reset (mode: $mode)...${NC}"
    echo ""

    case "$mode" in
        all)
            delete_app_support_data "all"
            delete_preferences
            delete_caches
            ;;
        data)
            delete_app_support_data "data"
            ;;
        transcriptions)
            delete_app_support_data "transcriptions"
            ;;
        models)
            delete_app_support_data "models"
            ;;
        preferences)
            delete_preferences
            ;;
    esac

    echo ""
    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}ℹ️  Dry run complete - no files were actually deleted${NC}"
    else
        echo -e "${GREEN}✅ Reset complete!${NC}"
        echo -e "${YELLOW}Next time you run VoiceInk, it will start fresh${NC}"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        all|data|transcriptions|models|preferences)
            MODE="$1"
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option or mode: $1${NC}"
            echo ""
            print_help
            exit 1
            ;;
    esac
done

# Validate mode is provided
if [ -z "$MODE" ]; then
    echo -e "${RED}Error: No mode specified${NC}"
    echo ""
    print_help
    exit 1
fi

# Main execution
print_header

if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}ℹ️  Running in DRY RUN mode - no files will be deleted${NC}"
    echo ""
fi

echo -e "${BLUE}Reset mode:${NC} ${GREEN}$MODE${NC}"
echo ""

# List items to delete
if ! list_items_to_delete "$MODE"; then
    echo -e "${GREEN}Nothing to delete - VoiceInk data already clean${NC}"
    exit 0
fi

# Confirmation prompt (unless --force is used)
if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}⚠️  WARNING: This action cannot be undone!${NC}"
    echo ""
    read -p "$(echo -e "${BLUE}Continue with deletion? (yes/no):${NC} ")" -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${CYAN}Cancelled - no files were deleted${NC}"
        exit 0
    fi
fi

# Perform the reset
perform_reset "$MODE"

echo ""
