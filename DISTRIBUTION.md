# Distribution Guide for mss Library

This guide explains how to distribute the mss library and how users can install it.

## Table of Contents

1. [System-Wide Installation (Recommended)](#system-wide-installation-recommended)
2. [Creating Releases](#creating-releases)
3. [Homebrew Distribution](#homebrew-distribution)
4. [Manual Installation](#manual-installation)
5. [For Developers Using mss](#for-developers-using-mss)

---

## System-Wide Installation (Recommended)

The mss library is designed to be installed system-wide so multiple applications can share the same installation.

### Via Homebrew (Easiest)

**Install the library:**
```bash
brew tap ryanthedev/mss
brew install mss
```

**Install the scripting addition (one-time, requires root + SIP disabled):**
```bash
sudo mss check    # Verify system requirements
sudo mss load     # Install and load into Dock.app
sudo mss status   # Verify it's working
```

### Via Manual Installation

**Download and install:**
```bash
# Download release
curl -L https://github.com/ryanthedev/mss/archive/refs/tags/v0.0.1.tar.gz -o mss.tar.gz
tar -xzf mss.tar.gz
cd mss-0.0.1

# Build and install
make
sudo make install

# Install scripting addition
sudo mss load
```

**Default installation locations:**
- Library: `/usr/local/lib/libmss.a`
- Headers: `/usr/local/include/mss/mss.h`, `/usr/local/include/mss/mss_types.h`
- CLI tool: `/usr/local/bin/mss`
- pkg-config: `/usr/local/lib/pkgconfig/mss.pc`

---

## Creating Releases

### Prerequisites

1. All changes committed and pushed to main branch
2. Version number updated in `include/mss_types.h` and `src/common.h`
3. Tests passing (`make clean && make && make cli`)

### Release Process

**1. Update version numbers:**
```bash
# Update version in both files (must match):
# - include/mss_types.h: #define MSS_VERSION "X.Y.Z"
# - src/common.h: #define OSAX_VERSION "X.Y.Z"
```

**2. Create and tag release:**
```bash
# Commit version changes
git add include/mss_types.h src/common.h
git commit -m "Bump version to X.Y.Z"
git push

# Create annotated tag
git tag -a vX.Y.Z -m "Release version X.Y.Z"
git push origin vX.Y.Z
```

**3. Build release tarball:**
```bash
make clean
make dist

# Output: mss-X.Y.Z.tar.gz
# SHA256 checksum is displayed
```

**4. Create GitHub release:**
```bash
# Using GitHub CLI
gh release create vX.Y.Z mss-X.Y.Z.tar.gz \
  --title "mss X.Y.Z" \
  --notes "Release notes here..."

# Or manually:
# 1. Go to https://github.com/ryanthedev/mss/releases/new
# 2. Select tag vX.Y.Z
# 3. Upload mss-X.Y.Z.tar.gz
# 4. Add release notes
# 5. Publish
```

**5. Homebrew formula update (automatic):**

The GitHub Actions workflow automatically updates the Homebrew formula in the `homebrew-mss` tap repository. Verify the update at:
```
https://github.com/ryanthedev/homebrew-mss/commits/main
```

No manual action required!

---

## Homebrew Distribution

### Homebrew Tap

The mss library is distributed via a dedicated Homebrew tap at:
**https://github.com/ryanthedev/homebrew-mss**

**Users install with:**
```bash
brew tap ryanthedev/mss
brew install mss
```

**Formula maintenance:**
The GitHub Actions release workflow automatically updates the formula in the tap repository when creating releases. The formula is kept in sync with the main repository's version, URL, and SHA256 checksums.

### Submitting to homebrew-core (Advanced)

To make `brew install mss` work without a tap:

1. Library must be stable and widely used
2. Follow [Homebrew contribution guidelines](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request)
3. Submit PR to [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core)

**Requirements:**
- No known security vulnerabilities
- Active maintenance
- Significant user base
- License compatible with Homebrew
- Successfully builds on all supported macOS versions

---

## Manual Installation

### Building from Source

**Clone and build:**
```bash
git clone https://github.com/ryanthedev/mss.git
cd mss
make
make cli
```

**Install system-wide (requires sudo):**
```bash
sudo make install
```

**Or install to custom location:**
```bash
make install PREFIX=$HOME/.local
```

**Uninstall:**
```bash
sudo make uninstall
```

### Using Pre-Built Tarballs

**Download release:**
```bash
curl -L https://github.com/ryanthedev/mss/releases/download/vX.Y.Z/mss-X.Y.Z.tar.gz -o mss.tar.gz
tar -xzf mss.tar.gz
cd mss-X.Y.Z
```

**Tarball contains:**
```
mss-X.Y.Z/
├── lib/libmss.a           # Static library
├── include/               # Headers
│   ├── mss.h
│   └── mss_types.h
├── bin/mss                # CLI tool
├── mss.pc.in              # pkg-config template
├── Makefile               # For installation
├── LICENSE
└── *.md                   # Documentation
```

**Install:**
```bash
sudo make install PREFIX=/usr/local
```

---

## For Developers Using mss

### System-Wide Installation (Recommended)

**After `make install` or `brew install mss`:**

**1. Using pkg-config (recommended):**
```bash
gcc myapp.c $(pkg-config --cflags --libs mss) -o myapp
```

**2. Manual linking:**
```bash
gcc myapp.c \
  -I/usr/local/include/mss \
  -L/usr/local/lib -lmss \
  -framework Cocoa -framework CoreGraphics \
  -o myapp
```

**3. In Xcode:**
- Header Search Paths: `/usr/local/include/mss`
- Library Search Paths: `/usr/local/lib`
- Link Binary: Add `/usr/local/lib/libmss.a`
- Link Frameworks: Cocoa.framework, CoreGraphics.framework

**4. In Swift:**
```swift
// Create bridging header:
#import <mss.h>

// Use in Swift code:
let ctx = mss_create(nil)
```

See [SWIFT_INTEGRATION.md](SWIFT_INTEGRATION.md) for complete Swift guide.

### Embedding in Application Bundle

Alternatively, developers can bundle the library directly in their app:

**1. Copy library files to project:**
```
YourApp/
└── Libraries/
    └── mss/
        ├── libmss.a
        ├── mss.h
        └── mss_types.h
```

**2. Configure Xcode:**
- Add `libmss.a` to "Link Binary With Libraries"
- Header Search Paths: `$(SRCROOT)/YourApp/Libraries/mss`

**3. Bundle installer tool:**
```
YourApp.app/
└── Contents/
    └── MacOS/
        └── mss    # Copy from /usr/local/bin/mss
```

**4. First-run installation:**
```swift
// In app, check if payload loaded:
if !manager.isLoaded() {
    showInstallDialog()  // Guide user to run installer
}
```

---

## System Requirements

### For Building (Development)

- macOS 11.0+ (Big Sur or later)
- Xcode Command Line Tools
- No special privileges required

### For Runtime (Using the Library)

**Linking and API calls:** No special requirements

**Installing scripting addition (one-time):**
- Root privileges (`sudo`)
- SIP partially disabled:
  - Boot to Recovery (⌘R at startup)
  - Run: `csrutil enable --without fs --without debug`
  - Reboot
- ARM64 Macs only:
  - Run: `sudo nvram boot-args="-arm64e_preview_abi"`
  - Reboot

---

## Shared Usage

### Multiple Applications Sharing One Installation

**Safe and recommended!** The library is designed for this:

- All apps by the same user connect to the same socket: `/tmp/mss_<username>.socket`
- Only **one payload instance** runs in Dock.app (shared by all apps)
- Very efficient - no conflicts between apps

**Benefits:**
- Single installation for all apps
- Lower memory overhead
- Simplified user experience

**Considerations:**
- Apps should check version compatibility via `mss_handshake()`
- If one app uninstalls, all apps are affected
- Apps should handle connection loss gracefully

### Version Compatibility

Check payload version at runtime:

```c
const char *version;
uint32_t capabilities;

if (mss_handshake(ctx, &capabilities, &version) == MSS_SUCCESS) {
    printf("Payload version: %s\n", version);
    printf("Capabilities: 0x%x\n", capabilities);

    // Check if compatible with minimum required version
    if (strcmp(version, MSS_VERSION) != 0) {
        fprintf(stderr, "Warning: Payload version (%s) differs from client (%s)\n",
                version, MSS_VERSION);
    }
}
```

---

## Troubleshooting Installation

### Users Report "Root privileges required"

**Solution:** Must use `sudo`:
```bash
sudo mss load
```

### "SIP must be disabled"

**Solution:**
1. Reboot and hold ⌘R (Recovery Mode)
2. Utilities → Terminal
3. Run: `csrutil enable --without fs --without debug`
4. Reboot

Verify:
```bash
csrutil status
# Should show: enabled (with filesystem and debugging restrictions disabled)
```

### ARM64: Process killed (exit code 137)

**Solution:** Missing boot argument
```bash
sudo nvram boot-args="-arm64e_preview_abi"
sudo reboot
```

Verify:
```bash
nvram boot-args | grep arm64e_preview_abi
```

### Homebrew Installation Issues

**Formula not found:**
```bash
# Make sure to tap the repository first
brew tap ryanthedev/mss
brew install mss
```

**Build failures:**
- Ensure Xcode Command Line Tools: `xcode-select --install`
- Check macOS version: `sw_vers` (need Big Sur 11.0+)

---

## Support and Documentation

- **Swift Integration:** See [SWIFT_INTEGRATION.md](SWIFT_INTEGRATION.md)
- **Architecture Details:** See [CLAUDE.md](CLAUDE.md)
- **API Reference:** See `include/mss.h`
- **Issues:** https://github.com/ryanthedev/mss/issues
- **License:** MIT (see [LICENSE](LICENSE))

---

## Quick Reference

### For Maintainers

```bash
# Create release (GitHub Actions workflow handles everything)
# Just trigger the workflow via GitHub UI or:
gh workflow run release.yml

# Or manually:
make clean && make dist
git tag vX.Y.Z
git push --tags
gh release create vX.Y.Z mss-X.Y.Z.tar.gz

# Note: Homebrew tap is updated automatically by GitHub Actions
```

### For Users

```bash
# Install
brew tap ryanthedev/mss
brew install mss

# Load scripting addition
sudo mss load

# Verify
mss status
```

### For Developers

```bash
# Build against system library
gcc myapp.c $(pkg-config --cflags --libs mss) -o myapp

# Or in code:
#include <mss.h>
mss_context *ctx = mss_create(NULL);
```
