# VoiceInk Fork Configuration Guide

> **Complete guide for creating and customizing your own VoiceInk fork**

## Table of Contents

- [Quick Start](#quick-start)
- [Understanding the Fork](#understanding-the-fork)
- [Configuration System](#configuration-system)
- [Customization Options](#customization-options)
- [Building and Distribution](#building-and-distribution)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## Quick Start

### 1. Fork and Clone

```bash
# Fork the repository on GitHub first, then:
git clone https://github.com/YOUR_USERNAME/VoiceInk.git
cd VoiceInk
```

### 2. Run Setup Script

```bash
./scripts/setup-fork.sh
```

The interactive script will prompt you for:

- **Bundle Identifier Prefix** (e.g., `com.yourdomain`)
- **Support Email**
- **App Name** (optional, defaults to "VoiceInk")
- **Optional URLs** (website, docs, community, etc.)
- **Feature Toggles** (purchase options, community links, donations)

### 3. Add Configuration to Xcode

1. Open `VoiceInk.xcodeproj` in Xcode
2. Drag `Fork.plist` into the project navigator
3. Ensure it's added to the VoiceInk target
4. Build and run!

## Understanding the Fork

### What's Different from Original VoiceInk?

This fork provides a **privacy-focused, fully configurable** version of VoiceInk:

| Feature                | Original               | This Fork       |
| ---------------------- | ---------------------- | --------------- |
| Auto-updates (Sparkle) | ✅ Enabled             | ❌ Disabled     |
| License validation     | ✅ Required            | ❌ Removed      |
| Analytics/Telemetry    | ✅ Present             | ❌ Removed      |
| Announcements          | ✅ Fetches from server | ❌ Removed      |
| External URLs          | 🔒 Hardcoded           | ⚙️ Configurable |
| Bundle IDs             | 🔒 Hardcoded           | ⚙️ Configurable |

### Privacy Guarantees

- **No telemetry** - No usage data is collected
- **No phone-home** - No automatic server communication
- **Offline by default** - Only connects for features you explicitly configure
- **Transparent networking** - All network calls are for user-initiated features

## Configuration System

### How It Works

```
Fork.plist → AppConfig.swift → UI Components
```

1. **Fork.plist**: Your configuration file (gitignored)
2. **Fork.plist.template**: Template for others (tracked in git)
3. **AppConfig.swift**: Singleton that reads configuration
4. **UI Components**: Conditionally render based on config

### Manual Configuration

If you prefer manual setup over the script:

1. Copy the template:

   ```bash
   cp Fork.plist.template Fork.plist
   ```

2. Edit `Fork.plist` with your values:

   ```xml
   <key>BundleIdentifierPrefix</key>
   <string>com.yourdomain</string>

   <key>SupportEmail</key>
   <string>support@yourdomain.com</string>
   ```

3. Add to Xcode project (drag into navigator)

## Customization Options

### Required Settings

These must be configured for the app to function:

| Key                      | Description                          | Example              |
| ------------------------ | ------------------------------------ | -------------------- |
| `BundleIdentifierPrefix` | Your organization's bundle ID prefix | `com.mycompany`      |
| `SupportEmail`           | Email for support requests           | `help@mycompany.com` |

### Optional Branding

Customize the app's identity:

| Key               | Description                    | Default             |
| ----------------- | ------------------------------ | ------------------- |
| `AppName`         | Display name in UI             | `VoiceInk`          |
| `LoggerSubsystem` | Console.app logging identifier | `{prefix}.voiceink` |

### Optional URLs

Leave blank to hide features:

| Key                | Description           | UI Effect              |
| ------------------ | --------------------- | ---------------------- |
| `WebsiteURL`       | Your website          | Shows website link     |
| `DocsURL`          | Documentation site    | Shows docs link        |
| `ChangelogURL`     | GitHub releases page  | Shows changelog button |
| `DiscordURL`       | Community URL         | Shows community button |
| `PurchaseURL`      | Upgrade/purchase page | Shows purchase flow    |
| `DonationURL`      | Tip jar/donations     | Shows donation button  |
| `LicensePortalURL` | License management    | Shows portal link      |

### Feature Flags

Control which features are visible:

| Key                       | Type | Description                                        |
| ------------------------- | ---- | -------------------------------------------------- |
| `ShowPurchaseOptions`     | Bool | Enable purchase/pro UI                             |
| `ShowCommunityLinks`      | Bool | Show community features                            |
| `ShowDonationLink`        | Bool | Show tip jar                                       |
| `EnableLicenseValidation` | Bool | Enable license checks (always false in fork)       |
| `EnableAutoUpdates`       | Bool | Enable Sparkle updates (requires additional setup) |

## Building and Distribution

### Code Signing

1. Open Xcode project settings
2. Select your team in "Signing & Capabilities"
3. Xcode will manage provisioning profiles automatically

### Creating Releases

#### Option 1: Direct Distribution

```bash
# Build release version
xcodebuild -project VoiceInk.xcodeproj \
           -scheme VoiceInk \
           -configuration Release \
           archive

# Export for distribution
# Then notarize with Apple
```

#### Option 2: GitHub Releases

1. Tag your version: `git tag v1.0.0`
2. Push tags: `git push --tags`
3. Create release on GitHub
4. Upload built `.dmg` file

### App Notarization

For distribution outside the App Store:

```bash
# Notarize your app
xcrun notarytool submit VoiceInk.dmg \
                 --apple-id "your@email.com" \
                 --team-id "TEAMID" \
                 --wait
```

## Maintenance

### Syncing with Upstream

Keep your fork updated with the original:

```bash
# Add upstream remote (once)
git remote add upstream https://github.com/Beingpax/VoiceInk.git

# Sync changes
git fetch upstream
git merge upstream/main

# Re-run setup script if needed
./scripts/setup-fork.sh
```

### Updating Configuration

To change configuration after initial setup:

1. Edit `Fork.plist` directly
2. Or re-run `./scripts/setup-fork.sh`
3. Clean build in Xcode (`Cmd+Shift+K`)
4. Build and run

### Version Management

Update version in:

- Xcode project settings (Version and Build)
- `Fork.plist` if you track versions there
- Git tags for releases

## Troubleshooting

### Common Issues

#### Fork.plist Not Found

**Problem**: App uses default values
**Solution**:

1. Ensure `Fork.plist` is in project root
2. Add to Xcode project (not just filesystem)
3. Check it's included in app target

#### Bundle ID Conflicts

**Problem**: Can't install alongside original VoiceInk
**Solution**: Ensure your `BundleIdentifierPrefix` is unique

#### Features Not Hiding

**Problem**: UI shows even with blank URLs
**Solution**:

1. Clean build (`Cmd+Shift+K`)
2. Check `Fork.plist` has empty strings, not missing keys
3. Verify `AppConfig.shared` is reading your config

#### Support Email Not Working

**Problem**: Email client doesn't open
**Solution**: Check `SupportEmail` is valid email format

### Debug Configuration

Check if your configuration is loaded:

```swift
// Add to AppDelegate or any view
print("Bundle ID: \(AppConfig.shared.mainBundleIdentifier)")
print("Support: \(AppConfig.shared.supportEmail)")
print("Has purchase: \(AppConfig.shared.showPurchaseOptions)")
```

### Console Logging

Filter logs by your configured subsystem:

```bash
log show --predicate 'subsystem == "com.yourdomain.voiceink"' --last 1h
```

## Best Practices

### For Open Source Forks

1. **Never commit `Fork.plist`** - It's gitignored for a reason
2. **Update `Fork.plist.template`** - If you add new config options
3. **Document your changes** - Update this guide with your additions
4. **Share improvements** - Consider PRs for useful features

### For Private/Commercial Use

1. **Customize bundle IDs** - Avoid conflicts with other forks
2. **Set up code signing** - Use your organization's certificates
3. **Configure support channels** - Update all contact information
4. **Consider telemetry** - Add your own analytics if needed (with user consent)
5. **Plan update strategy** - Without auto-updates, plan distribution

### Security Considerations

- **API Keys**: Never commit API keys; use Keychain or environment variables
- **URLs**: Validate all URLs from configuration before use
- **Features**: Audit enabled features for your use case
- **Updates**: Monitor upstream for security fixes

## Advanced Configuration

### Adding New Configuration Options

1. Add key to `Fork.plist.template`
2. Update `AppConfig.swift`:
   ```swift
   let myNewOption = config?["MyNewOption"] as? String
   ```
3. Use in your code:
   ```swift
   if let option = AppConfig.shared.myNewOption {
       // Feature enabled
   }
   ```

### Conditional Compilation

For build-time configuration:

```swift
#if PREMIUM_BUILD
    // Premium features
#endif
```

### Environment-Specific Configs

Create multiple configurations:

- `Fork.plist` - Development
- `Fork.production.plist` - Production
- `Fork.staging.plist` - Staging

Switch via build schemes in Xcode.

## Support

### Getting Help

1. Check this documentation
2. Review [ARCHITECTURE.md](./ARCHITECTURE.md) for technical details
3. See [PRIVACY_AUDIT.md](./PRIVACY_AUDIT.md) for removed features
4. Open an issue on GitHub
5. Contact the fork maintainer (via configured support email)

### Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Update documentation
5. Submit a pull request

---

_Last updated: October 2025_
_Fork configuration system version: 1.0_
