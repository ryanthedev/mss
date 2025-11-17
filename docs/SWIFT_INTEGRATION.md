# Swift Integration Guide for mss Library

A comprehensive guide for Swift developers integrating the mss (macOS Scripting addition) library into their applications.

## Table of Contents

1. [Distribution Files](#1-distribution-files)
2. [Understanding Embedded Resources](#2-understanding-embedded-resources)
3. [Swift Project Setup](#3-swift-project-setup)
4. [Complete Developer Workflow](#4-complete-developer-workflow)
5. [Swift-Specific Considerations](#5-swift-specific-considerations)
6. [Installation Process Details](#6-installation-process-details)
7. [Complete Swift Example](#7-complete-swift-example)
8. [Distribution Strategy](#8-distribution-strategy)
9. [Troubleshooting](#9-troubleshooting)
10. [API Reference](#10-api-reference)

---

## 1. Distribution Files

### What You Need to Bundle

After building the mss library (`make` or `make install`), you need only **three files**:

```
lib/libmss.a              # Static library (~716KB, universal binary)
include/mss.h             # Main API header
include/mss_types.h       # Type definitions and constants
```

**That's it!** The library is completely self-contained. All runtime components are embedded within `libmss.a`.

### What You DON'T Need

- ❌ No separate payload binary
- ❌ No separate loader binary
- ❌ No configuration files
- ❌ No additional resources

The payload and loader binaries are embedded as C byte arrays inside `libmss.a` and extracted automatically during installation.

---

## 2. Understanding Embedded Resources

### How It Works

The build process embeds two complete binaries into the static library:

1. **Payload** - A shared library (arm64e/x86_64) that gets injected into Dock.app
2. **Loader** - An executable (arm64e/x86_64) that performs the injection

**Build Process:**

```bash
# 1. Build payload and loader as separate binaries
make → build/payload    (shared library)
     → build/loader     (executable)

# 2. Convert binaries to C arrays using xxd
build/payload_bin.c:
  unsigned char __src_osax_payload[] = { 0xCF, 0xFA, 0xED, ... };
  unsigned int __src_osax_payload_len = 234567;

build/loader_bin.c:
  unsigned char __src_osax_loader[] = { 0xCF, 0xFA, 0xED, ... };
  unsigned int __src_osax_loader_len = 123456;

# 3. Compile client with embedded arrays (-include flags)
gcc client.m -include payload_bin.c -include loader_bin.c → client.o

# 4. Archive into static library
ar rcs libmss.a client.o
```

### Extraction During Installation

When `mss_install()` is called (requires root), the embedded binaries are written to disk:

```
/Library/ScriptingAdditions/mss.osax/
├── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── loader                    ← Extracted from __src_osax_loader[]
    └── Resources/
        └── payload.bundle/
            └── Contents/
                ├── Info.plist
                └── MacOS/
                    └── payload        ← Extracted from __src_osax_payload[]
```

**Key Point:** Your Swift app never needs to manage these files. The library handles everything.

---

## 3. Swift Project Setup

### Step 1: Add Library to Xcode

1. Drag `libmss.a` into your Xcode project
2. In Build Phases → "Link Binary With Libraries", ensure `libmss.a` is listed
3. Add the required system frameworks:
   - `Cocoa.framework`
   - `CoreGraphics.framework`

### Step 2: Create Bridging Header

Create `YourProject-Bridging-Header.h`:

```objective-c
#ifndef YourProject_Bridging_Header_h
#define YourProject_Bridging_Header_h

#import "mss.h"

#endif
```

Configure in Xcode:
- Build Settings → Swift Compiler - General → Objective-C Bridging Header
- Set to: `YourProject/YourProject-Bridging-Header.h`

### Step 3: Add Header Search Path

1. Copy `mss.h` and `mss_types.h` to your project (e.g., `YourProject/Libraries/mss/`)
2. Build Settings → Header Search Paths
3. Add: `$(SRCROOT)/YourProject/Libraries/mss`

### Step 4: Verify Setup

Create a test file:

```swift
import Foundation

let context = mss_create(nil)
if context != nil {
    print("mss library linked successfully!")
    mss_destroy(context)
} else {
    print("Failed to create context")
}
```

Build and run. If it compiles, you're set up correctly.

---

## 4. Complete Developer Workflow

### Phase 1: Link the Library (No Special Requirements)

**Who:** Any developer
**Privileges:** None
**When:** During development

```swift
import Foundation

class WindowManager {
    private var context: OpaquePointer?

    init?() {
        // Create context - works without any special privileges
        context = mss_create(nil)
        guard context != nil else { return nil }

        // Get socket path it will use
        if let path = mss_get_socket_path(context) {
            print("Socket: \(String(cString: path))")
            // Output: /tmp/mss_yourusername.socket
        }
    }

    deinit {
        if let ctx = context {
            mss_destroy(ctx)
        }
    }
}

// This works anywhere, anytime
let manager = WindowManager()
```

**At this stage:**
- ✅ Library is linked and callable
- ❌ Payload is not installed/loaded
- ❌ API calls will fail with connection errors

---

### Phase 2: One-Time Installation (Requires Root + SIP Disabled)

**Who:** End user with admin privileges
**Privileges:** Root (`sudo`)
**When:** First time setup on each machine

#### Prerequisites

**1. Root Privileges**
```bash
sudo /Applications/YourApp.app/Contents/MacOS/installer
```

**2. SIP Partially Disabled**

User must boot to Recovery Mode (⌘R at startup) and run:
```bash
csrutil enable --without fs --without debug
reboot
```

This disables:
- Filesystem Protections (needed to write to `/Library/ScriptingAdditions/`)
- Debugging Restrictions (needed for `task_for_pid` to inject into Dock)

**3. ARM64 Only: Boot Argument**

```bash
sudo nvram boot-args="-arm64e_preview_abi"
sudo reboot
```

Required because the payload is compiled as `arm64e` (with pointer authentication) to match Dock.app's architecture.

#### Installation Code

```swift
class Installer {
    private var context: OpaquePointer?

    init?() {
        context = mss_create(nil)
        guard context != nil else { return nil }
    }

    func checkRequirements() -> (Bool, String) {
        guard let ctx = context else {
            return (false, "Context creation failed")
        }

        let result = mss_check_requirements(ctx)

        switch result {
        case MSS_SUCCESS:
            return (true, "All requirements met")
        case MSS_ERROR_ROOT:
            return (false, "Root privileges required. Run with sudo.")
        default:
            // The log callback will show detailed error messages
            return (false, "Requirements not met. Check console output.")
        }
    }

    func install() -> Bool {
        guard let ctx = context else { return false }

        // This will:
        // 1. Validate root and SIP status
        // 2. Create /Library/ScriptingAdditions/mss.osax/
        // 3. Extract embedded payload and loader binaries
        // 4. Write Info.plist files
        // 5. Codesign both binaries
        // 6. Restart Dock.app

        let result = mss_install(ctx)
        return result == MSS_SUCCESS
    }

    func load() -> Bool {
        guard let ctx = context else { return false }

        // This will:
        // 1. Call install() if not already installed
        // 2. Wait for Dock to be ready
        // 3. Execute the loader to inject payload
        // 4. Payload starts socket server in Dock

        let result = mss_load(ctx)
        return result == MSS_SUCCESS
    }
}

// Usage in installer tool
mss_set_log_callback { message in
    if let msg = message {
        print("[mss] \(String(cString: msg))")
    }
}

let installer = Installer()

let (ok, message) = installer.checkRequirements()
if !ok {
    print("Error: \(message)")
    exit(1)
}

if installer.load() {
    print("Installation successful!")
} else {
    print("Installation failed")
    exit(1)
}
```

**What Happens:**

1. Library creates bundle structure in `/Library/ScriptingAdditions/`
2. Embedded payload and loader binaries are extracted from `libmss.a`
3. Binaries are codesigned
4. Dock.app is restarted (brief screen flicker)
5. Loader injects payload into restarted Dock process
6. Payload starts Unix socket server at `/tmp/mss_<username>.socket`

**Result:** Payload is now running inside Dock.app and ready to receive commands.

---

### Phase 3: Verify Installation

**Who:** Anyone
**Privileges:** None
**When:** After installation

```swift
func isPayloadLoaded() -> Bool {
    guard let ctx = context else { return false }

    var capabilities: UInt32 = 0
    var version: UnsafePointer<CChar>?

    let result = mss_handshake(ctx, &capabilities, &version)

    if result == MSS_SUCCESS {
        print("✓ Payload version: \(String(cString: version!))")
        print("✓ Capabilities: 0x\(String(capabilities, radix: 16))")
        return true
    } else {
        print("✗ Payload not responding")
        return false
    }
}

// Check before using API
if !isPayloadLoaded() {
    print("Please run installer first: sudo ./installer")
    exit(1)
}
```

**Capability Flags:**

```swift
let MSS_CAP_DOCK_SPACES: UInt32  = 0x01  // Dock Spaces support
let MSS_CAP_DPPM: UInt32         = 0x02  // Desktop Picture Manager
let MSS_CAP_ADD_SPACE: UInt32    = 0x04  // Can create spaces
let MSS_CAP_REM_SPACE: UInt32    = 0x08  // Can destroy spaces
let MSS_CAP_MOV_SPACE: UInt32    = 0x10  // Can move spaces
let MSS_CAP_SET_WINDOW: UInt32   = 0x20  // Window operations
let MSS_CAP_ANIM_TIME: UInt32    = 0x40  // Animation timing
let MSS_CAP_ALL: UInt32          = 0x7F  // All features
```

---

### Phase 4: Make API Calls (Normal Usage)

**Who:** Any process running as the user
**Privileges:** None
**When:** After payload is loaded

```swift
// Window operations - no special privileges needed!
let windowID: UInt32 = 12345  // From Accessibility API or CGWindowList

// Move window
mss_window_move(context, windowID, 100, 100)

// Set opacity (0.0 to 1.0)
mss_window_set_opacity(context, windowID, 0.8)

// Fade opacity over 0.5 seconds
mss_window_fade_opacity(context, windowID, 0.5, 0.5)

// Set layer level
mss_window_set_layer(context, windowID, MSS_LAYER_ABOVE)

// Make sticky (visible on all spaces)
mss_window_set_sticky(context, windowID, true)

// Remove shadow
mss_window_set_shadow(context, windowID, false)

// Resize
mss_window_resize(context, windowID, 800, 600)

// Set complete frame
mss_window_set_frame(context, windowID, 100, 100, 800, 600)

// Focus window
mss_window_focus(context, windowID)

// Minimize/restore
mss_window_minimize(context, windowID)
mss_window_unminimize(context, windowID)

// Query operations
var opacity: Float = 0
if mss_window_get_opacity(context, windowID, &opacity) {
    print("Current opacity: \(opacity)")
}

var x: Int32 = 0, y: Int32 = 0, width: Int32 = 0, height: Int32 = 0
if mss_window_get_frame(context, windowID, &x, &y, &width, &height) {
    print("Frame: \(x), \(y), \(width)×\(height)")
}

var sticky: Bool = false
mss_window_is_sticky(context, windowID, &sticky)

var minimized: Bool = false
mss_window_is_minimized(context, windowID, &minimized)

// Space operations
let spaceID: UInt64 = 67890  // From Spaces API

mss_space_create(context, spaceID)
mss_space_focus(context, spaceID)
mss_space_destroy(context, spaceID)

// Move window to space
mss_window_move_to_space(context, windowID, spaceID)

// Display queries
var displayCount: UInt32 = 0
if mss_display_get_count(context, &displayCount) == MSS_SUCCESS {
    print("Display count: \(displayCount)")

    var displays = [UInt32](repeating: 0, count: Int(displayCount))
    mss_display_get_list(context, &displays, displayCount)
    print("Displays: \(displays)")
}
```

**Communication Flow:**

```
Your App                          Dock.app
┌─────────────────┐              ┌──────────────────┐
│ mss_window_move()│              │ Payload Injected │
│       ↓         │              │       ↓          │
│ Format message: │              │ Socket Server    │
│ [len][opcode]   │─────────────→│ /tmp/mss_*.sock  │
│ [wid][x][y]     │  Unix Socket │       ↓          │
│                 │              │ SLSMoveWindow()  │
│       ↓         │←─────────────│ (SkyLight API)   │
│ Receive ACK     │  Response    │       ↓          │
│ Return true     │              │ Window moves     │
└─────────────────┘              └──────────────────┘
```

---

## 5. Swift-Specific Considerations

### Type Bridging

**Opaque Pointers:**
```swift
// C: mss_context*
// Swift: OpaquePointer?
var context: OpaquePointer?
```

**Enums:**
```swift
// C enums become Swift Int32 with named constants
let layer: mss_window_layer = MSS_LAYER_ABOVE
let order: mss_window_order = MSS_ORDER_ABOVE
```

**Structs:**
```swift
// C structs become Swift structs
var animation = mss_window_animation(wid: 123, proxy_wid: 456)
```

**C Strings:**
```swift
// const char* → UnsafePointer<CChar>?
if let path = mss_get_socket_path(context) {
    let swiftString = String(cString: path)
    // Do NOT free - library owns the memory
}
```

### Error Handling

**Pattern 1: Int Return Values**
```swift
let result = mss_install(context)

switch result {
case MSS_SUCCESS:
    print("Success")
case MSS_ERROR_ROOT:
    throw InstallError.needsRoot
case MSS_ERROR_CONNECTION:
    throw InstallError.payloadNotLoaded
case MSS_ERROR_INSTALL:
    throw InstallError.installationFailed
default:
    throw InstallError.unknown(result)
}
```

**Pattern 2: Bool Return Values**
```swift
if mss_window_move(context, windowID, 100, 100) {
    print("Window moved")
} else {
    print("Move failed - check window ID and payload status")
}
```

**Pattern 3: Output Parameters**
```swift
var opacity: Float = 0
guard mss_window_get_opacity(context, windowID, &opacity) else {
    throw WindowError.queryFailed
}
print("Opacity: \(opacity)")
```

### Thread Safety

⚠️ **The library is NOT thread-safe!** Multiple threads must not access the same `mss_context` concurrently.

**Solution: Serial Queue**

```swift
class WindowManager {
    private var context: OpaquePointer?
    private let queue = DispatchQueue(label: "com.yourapp.mss")

    func moveWindow(id: UInt32, x: Int32, y: Int32) -> Bool {
        queue.sync {
            guard let ctx = context else { return false }
            return mss_window_move(ctx, id, x, y)
        }
    }

    func setOpacity(id: UInt32, opacity: Float) -> Bool {
        queue.sync {
            guard let ctx = context else { return false }
            return mss_window_set_opacity(ctx, id, opacity)
        }
    }
}
```

**For async/await:**

```swift
func moveWindow(id: UInt32, x: Int32, y: Int32) async -> Bool {
    await withCheckedContinuation { continuation in
        queue.async {
            let result = mss_window_move(self.context, id, x, y)
            continuation.resume(returning: result)
        }
    }
}
```

### Logging Callbacks

```swift
// Global callback (set once at startup)
mss_set_log_callback { message in
    guard let msg = message else { return }
    NSLog("[mss] %@", String(cString: msg))
}

// Or with a custom logger
class Logger {
    static func setup() {
        mss_set_log_callback { message in
            guard let msg = message else { return }
            Logger.shared.log(String(cString: msg))
        }
    }
}
```

### Memory Management

```swift
class MSSManager {
    private var context: OpaquePointer?

    init?() {
        context = mss_create(nil)
        guard context != nil else { return nil }
    }

    deinit {
        // IMPORTANT: Always destroy context
        if let ctx = context {
            mss_destroy(ctx)
        }
    }
}
```

**What NOT to do:**
```swift
// ❌ Don't create multiple contexts unnecessarily
let ctx1 = mss_create(nil)
let ctx2 = mss_create(nil)  // Wasteful, use one context

// ❌ Don't forget to destroy
let ctx = mss_create(nil)
// ... use it ...
// (forgot mss_destroy - leaks socket and memory)

// ❌ Don't destroy twice
mss_destroy(context)
mss_destroy(context)  // Crash!
```

---

## 6. Installation Process Details

### Step-by-Step Technical Flow

When you call `mss_load(ctx)`, here's exactly what happens:

**1. Validation (`mss_check_requirements`)**

```c
// Check #1: Root privileges
if (geteuid() != 0) {
    log("Error: Root privileges required");
    return MSS_ERROR_ROOT;
}

// Check #2: SIP filesystem protections disabled
uint32_t config;
csr_get_active_config(&config);
if (!(config & CSR_ALLOW_UNRESTRICTED_FS)) {
    log("Error: SIP filesystem protections enabled");
    log("Boot to Recovery and run: csrutil enable --without fs");
    return MSS_ERROR_INSTALL;
}

// Check #3: SIP debugging restrictions disabled
if (!(config & CSR_ALLOW_TASK_FOR_PID)) {
    log("Error: SIP debugging restrictions enabled");
    log("Boot to Recovery and run: csrutil enable --without debug");
    return MSS_ERROR_INSTALL;
}

// Check #4 (ARM64 only): Boot argument
#ifdef __arm64__
char bootargs[1024];
sysctlbyname("kern.bootargs", bootargs, &len, NULL, 0);
if (!strstr(bootargs, "-arm64e_preview_abi")) {
    log("Error: Boot argument missing");
    log("Run: sudo nvram boot-args=\"-arm64e_preview_abi\"");
    log("Then reboot");
    return MSS_ERROR_INSTALL;
}
#endif
```

**2. Bundle Creation (`mss_install`)**

```c
// Create directory structure
mkdir("/Library/ScriptingAdditions/mss.osax/Contents/MacOS/");
mkdir("/Library/ScriptingAdditions/mss.osax/Contents/Resources/");
mkdir("/Library/ScriptingAdditions/mss.osax/Contents/Resources/payload.bundle/Contents/MacOS/");

// Write Info.plist files
write_file("/Library/ScriptingAdditions/mss.osax/Contents/Info.plist", plist_data);
write_file(".../payload.bundle/Contents/Info.plist", bundle_plist_data);
```

**3. Binary Extraction**

```c
// These symbols are embedded in libmss.a from payload_bin.c and loader_bin.c
extern unsigned char __src_osax_payload[];
extern unsigned int __src_osax_payload_len;
extern unsigned char __src_osax_loader[];
extern unsigned int __src_osax_loader_len;

// Write to disk
FILE *f = fopen("/Library/ScriptingAdditions/mss.osax/Contents/MacOS/loader", "wb");
fwrite(__src_osax_loader, 1, __src_osax_loader_len, f);
fclose(f);

f = fopen(".../payload.bundle/Contents/MacOS/payload", "wb");
fwrite(__src_osax_payload, 1, __src_osax_payload_len, f);
fclose(f);

// Make executable
chmod("/Library/.../loader", 0755);
chmod("/Library/.../payload", 0755);
```

**4. Code Signing**

```c
// Sign loader with entitlements (needs task_for_pid)
system("codesign -f -s - --entitlements loader.entitlements .../loader");

// Sign payload (no special entitlements)
system("codesign -f -s - .../payload");
```

The loader entitlements include `com.apple.security.cs.debugger` which allows `task_for_pid()`.

**5. Dock Restart**

```objc
NSArray *dock = [NSRunningApplication
    runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
[[dock firstObject] terminate];
```

macOS automatically:
- Restarts Dock.app
- Loads all `.osax` bundles from `/Library/ScriptingAdditions/`
- Executes `loader` binary from `mss.osax`

**6. Payload Injection (`loader` executable)**

```c
// Get Dock's process ID
NSArray *dockApps = [NSRunningApplication
    runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
pid_t dockPid = [[dockApps firstObject] processIdentifier];

// Get task port (requires SIP disabled + entitlements)
mach_port_t task;
task_for_pid(mach_task_self(), dockPid, &task);

// Allocate memory in Dock's address space
mach_vm_address_t remote_addr;
mach_vm_allocate(task, &remote_addr, page_size, VM_FLAGS_ANYWHERE);

// Write shellcode to Dock's memory
mach_vm_write(task, remote_addr, (vm_offset_t)shellcode, shellcode_size);

// Create thread in Dock that executes shellcode
thread_create_running(task, ARM_THREAD_STATE64, ...);
```

**7. Shellcode Execution (in Dock process)**

The shellcode (architecture-specific) does:

```c
// x86_64 and arm64e versions exist
pthread_create_from_mach_thread(..., dlopen_thread, ...);

void* dlopen_thread(void* arg) {
    dlopen("/Library/ScriptingAdditions/mss.osax/.../payload", RTLD_NOW);
    return NULL;
}
```

**8. Payload Initialization**

```c
// payload.m constructor (runs automatically on dlopen)
__attribute__((constructor))
static void initialize() {
    // Find Dock's internal objects via Objective-C runtime
    dock_spaces = find_dock_spaces_object();

    // Locate private function addresses
    add_space_fp = find_function_address("addSpace:");
    remove_space_fp = find_function_address("removeSpace:");

    // Start socket server
    pthread_create(&daemon_thread, NULL, daemon_thread_func, NULL);
}

void* daemon_thread_func(void* arg) {
    // Create Unix socket
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    bind(sockfd, "/tmp/mss_<username>.socket", ...);
    listen(sockfd, 10);

    // Accept connections and process commands
    while (1) {
        int client = accept(sockfd, ...);
        handle_client(client);  // Read opcode, execute, respond
    }
}
```

**9. Ready for Use**

The payload is now running inside Dock.app, listening on the socket. Your app can connect and send commands.

---

## 7. Complete Swift Example

### Production-Ready WindowManager Class

```swift
import Foundation
import CoreGraphics

enum MSSError: Error {
    case contextCreationFailed
    case payloadNotLoaded
    case notInstalled
    case needsRoot
    case sipNotDisabled
    case installationFailed
    case operationFailed
}

class WindowManager {
    // MARK: - Properties

    private var context: OpaquePointer?
    private let queue = DispatchQueue(label: "com.yourapp.mss", qos: .userInitiated)

    // MARK: - Initialization

    init() throws {
        // Set up logging
        Self.setupLogging()

        // Create context
        context = mss_create(nil)
        guard context != nil else {
            throw MSSError.contextCreationFailed
        }

        // Log socket path
        if let path = mss_get_socket_path(context) {
            NSLog("MSS socket: %@", String(cString: path))
        }
    }

    deinit {
        if let ctx = context {
            mss_destroy(ctx)
        }
    }

    private static func setupLogging() {
        mss_set_log_callback { message in
            guard let msg = message else { return }
            NSLog("[mss] %@", String(cString: msg))
        }
    }

    // MARK: - Installation Status

    func isLoaded() -> Bool {
        guard let ctx = context else { return false }

        var capabilities: UInt32 = 0
        var version: UnsafePointer<CChar>?

        return mss_handshake(ctx, &capabilities, &version) == MSS_SUCCESS
    }

    func getVersion() -> (version: String, capabilities: UInt32)? {
        guard let ctx = context else { return nil }

        var capabilities: UInt32 = 0
        var version: UnsafePointer<CChar>?

        guard mss_handshake(ctx, &capabilities, &version) == MSS_SUCCESS else {
            return nil
        }

        return (String(cString: version!), capabilities)
    }

    // MARK: - Installation (requires root)

    func checkRequirements() throws {
        guard let ctx = context else { throw MSSError.contextCreationFailed }

        let result = mss_check_requirements(ctx)

        switch result {
        case MSS_SUCCESS:
            return
        case MSS_ERROR_ROOT:
            throw MSSError.needsRoot
        default:
            throw MSSError.sipNotDisabled
        }
    }

    func install() throws {
        guard let ctx = context else { throw MSSError.contextCreationFailed }

        let result = mss_install(ctx)
        guard result == MSS_SUCCESS else {
            throw MSSError.installationFailed
        }
    }

    func load() throws {
        guard let ctx = context else { throw MSSError.contextCreationFailed }

        let result = mss_load(ctx)
        guard result == MSS_SUCCESS else {
            throw MSSError.installationFailed
        }
    }

    func uninstall() throws {
        guard let ctx = context else { throw MSSError.contextCreationFailed }

        let result = mss_uninstall(ctx)
        guard result == MSS_SUCCESS else {
            throw MSSError.operationFailed
        }
    }

    // MARK: - Window Operations

    func moveWindow(_ windowID: UInt32, to point: CGPoint) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_move(ctx, windowID, Int32(point.x), Int32(point.y)) else {
                throw MSSError.operationFailed
            }
        }
    }

    func resizeWindow(_ windowID: UInt32, to size: CGSize) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_resize(ctx, windowID, Int32(size.width), Int32(size.height)) else {
                throw MSSError.operationFailed
            }
        }
    }

    func setWindowFrame(_ windowID: UInt32, frame: CGRect) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_set_frame(ctx, windowID,
                                       Int32(frame.origin.x),
                                       Int32(frame.origin.y),
                                       Int32(frame.size.width),
                                       Int32(frame.size.height)) else {
                throw MSSError.operationFailed
            }
        }
    }

    func setWindowOpacity(_ windowID: UInt32, opacity: Float) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            let clampedOpacity = max(0.0, min(1.0, opacity))
            guard mss_window_set_opacity(ctx, windowID, clampedOpacity) else {
                throw MSSError.operationFailed
            }
        }
    }

    func fadeWindowOpacity(_ windowID: UInt32, to opacity: Float, duration: Float) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            let clampedOpacity = max(0.0, min(1.0, opacity))
            guard mss_window_fade_opacity(ctx, windowID, clampedOpacity, duration) else {
                throw MSSError.operationFailed
            }
        }
    }

    func setWindowLayer(_ windowID: UInt32, layer: mss_window_layer) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_set_layer(ctx, windowID, layer) else {
                throw MSSError.operationFailed
            }
        }
    }

    func setWindowSticky(_ windowID: UInt32, sticky: Bool) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_set_sticky(ctx, windowID, sticky) else {
                throw MSSError.operationFailed
            }
        }
    }

    func setWindowShadow(_ windowID: UInt32, enabled: Bool) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_set_shadow(ctx, windowID, enabled) else {
                throw MSSError.operationFailed
            }
        }
    }

    func focusWindow(_ windowID: UInt32) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_focus(ctx, windowID) else {
                throw MSSError.operationFailed
            }
        }
    }

    func minimizeWindow(_ windowID: UInt32) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_minimize(ctx, windowID) else {
                throw MSSError.operationFailed
            }
        }
    }

    func unminimizeWindow(_ windowID: UInt32) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_unminimize(ctx, windowID) else {
                throw MSSError.operationFailed
            }
        }
    }

    // MARK: - Window Queries

    func getWindowOpacity(_ windowID: UInt32) throws -> Float {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            var opacity: Float = 0
            guard mss_window_get_opacity(ctx, windowID, &opacity) else {
                throw MSSError.operationFailed
            }
            return opacity
        }
    }

    func getWindowFrame(_ windowID: UInt32) throws -> CGRect {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            var x: Int32 = 0, y: Int32 = 0
            var width: Int32 = 0, height: Int32 = 0

            guard mss_window_get_frame(ctx, windowID, &x, &y, &width, &height) else {
                throw MSSError.operationFailed
            }

            return CGRect(x: CGFloat(x), y: CGFloat(y),
                         width: CGFloat(width), height: CGFloat(height))
        }
    }

    func isWindowSticky(_ windowID: UInt32) throws -> Bool {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            var sticky: Bool = false
            guard mss_window_is_sticky(ctx, windowID, &sticky) else {
                throw MSSError.operationFailed
            }
            return sticky
        }
    }

    func isWindowMinimized(_ windowID: UInt32) throws -> Bool {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            var minimized: Bool = false
            guard mss_window_is_minimized(ctx, windowID, &minimized) else {
                throw MSSError.operationFailed
            }
            return minimized
        }
    }

    func getWindowLayer(_ windowID: UInt32) throws -> mss_window_layer {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            var layer: mss_window_layer = MSS_LAYER_NORMAL
            guard mss_window_get_layer(ctx, windowID, &layer) else {
                throw MSSError.operationFailed
            }
            return layer
        }
    }

    // MARK: - Space Operations

    func createSpace(on spaceID: UInt64) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_space_create(ctx, spaceID) else {
                throw MSSError.operationFailed
            }
        }
    }

    func destroySpace(_ spaceID: UInt64) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_space_destroy(ctx, spaceID) else {
                throw MSSError.operationFailed
            }
        }
    }

    func focusSpace(_ spaceID: UInt64) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_space_focus(ctx, spaceID) else {
                throw MSSError.operationFailed
            }
        }
    }

    func moveWindow(_ windowID: UInt32, toSpace spaceID: UInt64) throws {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            guard mss_window_move_to_space(ctx, windowID, spaceID) else {
                throw MSSError.operationFailed
            }
        }
    }

    // MARK: - Display Queries

    func getDisplayCount() throws -> Int {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }
            var count: UInt32 = 0
            guard mss_display_get_count(ctx, &count) == MSS_SUCCESS else {
                throw MSSError.operationFailed
            }
            return Int(count)
        }
    }

    func getDisplayList() throws -> [UInt32] {
        try queue.sync {
            guard let ctx = context else { throw MSSError.contextCreationFailed }

            var count: UInt32 = 0
            guard mss_display_get_count(ctx, &count) == MSS_SUCCESS else {
                throw MSSError.operationFailed
            }

            var displays = [UInt32](repeating: 0, count: Int(count))
            guard mss_display_get_list(ctx, &displays, count) == MSS_SUCCESS else {
                throw MSSError.operationFailed
            }

            return displays
        }
    }
}
```

### Usage Example

```swift
// Main app
do {
    let manager = try WindowManager()

    // Check if loaded
    if !manager.isLoaded() {
        print("Payload not loaded. Please run installer:")
        print("  sudo /Applications/YourApp.app/Contents/MacOS/installer")
        exit(1)
    }

    // Get version info
    if let info = manager.getVersion() {
        print("MSS version: \(info.version)")
        print("Capabilities: 0x\(String(info.capabilities, radix: 16))")
    }

    // Get window ID from accessibility API
    let windowID: UInt32 = getActiveWindowID()

    // Perform operations
    try manager.setWindowOpacity(windowID, opacity: 0.8)
    try manager.moveWindow(windowID, to: CGPoint(x: 100, y: 100))
    try manager.setWindowSticky(windowID, sticky: true)

    // Query window
    let frame = try manager.getWindowFrame(windowID)
    print("Window frame: \(frame)")

    let opacity = try manager.getWindowOpacity(windowID)
    print("Window opacity: \(opacity)")

} catch MSSError.payloadNotLoaded {
    print("Payload not loaded - run installer")
} catch {
    print("Error: \(error)")
}
```

### Separate Installer Tool

```swift
// installer.swift - Separate command-line tool

import Foundation

func main() {
    do {
        let manager = try WindowManager()

        // Check requirements
        print("Checking requirements...")
        try manager.checkRequirements()
        print("✓ Requirements met")

        // Install and load
        print("Installing scripting addition...")
        try manager.load()

        // Verify
        if manager.isLoaded() {
            if let info = manager.getVersion() {
                print("✓ Installation successful")
                print("  Version: \(info.version)")
                print("  Capabilities: 0x\(String(info.capabilities, radix: 16))")
            }
        } else {
            print("✗ Installation failed - payload not responding")
            exit(1)
        }

    } catch MSSError.needsRoot {
        print("Error: Root privileges required")
        print("Run: sudo \(CommandLine.arguments[0])")
        exit(1)

    } catch MSSError.sipNotDisabled {
        print("Error: SIP must be partially disabled")
        print("")
        print("Boot to Recovery Mode (⌘R at startup) and run:")
        print("  csrutil enable --without fs --without debug")
        print("  reboot")
        #if arch(arm64)
        print("")
        print("On ARM64, also set boot argument:")
        print("  nvram boot-args=\"-arm64e_preview_abi\"")
        print("  reboot")
        #endif
        exit(1)

    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

main()
```

---

## 8. Distribution Strategy

### Recommended Approach

**Option 1: Embed in App Bundle**

```
YourApp.app/
├── Contents/
    ├── MacOS/
    │   ├── YourApp              (main executable)
    │   └── installer            (separate tool with libmss.a linked)
    ├── Frameworks/
    │   ├── libmss.a
    │   ├── mss.h
    │   └── mss_types.h
    └── Info.plist
```

User workflow:
1. Download and launch YourApp.app
2. App detects payload not loaded
3. App shows instructions: "Run installer to enable advanced features"
4. User runs: `sudo /Applications/YourApp.app/Contents/MacOS/installer`
5. Installer installs and loads payload
6. User relaunches app, features now work

**Option 2: Separate Installer App**

```
YourApp-Installer.app          (handles installation)
YourApp.app                    (main app, links libmss.a)
```

User workflow:
1. Download both apps
2. Run YourApp-Installer.app with sudo
3. Installer handles all setup
4. Launch YourApp.app normally

**Option 3: System Library Installation**

```bash
# During build/packaging
make install  # Installs to /usr/local/lib and /usr/local/include
```

Your app:
- Links against system-installed `/usr/local/lib/libmss.a`
- Includes headers from `/usr/local/include/mss/`
- First launch triggers installation if needed

### Code Signing Considerations

⚠️ **Cannot be App Store distributed** due to:
- Requires SIP disabled
- Injects code into system processes
- Uses private APIs
- Requires root privileges

For direct distribution:
- You can sign and notarize your main app
- Installer tool should be signed
- Library itself doesn't need special signing

### User Documentation

Provide clear documentation:

```markdown
# Installation Instructions

## Prerequisites

1. **Disable SIP** (System Integrity Protection)
   - Restart and hold ⌘R to enter Recovery Mode
   - Open Terminal from Utilities menu
   - Run: `csrutil enable --without fs --without debug`
   - Restart normally

2. **ARM64 Macs Only**: Set boot argument
   - Open Terminal
   - Run: `sudo nvram boot-args="-arm64e_preview_abi"`
   - Restart

## Installation

1. Run the installer:
   ```bash
   sudo /Applications/YourApp.app/Contents/MacOS/installer
   ```

2. Enter your password when prompted

3. Dock will restart (screen may flicker briefly)

4. Launch YourApp normally

## Troubleshooting

If you see "Payload not loaded":
- Ensure you completed all prerequisites
- Check Console.app for mss-related errors
- Try: `sudo /Applications/YourApp.app/Contents/MacOS/installer`

## Uninstalling

To remove the scripting addition:
```bash
sudo /Applications/YourApp.app/Contents/MacOS/installer uninstall
```
```

---

## 9. Troubleshooting

### Common Issues and Solutions

#### "Failed to create context"

**Cause:** Memory allocation failed
**Solution:** Check system resources, restart app

#### "Root privileges required"

**Cause:** Trying to install/load without sudo
**Solution:**
```bash
sudo /path/to/installer
```

#### "Failed to connect to socket" / "Payload not loaded"

**Cause:** Payload not running in Dock
**Check:**
```swift
if !manager.isLoaded() {
    print("Payload not loaded")
    // Run installer
}
```

**Solution:**
```bash
sudo /path/to/installer load
```

#### "SIP must be disabled"

**Cause:** System Integrity Protection blocking installation
**Solution:**
1. Restart and hold ⌘R
2. Terminal → `csrutil enable --without fs --without debug`
3. Restart normally

Verify:
```bash
csrutil status
# Should show: enabled (with filesystem and debugging restrictions disabled)
```

#### ARM64: Process killed immediately (SIGKILL exit code 137)

**Cause:** Missing boot argument for arm64e binaries
**Solution:**
```bash
sudo nvram boot-args="-arm64e_preview_abi"
sudo reboot
```

Verify:
```bash
nvram boot-args
# Should include: -arm64e_preview_abi
```

**Technical Details:** See `tests/TEST_RESULTS.md` in repository for complete analysis.

#### "Version mismatch"

**Cause:** Client library version doesn't match payload version
**Check versions:**
- Single source: `MSS_VERSION` in `mss_types.h` (e.g., "0.0.1")
- Payload version is automatically synced via build system (injected as `OSAX_VERSION` during compilation)

**Solution:** Rebuild library and reinstall:
```bash
make clean && make
sudo make install
sudo /path/to/installer load
```

#### "Operation failed" on specific API calls

**Cause:** Various issues
**Debug:**
```swift
// Enable logging
mss_set_log_callback { message in
    if let msg = message {
        print("[mss] \(String(cString: msg))")
    }
}

// Try operation
if !mss_window_move(ctx, windowID, 100, 100) {
    // Check logs for details
}
```

**Common causes:**
- Invalid window ID → Use Accessibility API to get valid IDs
- Window doesn't exist → Check with `CGWindowListCopyWindowInfo`
- Permission issue → Enable Accessibility permissions for your app

#### Dock crashes after installation

**Cause:** Usually incompatible macOS version
**Check Console.app:**
```
Filter: process:Dock
Look for: mss, payload, crash reports
```

**Solution:**
- Ensure macOS 11.0+ (Big Sur or later)
- Check for library updates
- Report issue with macOS version and crash log

#### Payload stops responding after macOS update

**Cause:** Private APIs changed
**Solution:**
- Check for library updates
- The payload includes macOS version detection
- May need rebuild for new APIs

#### "Connection refused" immediately

**Cause:** Socket path issue
**Check:**
```swift
if let path = mss_get_socket_path(context) {
    print("Socket: \(String(cString: path))")
    // Should be: /tmp/mss_<username>.socket
}

// Verify socket exists
FileManager.default.fileExists(atPath: socketPath)
```

**Solution:**
- Reload payload: `sudo /path/to/installer load`
- Check socket permissions
- Ensure username matches

---

## 10. API Reference

### Context Management

```swift
// Create context
func mss_create(_ socket_path: UnsafePointer<CChar>?) -> OpaquePointer?
// Pass nil for default (/tmp/mss_<user>.socket)

// Destroy context
func mss_destroy(_ ctx: OpaquePointer?)

// Get socket path
func mss_get_socket_path(_ ctx: OpaquePointer?) -> UnsafePointer<CChar>?

// Test connection and get capabilities
func mss_handshake(_ ctx: OpaquePointer?,
                   _ capabilities: UnsafeMutablePointer<UInt32>?,
                   _ version: UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32

// Set logging callback
func mss_set_log_callback(_ callback: (@convention(c) (UnsafePointer<CChar>?) -> Void)?)
```

### Installation (requires root)

```swift
// Check system requirements
func mss_check_requirements(_ ctx: OpaquePointer?) -> Int32
// Returns: MSS_SUCCESS, MSS_ERROR_ROOT, or other error

// Install scripting addition
func mss_install(_ ctx: OpaquePointer?) -> Int32

// Load payload into Dock (auto-installs if needed)
func mss_load(_ ctx: OpaquePointer?) -> Int32

// Uninstall scripting addition
func mss_uninstall(_ ctx: OpaquePointer?) -> Int32
```

### Window Operations

```swift
// Position
func mss_window_move(_ ctx: OpaquePointer?, _ wid: UInt32, _ x: Int32, _ y: Int32) -> Bool

// Size
func mss_window_resize(_ ctx: OpaquePointer?, _ wid: UInt32, _ width: Int32, _ height: Int32) -> Bool

// Frame (position + size)
func mss_window_set_frame(_ ctx: OpaquePointer?, _ wid: UInt32,
                          _ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) -> Bool

// Opacity
func mss_window_set_opacity(_ ctx: OpaquePointer?, _ wid: UInt32, _ opacity: Float) -> Bool
func mss_window_fade_opacity(_ ctx: OpaquePointer?, _ wid: UInt32,
                             _ opacity: Float, _ duration: Float) -> Bool

// Layer level
func mss_window_set_layer(_ ctx: OpaquePointer?, _ wid: UInt32,
                          _ layer: mss_window_layer) -> Bool
// Layers: MSS_LAYER_BELOW (3), MSS_LAYER_NORMAL (4), MSS_LAYER_ABOVE (5)

// Sticky (visible on all spaces)
func mss_window_set_sticky(_ ctx: OpaquePointer?, _ wid: UInt32, _ sticky: Bool) -> Bool

// Shadow
func mss_window_set_shadow(_ ctx: OpaquePointer?, _ wid: UInt32, _ shadow: Bool) -> Bool

// Focus
func mss_window_focus(_ ctx: OpaquePointer?, _ wid: UInt32) -> Bool

// Minimize/restore
func mss_window_minimize(_ ctx: OpaquePointer?, _ wid: UInt32) -> Bool
func mss_window_unminimize(_ ctx: OpaquePointer?, _ wid: UInt32) -> Bool

// Order relative to another window
func mss_window_order(_ ctx: OpaquePointer?, _ wid: UInt32,
                      _ order: mss_window_order, _ relative_wid: UInt32) -> Bool
// Orders: MSS_ORDER_OUT (0), MSS_ORDER_ABOVE (1), MSS_ORDER_BELOW (-1)

// Scale (picture-in-picture effect)
func mss_window_scale(_ ctx: OpaquePointer?, _ wid: UInt32,
                      _ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bool

// Move to space
func mss_window_move_to_space(_ ctx: OpaquePointer?, _ wid: UInt32, _ sid: UInt64) -> Bool

// Move multiple windows to space
func mss_window_list_move_to_space(_ ctx: OpaquePointer?,
                                   _ window_list: UnsafeMutablePointer<UInt32>?,
                                   _ count: Int32, _ sid: UInt64) -> Bool
```

### Window Queries

```swift
// Get opacity
func mss_window_get_opacity(_ ctx: OpaquePointer?, _ wid: UInt32,
                            _ opacity: UnsafeMutablePointer<Float>?) -> Bool

// Get frame
func mss_window_get_frame(_ ctx: OpaquePointer?, _ wid: UInt32,
                          _ x: UnsafeMutablePointer<Int32>?,
                          _ y: UnsafeMutablePointer<Int32>?,
                          _ width: UnsafeMutablePointer<Int32>?,
                          _ height: UnsafeMutablePointer<Int32>?) -> Bool

// Check if sticky
func mss_window_is_sticky(_ ctx: OpaquePointer?, _ wid: UInt32,
                          _ sticky: UnsafeMutablePointer<Bool>?) -> Bool

// Get layer
func mss_window_get_layer(_ ctx: OpaquePointer?, _ wid: UInt32,
                          _ layer: UnsafeMutablePointer<mss_window_layer>?) -> Bool

// Check if minimized
func mss_window_is_minimized(_ ctx: OpaquePointer?, _ wid: UInt32,
                             _ result: UnsafeMutablePointer<Bool>?) -> Bool
```

### Space Operations

```swift
// Create space on display
func mss_space_create(_ ctx: OpaquePointer?, _ sid: UInt64) -> Bool

// Destroy space
func mss_space_destroy(_ ctx: OpaquePointer?, _ sid: UInt64) -> Bool

// Focus (switch to) space
func mss_space_focus(_ ctx: OpaquePointer?, _ sid: UInt64) -> Bool

// Move space to another display
func mss_space_move(_ ctx: OpaquePointer?,
                    _ src_sid: UInt64, _ dst_sid: UInt64,
                    _ src_prev_sid: UInt64, _ focus: Bool) -> Bool
```

### Display Queries

```swift
// Get display count
func mss_display_get_count(_ ctx: OpaquePointer?,
                           _ count: UnsafeMutablePointer<UInt32>?) -> Int32

// Get display IDs
func mss_display_get_list(_ ctx: OpaquePointer?,
                          _ displays: UnsafeMutablePointer<UInt32>?,
                          _ max_count: Int) -> Int32
```

### Error Codes

```swift
let MSS_SUCCESS: Int32           = 0   // Success
let MSS_ERROR_INIT: Int32        = -1  // Initialization failed
let MSS_ERROR_ROOT: Int32        = -2  // Root privileges required
let MSS_ERROR_CONNECTION: Int32  = -3  // Connection to payload failed
let MSS_ERROR_INSTALL: Int32     = -4  // Installation failed
let MSS_ERROR_LOAD: Int32        = -5  // Loading failed
let MSS_ERROR_NOT_LOADED: Int32  = -6  // Payload not loaded
let MSS_ERROR_OPERATION: Int32   = -7  // Operation failed
let MSS_ERROR_INVALID_ARG: Int32 = -8  // Invalid argument
```

### Capability Flags

```swift
let MSS_CAP_DOCK_SPACES: UInt32  = 0x01  // Dock Spaces support
let MSS_CAP_DPPM: UInt32         = 0x02  // Desktop Picture Manager
let MSS_CAP_ADD_SPACE: UInt32    = 0x04  // Can create spaces
let MSS_CAP_REM_SPACE: UInt32    = 0x08  // Can destroy spaces
let MSS_CAP_MOV_SPACE: UInt32    = 0x10  // Can move spaces
let MSS_CAP_SET_WINDOW: UInt32   = 0x20  // Window operations
let MSS_CAP_ANIM_TIME: UInt32    = 0x40  // Animation timing
let MSS_CAP_ALL: UInt32          = 0x7F  // All features available
```

---

## Additional Resources

- **Full API Documentation:** `include/mss.h`
- **Architecture Details:** `CLAUDE.md` in repository
- **Build System:** `Makefile`
- **CLI Reference:** `cli/cli.c`
- **Test Results:** `tests/TEST_RESULTS.md` (arm64e investigation)

---

## License

MIT License - See `LICENSE` file in repository.

Original yabai scripting addition by Åsmund Vikane.
