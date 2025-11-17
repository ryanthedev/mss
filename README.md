# mss - macOS Scripting Addition Library

A lightweight C library for programmatic window and space management on macOS through private SkyLight APIs.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-11.0+-blue.svg)](https://www.apple.com/macos/)

## Overview
Yabai and Aerospace built great apps. I just want something different. I want space manipulation while I still can have it.

So I ripped this out of yabai.
Based on the [yabai scripting addition](https://github.com/koekeishiya/yabai) by Åsmund Vikane.

- **Window Operations:** Move, resize, set opacity, change layers, focus, minimize
- **Window Queries:** Get frame, opacity, layer, sticky state, minimized state
- **Space Management:** Create, destroy, focus, and move spaces between displays
- **Display Queries:** Get display count and list of displays

## Quick Start

### Installation
```bash
# Direct from GitHub
brew install ryanthedev/mss/Formula/mss.rb

# Or tap repo first
brew tap ryanthedev/mss
brew install mss
```

**From source:**
```bash
git clone https://github.com/ryanthedev/mss.git
cd mss
make
sudo make install
```

### One-Time Setup (Requires Root + SIP Disabled)

**⚠️ Important:** The scripting addition requires system protections to be disabled.

**1. Disable SIP:**
- Boot to Recovery Mode (⌘R at startup)
- Open Terminal
- Run: `csrutil enable --without fs --without debug`
- Reboot

**2. ARM64 Macs only:**
```bash
sudo nvram boot-args="-arm64e_preview_abi"
sudo reboot
```

**3. Install and load scripting addition:**
```bash
sudo mss check    # Verify requirements
sudo mss load     # Install into Dock.app
```

### Usage Example

**C:**
```c
#include <mss.h>

int main() {
    // Create context
    mss_context *ctx = mss_create(NULL);

    // Check if payload is loaded
    uint32_t caps;
    const char *version;
    if (mss_handshake(ctx, &caps, &version) != MSS_SUCCESS) {
        fprintf(stderr, "Payload not loaded. Run: sudo mss load\n");
        return 1;
    }

    printf("mss version: %s\n", version);

    // Move window
    uint32_t window_id = 12345;  // From Accessibility API or CGWindowList
    mss_window_move(ctx, window_id, 100, 100);

    // Set opacity
    mss_window_set_opacity(ctx, window_id, 0.8);

    // Make sticky (visible on all spaces)
    mss_window_set_sticky(ctx, window_id, true);

    // Query window
    float opacity;
    mss_window_get_opacity(ctx, window_id, &opacity);
    printf("Window opacity: %.2f\n", opacity);

    // Cleanup
    mss_destroy(ctx);
    return 0;
}
```

**Build:**
```bash
# With pkg-config
gcc myapp.c $(pkg-config --cflags --libs mss) -o myapp

# Or manually
gcc myapp.c -I/usr/local/include/mss -L/usr/local/lib -lmss \
    -framework Cocoa -framework CoreGraphics -o myapp
```

**Swift:**

See [SWIFT_INTEGRATION.md](SWIFT_INTEGRATION.md) for complete Swift integration guide.

## Features

### Window Management
- **Position:** Move windows to absolute coordinates
- **Size:** Resize and set complete frame (position + size)
- **Opacity:** Set instantly or fade over duration
- **Layers:** Below, normal, or above standard window level
- **Properties:** Sticky (all spaces), shadow, focus
- **State:** Minimize, unminimize, check minimized state
- **Ordering:** Order relative to other windows
- **Spaces:** Move windows to specific spaces

### Space Management
- **Create/Destroy:** Add or remove spaces on displays
- **Focus:** Switch to a specific space
- **Move:** Transfer spaces between displays

### Display Queries
- **Count:** Get number of displays
- **List:** Get array of display IDs

### Query Operations
All window properties can be queried:
- Get current opacity, frame, layer, sticky state
- Check if window is minimized

## Architecture

The library uses a three-component architecture:

1. **Client Library** (`libmss.a`) - Links with your application
2. **Payload** - Injected into Dock.app, executes operations
3. **Loader** - Performs the injection

Communication happens via Unix socket (`/tmp/mss_<username>.socket`). The payload and loader binaries are embedded inside `libmss.a` and extracted during installation.

**Key insight:** Multiple applications can share the same payload instance - only one installation needed per user.

## Documentation

- **[SWIFT_INTEGRATION.md](SWIFT_INTEGRATION.md)** - Complete Swift integration guide with examples
- **[DISTRIBUTION.md](DISTRIBUTION.md)** - Creating releases, Homebrew distribution, installation
- **[CLAUDE.md](CLAUDE.md)** - Architecture details and development guide
- **[include/mss.h](include/mss.h)** - Complete API reference
- **[tests/TEST_RESULTS.md](tests/TEST_RESULTS.md)** - Architecture requirements analysis

## System Requirements

### Building
- macOS 11.0+ (Big Sur or later)
- Xcode Command Line Tools
- No special privileges required

### Runtime
- **Linking library:** No requirements
- **Loading scripting addition:**
  - Root privileges (`sudo`)
  - SIP partially disabled (filesystem + debugging restrictions)
  - ARM64: boot argument `-arm64e_preview_abi`

## Security Considerations

**⚠️ This library requires disabling system protections:**

- Injects code into system process (Dock.app)
- Uses private SkyLight APIs
- Requires SIP filesystem and debugging protections disabled
- Not suitable for App Store distribution

**Appropriate for:**
- Developer tools
- Power user applications
- Window management utilities
- Internal tools

**Not appropriate for:**
- Consumer applications
- App Store apps
- Sandboxed applications

## Compatibility

- **macOS:** 11.0+ (Big Sur, Monterey, Ventura, Sonoma, Sequoia)
- **Architectures:** x86_64, arm64
- **Languages:** C, Objective-C, Swift (via bridging)

The library includes runtime detection for macOS versions and adjusts API usage accordingly.

## License

MIT License - see [LICENSE](LICENSE) file.

Original yabai scripting addition:
- Copyright © 2019 Åsmund Vikane
- Copyright © 2025 mss contributors


## Acknowledgments

Based on the [yabai scripting addition](https://github.com/koekeishiya/yabai) by Åsmund Vikane. Special thanks to the yabai project for pioneering this approach to macOS window management.

## Related Projects

- [yabai](https://github.com/koekeishiya/yabai) - Tiling window manager for macOS

---

![Version](https://img.shields.io/github/v/release/ryanthedev/mss)

**Repository:** https://github.com/ryanthedev/mss
