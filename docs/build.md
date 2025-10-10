# VoiceInk Build and Installation Guide

## Table of Contents

- [Prerequisites](#prerequisites)
- [Dependencies](#dependencies)
- [Quick Start](#quick-start)
- [Detailed Build Instructions](#detailed-build-instructions)
- [Running the Application](#running-the-application)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)
- [Contributing](#contributing)

## Prerequisites

### System Requirements

#### Hardware

- **Mac**: Apple Silicon (M1/M2/M3) or Intel-based Mac
- **Memory**: Minimum 8GB RAM (16GB recommended for development)
- **Storage**: At least 5GB free disk space
  - VoiceInk: ~200MB
  - whisper.cpp build: ~1GB
  - Xcode: ~3GB
  - Dependencies and build artifacts: ~500MB

#### Software

- **macOS**: 14.0 (Sonoma) or later
- **Xcode**: 15.0 or later (26.0+ recommended)
  - Download from [Mac App Store](https://apps.apple.com/us/app/xcode/id497799835) or [Apple Developer](https://developer.apple.com/xcode/)
- **Command Line Tools**: Required for building from terminal
- **Git**: For cloning repositories (included with Xcode Command Line Tools)

### Required Development Tools

1. **Xcode Command Line Tools**

   ```bash
   # Install Command Line Tools
   xcode-select --install

   # Verify installation
   xcode-select -p
   # Expected output: /Applications/Xcode.app/Contents/Developer
   ```

2. **Git** (included with Command Line Tools)

   ```bash
   # Verify Git installation
   git --version
   # Expected output: git version 2.x.x
   ```

3. **CMake** (Required for building whisper.cpp)

   ```bash
   # Install using Homebrew
   brew install cmake

   # Or download from https://cmake.org/download/
   ```

### Optional Tools

- **Homebrew**: Package manager for macOS (recommended)

  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

- **xcpretty**: Better formatting for xcodebuild output
  ```bash
  gem install xcpretty
  ```

### Developer Account Requirements

#### For Development (Running on Your Mac)

- **Apple Developer Account**: NOT required for local development
- **Code Signing**: Automatic signing with personal team

#### For Distribution

- **Apple Developer Program**: Required ($99/year)
- **Developer ID Certificate**: For notarization
- **App Store Connect**: For App Store distribution

## Dependencies

### External Frameworks

#### 1. whisper.cpp (Core Transcription Engine)

- **Repository**: https://github.com/ggerganov/whisper.cpp
- **Purpose**: Local speech-to-text transcription
- **Build Method**: XCFramework via build script
- **Size**: ~100MB when built

#### 2. Swift Package Manager Dependencies

The following dependencies are automatically resolved by Xcode:

| Package                | Repository                                           | Purpose                  |
| ---------------------- | ---------------------------------------------------- | ------------------------ |
| **KeyboardShortcuts**  | https://github.com/sindresorhus/KeyboardShortcuts    | Global hotkey management |
| **Sparkle**            | https://github.com/sparkle-project/Sparkle           | Auto-update framework    |
| **LaunchAtLogin**      | https://github.com/sindresorhus/LaunchAtLogin-Modern | Startup management       |
| **FluidAudio**         | https://github.com/FluidInference/FluidAudio         | Parakeet model support   |
| **MediaRemoteAdapter** | https://github.com/ejbills/mediaremote-adapter       | Media playback control   |
| **Zip**                | https://github.com/marmelroy/Zip                     | Archive handling         |

### Updating Dependencies

#### Swift Package Manager Dependencies

1. Open VoiceInk.xcodeproj in Xcode
2. Navigate to File → Swift Packages → Update to Latest Package Versions
3. Or update individually in Project Settings → Package Dependencies

#### whisper.cpp Framework

```bash
cd ../whisper.cpp
git pull origin master
./build-xcframework.sh
# Copy the new framework to VoiceInk project
```

## Quick Start

For the fastest setup, use our automated scripts:

```bash
# Clone VoiceInk repository
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk

# Run automated setup (builds whisper.cpp and configures project)
./scripts/setup-project.sh

# Build and run the app
./scripts/build-app.sh

# Or open in Xcode
open VoiceInk.xcodeproj
```

## Detailed Build Instructions

### Step 1: Clone the Repositories

```bash
# Create a workspace directory
mkdir -p ~/Development/VoiceInk
cd ~/Development/VoiceInk

# Clone VoiceInk
git clone https://github.com/Beingpax/VoiceInk.git

# Clone whisper.cpp (if not already present)
if [ ! -d "whisper.cpp" ]; then
    git clone https://github.com/ggerganov/whisper.cpp.git
fi
```

### Step 2: Build whisper.cpp Framework

#### Option A: Using the Automated Script (Recommended)

```bash
cd whisper.cpp
./build-xcframework.sh
```

#### Option B: Manual Build

```bash
cd whisper.cpp

# Create build directory
mkdir -p build-apple

# Configure with CMake
cmake -B build-apple \
    -G Xcode \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON

# Build for all architectures
xcodebuild -project build-apple/whisper.cpp.xcodeproj \
    -scheme whisper \
    -configuration Release \
    -arch arm64 \
    -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO

# Create XCFramework
xcodebuild -create-xcframework \
    -framework build-apple/Release/whisper.framework \
    -output build-apple/whisper.xcframework
```

#### Verify Framework Build

```bash
# Check that the framework was created
ls -la build-apple/whisper.xcframework
# Should show directories for different platforms
```

### Step 3: Configure Xcode Project

1. **Open the Project**

   ```bash
   cd ../VoiceInk
   open VoiceInk.xcodeproj
   ```

2. **Add whisper.xcframework**

   - In Xcode, select the VoiceInk project in the navigator
   - Select the VoiceInk target
   - Go to "General" tab → "Frameworks, Libraries, and Embedded Content"
   - Click "+" and select "Add Other..." → "Add Files..."
   - Navigate to `../whisper.cpp/build-apple/whisper.xcframework`
   - Ensure "Embed & Sign" is selected

3. **Resolve Swift Package Dependencies**
   - Xcode should automatically resolve dependencies on first open
   - If not: File → Swift Packages → Resolve Package Versions

### Step 4: Configure Code Signing

#### For Local Development

1. Select the VoiceInk project in navigator
2. Select the VoiceInk target
3. Go to "Signing & Capabilities" tab
4. Enable "Automatically manage signing"
5. Select your Team (Personal Team for free account)
6. Bundle Identifier: `com.yourname.VoiceInk` (change if needed)

#### For Distribution

1. Use your paid Developer Account team
2. Configure proper Bundle ID: `com.yourcompany.VoiceInk`
3. Ensure proper provisioning profiles

### Step 5: Build the Application

#### Using Xcode GUI

1. Select target device: "My Mac" or specific architecture
2. Select scheme: VoiceInk
3. Build: Press `Cmd+B` or Product → Build
4. Run: Press `Cmd+R` or Product → Run

#### Using Command Line

```bash
# Debug build
xcodebuild -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Debug \
    -derivedDataPath build \
    build

# Release build
xcodebuild -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Release \
    -derivedDataPath build \
    build

# Build with pretty output (requires xcpretty)
xcodebuild -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Debug \
    build | xcpretty
```

## Running the Application

### From Xcode

1. Select "My Mac" as the run destination
2. Press `Cmd+R` or click the Run button
3. The app will build and launch automatically

### From Command Line

```bash
# After building, run the app
open build/Build/Products/Debug/VoiceInk.app

# Or for release build
open build/Build/Products/Release/VoiceInk.app
```

### Required Permissions on First Launch

VoiceInk will request the following permissions on first launch:

1. **Microphone Access**

   - Required for audio recording
   - System prompt: "VoiceInk needs access to your microphone to record audio for transcription."

2. **Screen Recording** (Optional)

   - For Power Mode context awareness
   - System Preferences → Privacy & Security → Screen Recording
   - Add VoiceInk and enable

3. **Accessibility** (Optional)
   - For detecting active windows in Power Mode
   - System Preferences → Privacy & Security → Accessibility
   - Add VoiceInk and enable

### Configuration for Development

1. **Enable Developer Mode**

   - Open VoiceInk
   - Preferences → Advanced → Enable Developer Mode

2. **Configure API Keys** (for cloud transcription)

   - Preferences → AI Models
   - Add API keys for OpenAI, Anthropic, or Groq

3. **Download Local Models** (optional)
   - Preferences → AI Models → Local Models
   - Download Whisper models for offline transcription

## Testing

### Running Unit Tests

#### From Xcode

```bash
# Run all tests
Cmd+U

# Run specific test
# Select test in Test Navigator → Right-click → Run
```

#### From Command Line

```bash
# Run all tests
xcodebuild test \
    -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -destination 'platform=macOS'

# Run with coverage
xcodebuild test \
    -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -enableCodeCoverage YES \
    -destination 'platform=macOS'
```

### Running UI Tests

```bash
# Run UI tests
xcodebuild test \
    -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -only-testing:VoiceInkUITests \
    -destination 'platform=macOS'
```

### Test Coverage Requirements

- **Minimum Coverage**: 70% for new code
- **Critical Paths**: 90% for core functionality
- **View Coverage Report**:
  - Xcode: Product → Show Build Report → Coverage
  - Command line: Use `xcov` or `slather` tools

### Writing New Tests

#### Unit Tests

```swift
// Add to VoiceInkTests/YourFeatureTests.swift
import XCTest
@testable import VoiceInk

class YourFeatureTests: XCTestCase {
    func testExample() {
        // Given
        let feature = YourFeature()

        // When
        let result = feature.doSomething()

        // Then
        XCTAssertEqual(result, expectedValue)
    }
}
```

#### UI Tests

```swift
// Add to VoiceInkUITests/YourFeatureUITests.swift
import XCTest

class YourFeatureUITests: XCTestCase {
    func testUIFlow() {
        let app = XCUIApplication()
        app.launch()

        // Test UI interactions
        app.buttons["Record"].tap()
        XCTAssert(app.staticTexts["Recording..."].exists)
    }
}
```

## Troubleshooting

### Common Build Errors

#### 1. Framework Not Found: whisper

**Error**: `ld: framework not found whisper`

**Solution**:

```bash
# Rebuild whisper framework
cd ../whisper.cpp
./build-xcframework.sh

# Re-add to Xcode project
# Remove old reference and add new framework
```

#### 2. Swift Package Resolution Failed

**Error**: `Failed to resolve dependencies`

**Solution**:

```bash
# Clear package cache
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData

# In Xcode: File → Swift Packages → Reset Package Caches
```

#### 3. Code Signing Failed

**Error**: `Code signing is required for product type 'Application'`

**Solution**:

- Enable automatic signing in project settings
- Select a development team
- Or disable code signing for local builds:

```bash
xcodebuild -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    build
```

#### 4. Minimum OS Version Error

**Error**: `The application requires macOS 14.0 or later`

**Solution**:

- Update to macOS 14.0 (Sonoma) or later
- Or modify deployment target (not recommended):
  - Project Settings → Deployment Target → macOS 13.0

#### 5. Missing Entitlements

**Error**: `The application does not have permission to access the microphone`

**Solution**:

- Ensure Info.plist contains usage descriptions
- Check entitlements file is included in build settings
- Reset permissions: `tccutil reset Microphone com.yourcompany.VoiceInk`

### Framework Linking Issues

#### Undefined Symbols

```bash
# Clean build folder
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodebuild clean -project VoiceInk.xcodeproj

# Rebuild
xcodebuild -project VoiceInk.xcodeproj build
```

#### Runtime Dylib Errors

```bash
# Check framework embedding
otool -L build/Build/Products/Debug/VoiceInk.app/Contents/MacOS/VoiceInk

# Verify framework is embedded
ls -la build/Build/Products/Debug/VoiceInk.app/Contents/Frameworks/
```

### Permission Problems

#### Reset All Permissions

```bash
# Reset specific permissions
tccutil reset Microphone com.yourcompany.VoiceInk
tccutil reset ScreenCapture com.yourcompany.VoiceInk
tccutil reset Accessibility com.yourcompany.VoiceInk

# Check current permissions
defaults read com.apple.TCC
```

### Clean Build Procedures

#### Complete Clean

```bash
# Clean Xcode build
xcodebuild clean -project VoiceInk.xcodeproj

# Remove derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Clean package caches
rm -rf ~/Library/Caches/org.swift.swiftpm

# Remove build folder
rm -rf build/

# Reset simulator (if applicable)
xcrun simctl shutdown all
xcrun simctl erase all
```

### Debug vs Release Configuration Issues

#### Build Configuration Differences

| Setting             | Debug      | Release    |
| ------------------- | ---------- | ---------- |
| Optimization        | None (-O0) | Full (-O2) |
| Debug Symbols       | Yes        | Limited    |
| Assert/Precondition | Enabled    | Disabled   |
| Code Coverage       | Available  | Disabled   |

#### Switch Between Configurations

```bash
# Debug build (default)
xcodebuild -configuration Debug build

# Release build
xcodebuild -configuration Release build

# Check active configuration in Xcode
# Product → Scheme → Edit Scheme → Build Configuration
```

## Advanced Topics

### Creating Release Builds

#### 1. Archive the Application

```bash
xcodebuild archive \
    -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Release \
    -archivePath build/VoiceInk.xcarchive
```

#### 2. Export for Distribution

```bash
# Create ExportOptions.plist
cat > ExportOptions.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
EOF

# Export archive
xcodebuild -exportArchive \
    -archivePath build/VoiceInk.xcarchive \
    -exportPath build/Release \
    -exportOptionsPlist ExportOptions.plist
```

#### 3. Notarization (Required for Distribution)

```bash
# Submit for notarization
xcrun notarytool submit build/Release/VoiceInk.app \
    --apple-id "your-apple-id@example.com" \
    --password "app-specific-password" \
    --team-id "YOUR_TEAM_ID" \
    --wait

# Staple the notarization
xcrun stapler staple build/Release/VoiceInk.app
```

### Custom Build Configurations

#### Create New Configuration

1. Project Settings → Info → Configurations
2. Duplicate existing configuration
3. Rename (e.g., "Beta", "Testing")

#### Configuration-Specific Settings

```swift
// In code
#if DEBUG
    print("Debug mode")
#elseif BETA
    print("Beta mode")
#else
    print("Release mode")
#endif
```

#### Build with Custom Configuration

```bash
xcodebuild -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Beta \
    build
```

### Performance Profiling

```bash
# Build for profiling
xcodebuild -project VoiceInk.xcodeproj \
    -scheme VoiceInk \
    -configuration Release \
    -derivedDataPath build \
    build

# Open in Instruments
open /Applications/Xcode.app/Contents/Applications/Instruments.app
# Select Time Profiler, Allocations, or other templates
```

### Continuous Integration

#### GitHub Actions Example

```yaml
name: Build and Test
on: [push, pull_request]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2

      - name: Build whisper.cpp
        run: |
          git clone https://github.com/ggerganov/whisper.cpp.git ../whisper.cpp
          cd ../whisper.cpp
          ./build-xcframework.sh

      - name: Build VoiceInk
        run: |
          xcodebuild -project VoiceInk.xcodeproj \
            -scheme VoiceInk \
            -configuration Debug \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            build

      - name: Run Tests
        run: |
          xcodebuild test \
            -project VoiceInk.xcodeproj \
            -scheme VoiceInk \
            -destination 'platform=macOS'
```

## Contributing

### Development Workflow

1. **Fork the repository**
2. **Create a feature branch**

   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make changes and test**

   ```bash
   ./scripts/run-tests.sh
   ```

4. **Commit with descriptive messages**

   ```bash
   git commit -m "feat: add new transcription feature"
   ```

5. **Push and create pull request**
   ```bash
   git push origin feature/your-feature-name
   ```

### Code Style Guidelines

- Follow Swift API Design Guidelines
- Use SwiftLint for consistent formatting
- Add documentation comments for public APIs
- Include unit tests for new features

### Submitting Pull Requests

1. Ensure all tests pass
2. Update documentation if needed
3. Add entry to CHANGELOG
4. Request review from maintainers

## Support

### Getting Help

- **Issues**: https://github.com/Beingpax/VoiceInk/issues
- **Discussions**: https://github.com/Beingpax/VoiceInk/discussions
- **Documentation**: Check `/docs` folder
- **Wiki**: https://github.com/Beingpax/VoiceInk/wiki

### Reporting Bugs

When reporting bugs, include:

1. macOS version
2. Xcode version
3. Steps to reproduce
4. Error messages
5. Console logs (`Console.app` output)

### Feature Requests

Submit feature requests via GitHub Issues with:

- Clear description
- Use cases
- Mockups (if applicable)
- Implementation suggestions

---

## Quick Reference

### Essential Commands

```bash
# Setup (first time)
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
./scripts/setup-project.sh

# Daily development
./scripts/build-app.sh          # Build debug version
./scripts/run-tests.sh          # Run all tests
./scripts/clean-build.sh        # Clean and rebuild

# Release
./scripts/create-release.sh     # Create release build
```

### File Locations

| Item         | Location                                               |
| ------------ | ------------------------------------------------------ |
| App Bundle   | `build/Build/Products/{Debug\|Release}/VoiceInk.app`   |
| Derived Data | `~/Library/Developer/Xcode/DerivedData`                |
| Logs         | `~/Library/Logs/VoiceInk/`                             |
| Preferences  | `~/Library/Preferences/com.yourcompany.VoiceInk.plist` |
| App Support  | `~/Library/Application Support/VoiceInk/`              |

### Useful Debugging Commands

```bash
# View console logs
log show --predicate 'subsystem == "com.voiceink"' --last 1h

# Check code signing
codesign -vvv --deep --strict VoiceInk.app

# View app entitlements
codesign -d --entitlements :- VoiceInk.app

# List linked frameworks
otool -L VoiceInk.app/Contents/MacOS/VoiceInk
```

---

_Last updated: October 2024_
_VoiceInk Version: 1.0_
_Documentation Version: 1.0_
