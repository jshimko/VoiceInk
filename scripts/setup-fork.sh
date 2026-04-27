#!/bin/bash

# VoiceInk Fork Setup Script
# This script helps configure your fork with your own organization details

set -e

echo "================================================"
echo "          VoiceInk Fork Setup Script            "
echo "================================================"
echo

# Check if we're in the right directory
if [ ! -f "VoiceInk.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Please run this script from the VoiceInk project root directory"
    exit 1
fi

# Check if Fork.plist.template exists
if [ ! -f "Fork.plist.template" ]; then
    echo "❌ Error: Fork.plist.template not found"
    exit 1
fi

# Function to prompt for input with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    read -p "$prompt [$default]: " input_value
    if [ -z "$input_value" ]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$input_value'"
    fi
}

echo "This script will help you configure your VoiceInk fork."
echo "Press Enter to accept default values shown in brackets."
echo

# Prompt for configuration values
prompt_with_default "Enter your bundle identifier prefix (e.g., com.yourdomain)" "com.voiceink" BUNDLE_ID_PREFIX
prompt_with_default "Enter your support email" "support@voiceink.app" SUPPORT_EMAIL
prompt_with_default "Enter your app name" "VoiceInk" APP_NAME

echo
echo "Optional URLs (press Enter to skip):"
prompt_with_default "Website URL" "" WEBSITE_URL
prompt_with_default "Documentation URL" "" DOCS_URL
prompt_with_default "GitHub/GitLab releases URL" "" CHANGELOG_URL
prompt_with_default "Discord/Community URL" "" DISCORD_URL
prompt_with_default "Purchase/upgrade URL" "" PURCHASE_URL
prompt_with_default "Donation/tip jar URL" "" DONATION_URL

echo
echo "Feature Configuration:"

# Ask about features
read -p "Enable purchase/licensing features? (y/N): " ENABLE_PURCHASE
SHOW_PURCHASE=$([[ "$ENABLE_PURCHASE" =~ ^[Yy]$ ]] && echo "true" || echo "false")

read -p "Show community links? (y/N): " ENABLE_COMMUNITY
SHOW_COMMUNITY=$([[ "$ENABLE_COMMUNITY" =~ ^[Yy]$ ]] && echo "true" || echo "false")

read -p "Show donation/tip jar? (y/N): " ENABLE_DONATION
SHOW_DONATION=$([[ "$ENABLE_DONATION" =~ ^[Yy]$ ]] && echo "true" || echo "false")

# Create Fork.plist from template
echo
echo "Creating Fork.plist..."

cat > Fork.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>BundleIdentifierPrefix</key>
	<string>$BUNDLE_ID_PREFIX</string>
	<key>SupportEmail</key>
	<string>$SUPPORT_EMAIL</string>
	<key>AppName</key>
	<string>$APP_NAME</string>
EOF

# Add optional URLs if provided
[ -n "$WEBSITE_URL" ] && echo "	<key>WebsiteURL</key>
	<string>$WEBSITE_URL</string>" >> Fork.plist

[ -n "$DOCS_URL" ] && echo "	<key>DocsURL</key>
	<string>$DOCS_URL</string>" >> Fork.plist

[ -n "$DISCORD_URL" ] && echo "	<key>DiscordURL</key>
	<string>$DISCORD_URL</string>" >> Fork.plist

[ -n "$PURCHASE_URL" ] && echo "	<key>PurchaseURL</key>
	<string>$PURCHASE_URL</string>" >> Fork.plist

[ -n "$DONATION_URL" ] && echo "	<key>DonationURL</key>
	<string>$DONATION_URL</string>" >> Fork.plist

[ -n "$CHANGELOG_URL" ] && echo "	<key>ChangelogURL</key>
	<string>$CHANGELOG_URL</string>" >> Fork.plist

# Add feature flags
cat >> Fork.plist << EOF
	<key>ShowPurchaseOptions</key>
	<$SHOW_PURCHASE/>
	<key>ShowCommunityLinks</key>
	<$SHOW_COMMUNITY/>
	<key>ShowDonationLink</key>
	<$SHOW_DONATION/>
	<key>EnableLicenseValidation</key>
	<false/>
	<key>EnableAutoUpdates</key>
	<false/>
	<key>LoggerSubsystem</key>
	<string>$BUNDLE_ID_PREFIX.voiceink</string>
</dict>
</plist>
EOF

echo "✅ Fork.plist created successfully!"

# Update project bundle identifier
echo
echo "Updating project configuration..."

# Update the main bundle identifier in the project file
sed -i '' "s/com\.jshimko\.VoiceInk/$BUNDLE_ID_PREFIX.VoiceInk/g" VoiceInk.xcodeproj/project.pbxproj

# Update test bundle identifiers
sed -i '' "s/com\.jshimko\.VoiceInkTests/$BUNDLE_ID_PREFIX.VoiceInkTests/g" VoiceInk.xcodeproj/project.pbxproj
sed -i '' "s/com\.jshimko\.VoiceInkUITests/$BUNDLE_ID_PREFIX.VoiceInkUITests/g" VoiceInk.xcodeproj/project.pbxproj

echo "✅ Project bundle identifiers updated!"

# Add Fork.plist to Xcode project if needed
echo
echo "================================================"
echo "                Setup Complete!                 "
echo "================================================"
echo
echo "Next steps:"
echo "1. Open VoiceInk.xcodeproj in Xcode"
echo "2. Add Fork.plist to the project (drag it into the VoiceInk folder)"
echo "3. Ensure Fork.plist is added to the app target"
echo "4. Build and run your configured fork!"
echo
echo "Your configuration:"
echo "  Bundle ID: $BUNDLE_ID_PREFIX.VoiceInk"
echo "  Support Email: $SUPPORT_EMAIL"
echo "  App Name: $APP_NAME"
echo
echo "Fork.plist has been created and added to .gitignore"
echo "Your personal configuration will not be committed to git."
echo