# VoiceInk Migration Guide

> **Guide for migrating from original VoiceInk or updating existing forks**

## Table of Contents

- [Migration Scenarios](#migration-scenarios)
- [From Original VoiceInk](#from-original-voiceink)
- [Updating Existing Fork](#updating-existing-fork)
- [Breaking Changes](#breaking-changes)
- [Data Migration](#data-migration)
- [Syncing with Upstream](#syncing-with-upstream)
- [Rollback Procedures](#rollback-procedures)

## Migration Scenarios

### Which Guide Do You Need?

| Your Situation                                | Guide Section                                     |
| --------------------------------------------- | ------------------------------------------------- |
| Using original VoiceInk, want privacy fork    | [From Original VoiceInk](#from-original-voiceink) |
| Have existing fork, want configuration system | [Updating Existing Fork](#updating-existing-fork) |
| Want to sync latest changes from upstream     | [Syncing with Upstream](#syncing-with-upstream)   |
| Need to preserve user data                    | [Data Migration](#data-migration)                 |
| Something went wrong                          | [Rollback Procedures](#rollback-procedures)       |

## From Original VoiceInk

### Pre-Migration Checklist

- [ ] Backup your VoiceInk data
- [ ] Export any custom settings
- [ ] Note your license key (if applicable)
- [ ] Document custom keyboard shortcuts
- [ ] Save any custom AI prompts
- [ ] Export your personal dictionary

### Step 1: Backup Current Data

#### Locate VoiceInk Data

```bash
# Original VoiceInk data location
~/Library/Application Support/com.jshimko.VoiceInk/

# Backup everything
cp -r ~/Library/Application\ Support/com.jshimko.VoiceInk ~/Desktop/VoiceInk-Backup
```

#### Data to Backup

| Data Type          | Location            | File/Folder                  |
| ------------------ | ------------------- | ---------------------------- |
| Transcriptions     | Application Support | `default.store`              |
| Audio recordings   | Application Support | `Recordings/`                |
| Whisper models     | Application Support | `WhisperModels/`             |
| Settings           | UserDefaults        | `com.jshimko.VoiceInk.plist` |
| Keyboard shortcuts | UserDefaults        | Embedded in plist            |

### Step 2: Uninstall Original

```bash
# Remove original VoiceInk
rm -rf /Applications/VoiceInk.app

# Optional: Remove all data (after backup!)
rm -rf ~/Library/Application\ Support/com.jshimko.VoiceInk
rm ~/Library/Preferences/com.jshimko.VoiceInk.plist
```

### Step 3: Install Fork

1. **Clone the fork:**

   ```bash
   git clone https://github.com/YOUR_USERNAME/VoiceInk.git
   cd VoiceInk
   ```

2. **Configure your fork:**

   ```bash
   ./scripts/setup-fork.sh
   ```

3. **Build and install:**
   ```bash
   xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release
   cp -r build/Release/VoiceInk.app /Applications/
   ```

### Step 4: Migrate Data

#### Option A: Same Bundle ID (Seamless)

If you use `com.jshimko` as your prefix, data migrates automatically.

#### Option B: Different Bundle ID (Manual)

```bash
# Copy data to new location
OLD_BUNDLE="com.jshimko.VoiceInk"
NEW_BUNDLE="com.yourdomain.VoiceInk"

cp -r ~/Library/Application\ Support/$OLD_BUNDLE/* \
      ~/Library/Application\ Support/$NEW_BUNDLE/
```

### Step 5: Verify Migration

- [ ] App launches successfully
- [ ] Previous transcriptions visible
- [ ] Audio recordings accessible
- [ ] Settings preserved
- [ ] Keyboard shortcuts work
- [ ] Models don't need re-downloading

## Updating Existing Fork

### From Earlier Fork Version

#### Check Current Version

```bash
# Check your fork's base
git log --oneline | grep -i fork

# Check divergence from upstream
git remote add upstream https://github.com/Beingpax/VoiceInk.git
git fetch upstream
git log upstream/main..HEAD --oneline
```

#### Apply Configuration System

1. **Fetch latest changes:**

   ```bash
   git fetch upstream
   git checkout -b add-configuration
   ```

2. **Cherry-pick configuration commits:**

   ```bash
   # Get configuration system commits
   git cherry-pick <commit-hash-1> <commit-hash-2> ...
   ```

3. **Or merge selectively:**

   ```bash
   git checkout upstream/main -- Fork.plist.template
   git checkout upstream/main -- VoiceInk/AppConfig.swift
   git checkout upstream/main -- scripts/setup-fork.sh
   ```

4. **Update your code:**

   ```bash
   # Run setup script
   ./scripts/setup-fork.sh

   # Update remaining references
   grep -r "com\..*voiceink" --include="*.swift"
   # Manually update any remaining hardcoded values
   ```

## Breaking Changes

### Configuration System (v1.0)

#### Changed Files

| File                          | Change Type    | Impact                  |
| ----------------------------- | -------------- | ----------------------- |
| `VoiceInk.swift`              | Modified       | AppConfig dependency    |
| `LicenseManagementView.swift` | Modified       | URL configuration       |
| `EmailSupport.swift`          | Modified       | Email configuration     |
| `WhisperState.swift`          | Modified       | Path configuration      |
| All Logger files              | Modified       | Subsystem configuration |
| `Fork.plist`                  | New Required\* | Configuration file      |

\*Required for customization, app works with defaults

#### API Changes

**Before:**

```swift
let supportEmail = "support@yourdomain.com"
let bundleID = "com.jshimko.VoiceInk"
```

**After:**

```swift
let supportEmail = AppConfig.shared.supportEmail
let bundleID = AppConfig.shared.mainBundleIdentifier
```

#### Required Actions

1. Add `AppConfig.swift` to project
2. Create `Fork.plist` configuration
3. Update all hardcoded references
4. Test with new configuration

### Removed Features

| Feature            | Alternative    | Migration                    |
| ------------------ | -------------- | ---------------------------- |
| Auto-updates       | Manual updates | Implement your own if needed |
| License validation | None needed    | App runs freely              |
| Announcements      | None           | Remove UI references         |
| Analytics          | None           | Add your own if needed       |

## Data Migration

### SwiftData Schema

The fork maintains compatibility with original schema:

```swift
// No schema changes required
let schema = Schema([
    Transcription.self
])
```

### UserDefaults Migration

#### Key Mappings

| Original Key                 | Fork Key         | Action                          |
| ---------------------------- | ---------------- | ------------------------------- |
| `com.jshimko.VoiceInk.*`     | `{YourBundle}.*` | Auto-migrates if same structure |
| `selectedTranscriptionModel` | Same             | No change                       |
| `enableAIEnhancement`        | Same             | No change                       |
| `powerModeConfigs`           | Same             | No change                       |

#### Manual Migration Script

```swift
// In AppDelegate.swift
func migrateUserDefaults() {
    let oldDomain = "com.jshimko.VoiceInk"
    let newDomain = AppConfig.shared.mainBundleIdentifier

    if let oldDefaults = UserDefaults(suiteName: oldDomain) {
        let newDefaults = UserDefaults(suiteName: newDomain)

        for (key, value) in oldDefaults.dictionaryRepresentation() {
            newDefaults?.set(value, forKey: key)
        }
    }
}
```

### Model Files Migration

Whisper models are bundle-agnostic and don't need migration:

```bash
# Models remain in same relative location
~/Library/Application Support/{BundleID}/WhisperModels/
```

## Syncing with Upstream

### Setup Upstream Remote

```bash
# Add original repository
git remote add upstream https://github.com/Beingpax/VoiceInk.git
git fetch upstream
```

### Regular Sync Process

```bash
# 1. Create sync branch
git checkout main
git checkout -b sync-upstream

# 2. Fetch and merge
git fetch upstream
git merge upstream/main

# 3. Resolve conflicts
# Fork.plist.template - Keep fork version
# Hardcoded values - Keep configured version
# New features - Merge normally

# 4. Test thoroughly
./scripts/setup-fork.sh
xcodebuild test

# 5. Merge to main
git checkout main
git merge sync-upstream
```

### Conflict Resolution

Common conflicts and resolutions:

| File                  | Conflict Type     | Resolution        |
| --------------------- | ----------------- | ----------------- |
| `Fork.plist.template` | Structure changes | Merge new keys    |
| `AppConfig.swift`     | New properties    | Add with defaults |
| `*.swift`             | Hardcoded values  | Keep configured   |
| `Info.plist`          | Bundle ID         | Keep your fork's  |

## Rollback Procedures

### Quick Rollback

```bash
# Restore from backup
cp -r ~/Desktop/VoiceInk-Backup/* ~/Library/Application\ Support/{YourBundleID}/

# Revert to previous version
git checkout <previous-version-tag>
xcodebuild clean build
```

### Data Recovery

#### Lost Transcriptions

```bash
# Check for SwiftData WAL files
ls ~/Library/Application\ Support/*/default.store*

# Recover from SQLite
sqlite3 default.store
.dump transcriptions
```

#### Lost Settings

```bash
# Check preferences
defaults read {YourBundleID}

# Restore from backup
cp ~/Desktop/VoiceInk-Backup/*.plist ~/Library/Preferences/
```

## Migration Validation

### Post-Migration Tests

- [ ] **Launch Test**: App starts without errors
- [ ] **Data Test**: Previous transcriptions load
- [ ] **Audio Test**: Can record and transcribe
- [ ] **Settings Test**: Preferences preserved
- [ ] **Model Test**: Whisper models recognized
- [ ] **UI Test**: No missing UI elements
- [ ] **Network Test**: No unwanted connections
- [ ] **Privacy Test**: No phone-home behavior

### Verification Commands

```bash
# Check bundle identifier
defaults read /Applications/VoiceInk.app/Contents/Info.plist CFBundleIdentifier

# Check data migration
ls -la ~/Library/Application\ Support/*/VoiceInk/

# Monitor network
nettop -p $(pgrep VoiceInk)

# Check logs
log show --predicate 'subsystem == "com.yourdomain.voiceink"' --last 1h
```

## Common Issues

### Issue: Data Not Migrating

**Cause:** Different bundle identifier
**Solution:** Manual copy or symlink data

### Issue: Models Need Re-downloading

**Cause:** Path mismatch
**Solution:** Copy models to new location or symlink

### Issue: Settings Reset

**Cause:** UserDefaults domain change
**Solution:** Run migration script or manually set

### Issue: Keyboard Shortcuts Lost

**Cause:** Stored under old bundle ID
**Solution:** Re-configure in settings

## Support

### Getting Help

1. Check this migration guide
2. Review [FORK_GUIDE.md](./FORK_GUIDE.md)
3. Search existing issues
4. Open new issue with:
   - Original version
   - Fork version
   - Migration method used
   - Error messages

### Reporting Issues

Include in bug reports:

- Migration path (original → fork)
- Data migration method
- Bundle identifiers (old/new)
- Console logs
- Steps to reproduce

## Best Practices

### For Smooth Migration

1. **Always backup first** - Data is irreplaceable
2. **Test in parallel** - Run both versions initially
3. **Migrate gradually** - Don't delete original immediately
4. **Document changes** - Track what you modified
5. **Keep upstream remote** - Easy future syncing

### For Fork Maintainers

1. **Document breaking changes** - Update this guide
2. **Provide migration scripts** - Automate where possible
3. **Maintain compatibility** - Avoid unnecessary breaks
4. **Version appropriately** - Semantic versioning
5. **Test migration paths** - From various versions

---

_Migration Guide Version: 1.0_
_Last updated: October 2025_
_Compatible with: VoiceInk Fork 1.0+_
