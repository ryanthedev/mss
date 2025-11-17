# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**mss** (macOS Scripting addition library) is a C library that provides window and space management capabilities on macOS through a scripting addition (OSAX) that injects into Dock.app. It allows applications to control window opacity, position, layer levels, and manage macOS Spaces programmatically.

Based on yabai's scripting addition implementation, this library exposes low-level SkyLight APIs for window management without requiring a full window manager.

## Build Commands

### Basic Build
```bash
make              # Build static library (lib/libmss.a)
make install      # Install to /usr/local (requires sudo)
make cli          # Build CLI installer tool (build/mss)
make clean        # Remove build artifacts
```

### Testing
```bash
sudo ./build/mss check      # Validate system requirements
sudo ./build/mss load       # Install and load SA into Dock
sudo ./build/mss test       # Test if SA is working
sudo ./build/mss status     # Show installation status
sudo ./build/mss uninstall  # Remove SA completely
```

## Architecture

### Three-Component System

1. **Client Library** (`src/client.m` → `lib/libmss.a`)
   - Public API that applications link against
   - Communicates with payload via Unix socket (`/tmp/mss_<user>.socket`)
   - Built for `x86_64 arm64` (regular architectures)
   - No special privileges required to compile/link

2. **Payload** (`src/payload.m` → injected into Dock.app)
   - Shared library loaded into Dock process
   - Performs actual window/space operations via SkyLight APIs
   - Runs socket server to receive commands from clients
   - Built for `x86_64 arm64e` (requires pointer authentication for injection)
   - Uses runtime introspection to find private Dock APIs on different macOS versions

3. **Loader** (`src/loader.m` → executed by macOS when SA loads)
   - Executable that injects payload into Dock.app
   - Uses Mach thread injection with architecture-specific shellcode
   - Built for `x86_64 arm64e` (must match Dock's architecture)
   - Signed with entitlements for `task_for_pid` access

### Build Process Flow

The Makefile implements a multi-stage build:
1. Compile payload as shared library → `build/payload`
2. Compile loader as executable → `build/loader`
3. Convert both binaries to C arrays using `xxd`:
   - `build/payload_bin.c` (embedded payload)
   - `build/loader_bin.c` (embedded loader)
4. Compile client library with embedded binaries → `build/client.o`
5. Archive into static library → `lib/libmss.a`

The embedded binaries are written to disk during installation via `mss_install()`.

### Communication Protocol

Client-payload communication uses a binary protocol over Unix sockets:
- **Opcodes**: Defined in `src/common.h` (`enum sa_opcode`)
- **Message format**: `[opcode:1][params:N]`
- **Handshake**: Client sends `SA_OPCODE_HANDSHAKE`, payload responds with capabilities and version
- **Capabilities**: Bitflags (`MSS_CAP_*`) indicate which features are available based on macOS version

### Architecture-Specific Code

The payload includes platform-specific implementations:
- `src/arm64_payload.m`: ARM64-specific API addresses and pointer authentication
- `src/x64_payload.m`: x86_64-specific API addresses
- Runtime selection via `#ifdef __arm64__` / `#ifdef __x86_64__`

Function pointer discovery is performed at runtime using Objective-C runtime introspection to locate private Dock methods across macOS versions.

## System Requirements

### For Development (building/linking)
- macOS 11.0+ (Big Sur or later)
- Xcode Command Line Tools

### For SA Loading (runtime injection)
- Root privileges (`sudo`)
- SIP partially disabled:
  - Filesystem Protections: disabled (`csrutil enable --without fs`)
  - Debugging Restrictions: disabled (`csrutil enable --without debug`)
- ARM64 only: Boot argument `sudo nvram boot-args="-arm64e_preview_abi"` (+ reboot)

**Note**: The library can be built and linked without these requirements. They're only needed when actually loading the SA into Dock.

## Key Implementation Details

### Version Synchronization
Version is defined in **one place** (single source of truth):
- `include/mss_types.h`: `#define MSS_VERSION "0.0.1"`
- `src/common.h`: `OSAX_VERSION` is injected via `-DOSAX_VERSION` compiler flag (extracts from `MSS_VERSION`)

### Installation Paths
- SA bundle: `/Library/ScriptingAdditions/mss.osax/`
- Loader: `/Library/ScriptingAdditions/mss.osax/Contents/MacOS/loader`
- Payload: `/Library/ScriptingAdditions/mss.osax/Contents/Resources/payload.bundle/Contents/MacOS/payload`

### Error Handling
Functions return:
- `int`: Status codes (`MSS_SUCCESS`, `MSS_ERROR_*` from `mss_types.h`)
- `bool`: Success/failure for operations

Use `mss_set_log_callback()` to capture diagnostic messages during development.

### Thread Safety
The payload uses pthread mutexes to protect the window fade table. Client functions are not thread-safe; callers should synchronize access to `mss_context`.

## Common Gotchas

1. **Architecture Mismatch**: Library must be `arm64` (regular), not `arm64e`, for applications that don't inject. Only payload/loader need `arm64e`.

2. **SIGKILL on ARM64**: If binaries are killed immediately, ensure the boot argument is set (see TEST_RESULTS.md).

3. **Socket Permissions**: Socket is created with the user's permissions. If Dock runs as different user, connection will fail.

4. **Version Mismatches**: Client and payload must have matching versions. Handshake validates this.

5. **macOS Updates**: Private APIs may change between macOS versions. The payload includes version detection (`macOSSequoia`) and fallback logic.

## Reference Documentation

- `include/mss.h`: Complete public API documentation
- `include/mss_types.h`: Type definitions, error codes, constants
- `tests/TEST_RESULTS.md`: Detailed analysis of architecture requirements and SIGKILL root cause
- Original inspiration: [yabai scripting addition](https://github.com/koekeishiya/yabai)
