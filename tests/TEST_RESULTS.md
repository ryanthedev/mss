# Incremental Testing Results: SIGKILL Root Cause

## Summary

**ROOT CAUSE IDENTIFIED**: The library (libmacos-sa.a) is built as `x86_64 arm64e`, but the system needs `x86_64 arm64` (regular ARM64) for binaries that don't inject into system processes.

## Test Results

### Test 1: Minimal Hello World
- **Build**: `clang test1.c -o test1`
- **Result**: ✅ SUCCESS
- **Conclusion**: Basic compilation works

### Test 2: With Frameworks
- **Build**: Added `-framework Cocoa -framework CoreGraphics -framework SkyLight -framework Carbon`
- **Result**: ✅ SUCCESS
- **Conclusion**: Framework linking works

### Test 3: Linked Against libmacos-sa (No Function Calls)
- **Build**: Added `-L../lib -lmacos-sa`
- **Result**: ⚠️ WARNING + SUCCESS
- **Warning**: `ld: warning: ignoring file '../lib/libmacos-sa.a': fat file missing arch 'arm64', file has 'x86_64,arm64e'`
- **Conclusion**: Links but ignores the library (no symbols used)

### Test 4: Include Header (No Function Calls)
- **Build**: Added `-I../include`, includes `macos_sa.h`
- **Result**: ⚠️ WARNING + SUCCESS
- **Warning**: Same linker warning about missing arm64
- **Conclusion**: Header includes work, but library still ignored

### Test 5: Call Library Functions

#### Test 5a: Default Build (arm64)
- **Build**: Calls `macos_sa_create()`, `macos_sa_get_socket_path()`, `macos_sa_destroy()`
- **Result**: ❌ LINK ERROR
```
Undefined symbols for architecture arm64:
  "_macos_sa_create"
  "_macos_sa_destroy"
  "_macos_sa_get_socket_path"
```
- **Conclusion**: Library has no arm64 symbols

#### Test 5b: Force x86_64 Build
- **Build**: Added `-arch x86_64`
- **Result**: ✅ SUCCESS
```
Test 5: Creating context...
  Context created successfully: 0x7faadf808200
  Socket path: /tmp/libmacos-sa_r.socket
Test 5: SUCCESS
```
- **Conclusion**: Works under Rosetta translation

#### Test 5c: Force arm64e Build
- **Build**: Added `-arch arm64e`
- **Result**: ❌ SIGKILL (Exit code 137)
- **Conclusion**: arm64e binaries are killed by macOS without boot-arg

## Comparison with yabai

```bash
$ lipo -info /opt/homebrew/bin/yabai
Architectures in the fat file: /opt/homebrew/bin/yabai are: x86_64 arm64
```

**Key Finding**: yabai main binary is `arm64` (regular), NOT `arm64e`

## Analysis

### Why arm64e Was Used
The Makefile specifies:
```makefile
ARCHS := x86_64 arm64e
```

This builds ALL components (library, example, loader, payload) as arm64e.

### Why arm64e is Needed (For Payload Only)
- Dock.app on Apple Silicon is arm64e
- To inject code into Dock.app, the payload must be arm64e
- **However**: The main executable does NOT need to be arm64e

### Why arm64e Causes SIGKILL
- macOS refuses to run third-party arm64e binaries without `-arm64e_preview_abi` boot argument
- This is a security measure to prevent abuse of pointer authentication
- Boot argument is set via `sudo nvram boot-args="-arm64e_preview_abi"`

## The Fix

### Option 1: Set Boot Argument (Not Recommended)
```bash
sudo nvram boot-args="-arm64e_preview_abi"
sudo reboot
```

**Downsides**:
- Requires reboot
- May conflict with other boot arguments
- Weakens system security
- Should not be required for normal use

### Option 2: Split Architecture Builds (RECOMMENDED)
Change Makefile to use:
- **Main library/example**: `x86_64 arm64` (regular)
- **Payload/loader**: `x86_64 arm64e` (for injection)

This matches yabai's approach:
| Component | yabai | libmacos-sa (current) | libmacos-sa (fixed) |
|-----------|-------|----------------------|---------------------|
| Main binary | arm64 | arm64e ❌ | arm64 ✅ |
| Payload | arm64e | arm64e ✅ | arm64e ✅ |
| Loader | arm64e | arm64e ✅ | arm64e ✅ |

## Implementation Plan

1. **Makefile Changes**:
   ```makefile
   # For main components (library, example)
   ARCHS := x86_64 arm64

   # For SA components (payload, loader)
   ARCHS_SA := x86_64 arm64e
   ```

2. **Update Build Targets**:
   - Client compilation: Use `ARCHS`
   - Payload compilation: Use `ARCHS_SA`
   - Loader compilation: Use `ARCHS_SA`
   - Example compilation: Use `ARCHS`

3. **Result**:
   - Library can be used without boot argument
   - Example runs without boot argument
   - Boot argument only needed when actually loading SA into Dock

## Benefits of Fix

1. **Better User Experience**: No boot argument required for development/testing
2. **Matches yabai**: Consistent with reference implementation
3. **Security**: Doesn't require weakening system protections unnecessarily
4. **Flexibility**: SA loading is optional, not required for all library features

## Files for Reference

- `test1.c` through `test5.c` - Incremental test programs
- `test5-x86` - Working x86_64 version
- `test5-arm64e` - Failing arm64e version (SIGKILL)
