#include "../include/mss.h"
#include "../include/mss_types.h"
#include "common.h"
#include "util.h"

#include <Cocoa/Cocoa.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <pwd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <assert.h>
#include <sys/wait.h>
#include <sys/sysctl.h>

// External symbols for CSR check
extern int csr_get_active_config(uint32_t *config);
#define CSR_ALLOW_UNRESTRICTED_FS 0x02
#define CSR_ALLOW_TASK_FOR_PID    0x04

// External SkyLight functions
extern int SLSMainConnectionID(void);
extern int SLSWindowIsOrderedIn(int cid, uint32_t wid, uint8_t *ordered_in);

// Maximum path length
#define MAXLEN 4096

// Socket path format
#define SA_SOCKET_PATH_FMT "/tmp/mss_%s.socket"

// Global logging callback
static mss_log_callback g_log_callback = NULL;

// Helper to log messages
static void sa_log(const char *format, ...) __attribute__((format(printf, 1, 2)));
static void sa_log(const char *format, ...)
{
    if (g_log_callback) {
        char buffer[4096];
        va_list args;
        va_start(args, format);
        vsnprintf(buffer, sizeof(buffer), format, args);
        va_end(args);
        g_log_callback(buffer);
    }
}

// Context structure
struct mss_context {
    char socket_path[MAXLEN];
    int connection_id;  // SkyLight connection ID
};

// Plist contents for SA bundle
static char sa_plist[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\">\n"
    "<dict>\n"
    "<key>CFBundleDevelopmentRegion</key>\n"
    "<string>en</string>\n"
    "<key>CFBundleExecutable</key>\n"
    "<string>loader</string>\n"
    "<key>CFBundleIdentifier</key>\n"
    "<string>com.mss.osax</string>\n"
    "<key>CFBundleInfoDictionaryVersion</key>\n"
    "<string>6.0</string>\n"
    "<key>CFBundleName</key>\n"
    "<string>mss</string>\n"
    "<key>CFBundlePackageType</key>\n"
    "<string>osax</string>\n"
    "<key>CFBundleShortVersionString</key>\n"
    "<string>"OSAX_VERSION"</string>\n"
    "<key>CFBundleVersion</key>\n"
    "<string>"OSAX_VERSION"</string>\n"
    "<key>NSHumanReadableCopyright</key>\n"
    "<string>Copyright © 2019 Åsmund Vikane. All rights reserved.</string>\n"
    "<key>OSAXHandlers</key>\n"
    "<dict>\n"
    "</dict>\n"
    "</dict>\n"
    "</plist>";

static char sa_bundle_plist[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\">\n"
    "<dict>\n"
    "<key>CFBundleDevelopmentRegion</key>\n"
    "<string>en</string>\n"
    "<key>CFBundleExecutable</key>\n"
    "<string>payload</string>\n"
    "<key>CFBundleIdentifier</key>\n"
    "<string>com.mss.payload</string>\n"
    "<key>CFBundleInfoDictionaryVersion</key>\n"
    "<string>6.0</string>\n"
    "<key>CFBundleName</key>\n"
    "<string>payload</string>\n"
    "<key>CFBundlePackageType</key>\n"
    "<string>BNDL</string>\n"
    "<key>CFBundleShortVersionString</key>\n"
    "<string>"OSAX_VERSION"</string>\n"
    "<key>CFBundleVersion</key>\n"
    "<string>"OSAX_VERSION"</string>\n"
    "<key>NSHumanReadableCopyright</key>\n"
    "<string>Copyright © 2019 Åsmund Vikane. All rights reserved.</string>\n"
    "<key>NSPrincipalClass</key>\n"
    "<string></string>\n"
    "</dict>\n"
    "</plist>";

// External embedded binaries (will be linked from payload_bin.c and loader_bin.c)
extern unsigned char __src_osax_payload[];
extern unsigned int __src_osax_payload_len;
extern unsigned char __src_osax_loader[];
extern unsigned int __src_osax_loader_len;

// ============================================================================
// Internal helper functions
// ============================================================================

static bool sa_write_file(const char *buffer, unsigned int size, const char *file, const char *file_mode)
{
    FILE *handle = fopen(file, file_mode);
    if (!handle) return false;

    size_t bytes = fwrite(buffer, size, 1, handle);
    bool result = bytes == 1;
    fclose(handle);

    return result;
}

static bool sa_is_sip_friendly(void)
{
    uint32_t config = 0;
    csr_get_active_config(&config);

    if (!(config & CSR_ALLOW_UNRESTRICTED_FS)) return false;
    if (!(config & CSR_ALLOW_TASK_FOR_PID)) return false;

    return true;
}

static bool sa_is_installed(void)
{
    struct stat st;
    return stat("/Library/ScriptingAdditions/mss.osax", &st) == 0;
}

static int sa_validate_requirements(bool check_root)
{
    // 1. Check root privileges if requested
    if (check_root && !is_root()) {
        sa_log("ERROR: Root privileges required");
        sa_log("");
        sa_log("To fix:");
        sa_log("  Run this program with sudo:");
        sa_log("  $ sudo %s", getprogname());
        return MSS_ERROR_ROOT;
    }

    // 2. Check SIP configuration
    uint32_t config = 0;
    csr_get_active_config(&config);

    bool sip_fs_disabled = (config & CSR_ALLOW_UNRESTRICTED_FS);
    bool sip_debug_disabled = (config & CSR_ALLOW_TASK_FOR_PID);

    if (!sip_fs_disabled || !sip_debug_disabled) {
        sa_log("ERROR: System Integrity Protection must be partially disabled");
        sa_log("");
        sa_log("Current SIP status:");
        if (!sip_fs_disabled) {
            sa_log("  ✗ Filesystem Protections: ENABLED (must be disabled)");
        } else {
            sa_log("  ✓ Filesystem Protections: disabled");
        }
        if (!sip_debug_disabled) {
            sa_log("  ✗ Debugging Restrictions: ENABLED (must be disabled)");
        } else {
            sa_log("  ✓ Debugging Restrictions: disabled");
        }
        sa_log("");
        sa_log("To fix:");
        sa_log("  1. Reboot into Recovery Mode (hold Cmd+R during startup)");
        sa_log("  2. Open Terminal from Utilities menu");
        sa_log("  3. Run: csrutil enable --without fs --without debug");
#ifdef __arm64__
        sa_log("  4. Run: nvram boot-args=\"-arm64e_preview_abi\"");
        sa_log("  5. Reboot normally");
#else
        sa_log("  4. Reboot normally");
#endif
        sa_log("");
        sa_log("WARNING: Disabling SIP reduces system security.");
        sa_log("         Only do this if you understand the implications.");
        return MSS_ERROR_INSTALL;
    }

    // 3. Check boot arguments on ARM64
#ifdef __arm64__
    char bootargs[2048];
    size_t len = sizeof(bootargs) - 1;
    bool has_arm64e_arg = false;

    if (sysctlbyname("kern.bootargs", bootargs, &len, NULL, 0) == 0) {
        bootargs[len] = '\0';
        if (strstr(bootargs, "-arm64e_preview_abi")) {
            has_arm64e_arg = true;
        }
    }

    if (!has_arm64e_arg) {
        sa_log("ERROR: Required boot argument missing for Apple Silicon");
        sa_log("");
        sa_log("The scripting addition loader requires arm64e support to inject into Dock.app");
        sa_log("");
        sa_log("Current boot args:");
        if (len > 0) {
            sa_log("  %s", bootargs);
        } else {
            sa_log("  (none)");
        }
        sa_log("");
        sa_log("To fix:");
        sa_log("  1. Reboot into Recovery Mode (hold Power button, select Options)");
        sa_log("  2. Open Terminal from Utilities menu");
        sa_log("  3. Run: nvram boot-args=\"-arm64e_preview_abi\"");
        sa_log("  4. Ensure SIP is still disabled: csrutil enable --without fs --without debug");
        sa_log("  5. Reboot normally");
        sa_log("");
        sa_log("After reboot, run this program again.");
        return MSS_ERROR_LOAD;
    }
#endif

    return MSS_SUCCESS;
}

static void sa_restart_dock(void)
{
    NSArray *dock = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
    [dock makeObjectsPerformSelector:@selector(terminate)];
}

static bool sa_send_bytes(mss_context *ctx, char *bytes, int length)
{
    int sockfd;
    char dummy;
    bool result = false;

    if (socket_open(&sockfd)) {
        if (socket_connect(sockfd, ctx->socket_path)) {
            if (send(sockfd, bytes, length, 0) != -1) {
                recv(sockfd, &dummy, 1, 0);
                result = true;
            }
        }

        socket_close(sockfd);
    }

    return result;
}

// Query operation helper - sends request and receives response
static bool sa_query_bytes(mss_context *ctx, char *send_bytes, int send_length,
                           void *recv_buffer, int recv_buffer_size, int *bytes_received)
{
    int sockfd;
    bool result = false;

    if (!socket_open(&sockfd)) {
        sa_log("ERROR: Failed to open socket for query");
        return false;
    }

    if (!socket_connect(sockfd, ctx->socket_path)) {
        sa_log("ERROR: Failed to connect socket for query");
        socket_close(sockfd);
        return false;
    }

    if (send(sockfd, send_bytes, send_length, 0) == -1) {
        sa_log("ERROR: Failed to send query request");
        socket_close(sockfd);
        return false;
    }

    // Receive response
    int received = recv(sockfd, recv_buffer, recv_buffer_size, 0);
    if (received > 0) {
        if (bytes_received) *bytes_received = received;
        result = true;
    } else {
        sa_log("ERROR: Failed to receive query response (received=%d)", received);
    }

    socket_close(sockfd);
    return result;
}

// ============================================================================
// Context Management
// ============================================================================

mss_context *mss_create(const char *socket_path)
{
    mss_context *ctx = malloc(sizeof(mss_context));
    if (!ctx) return NULL;

    if (socket_path) {
        snprintf(ctx->socket_path, sizeof(ctx->socket_path), "%s", socket_path);
    } else {
        // Resolve socket path - handle sudo case like yabai does
        const char *sudo_uid = getenv("SUDO_UID");
        uid_t uid = getuid();
        const char *user = NULL;

        // If running as root via sudo, get the original user
        if (uid == 0 && sudo_uid) {
            unsigned int target_uid;
            if (sscanf(sudo_uid, "%u", &target_uid) == 1) {
                struct passwd *pw = getpwuid(target_uid);
                if (pw) {
                    user = pw->pw_name;
                }
            }
        }

        // Fallback to current user
        if (!user) {
            user = getenv("USER");
        }

        if (!user) {
            free(ctx);
            return NULL;
        }

        snprintf(ctx->socket_path, sizeof(ctx->socket_path), SA_SOCKET_PATH_FMT, user);
    }

    ctx->connection_id = SLSMainConnectionID();

    return ctx;
}

void mss_destroy(mss_context *ctx)
{
    if (ctx) {
        free(ctx);
    }
}

void mss_set_log_callback(mss_log_callback callback)
{
    g_log_callback = callback;
}

const char *mss_get_socket_path(mss_context *ctx)
{
    return ctx ? ctx->socket_path : NULL;
}

int mss_handshake(mss_context *ctx, uint32_t *capabilities, const char **version)
{
    if (!ctx) return MSS_ERROR_INVALID_ARG;

    sa_log("Performing handshake with scripting addition...");
    sa_log("Socket path: %s", ctx->socket_path);

    int sockfd;
    char rsp[BUFSIZ] = {0};
    char bytes[0x1000] = { 0x01, 0x00, SA_OPCODE_HANDSHAKE };
    static char version_buf[0x1000] = {0};

    if (!socket_open(&sockfd)) {
        sa_log("ERROR: Failed to open socket");
        return MSS_ERROR_CONNECTION;
    }

    if (!socket_connect(sockfd, ctx->socket_path)) {
        sa_log("ERROR: Failed to connect to socket - payload not running?");
        socket_close(sockfd);
        return MSS_ERROR_CONNECTION;
    }

    if (send(sockfd, bytes, 3, 0) == -1) {
        sa_log("ERROR: Failed to send handshake message");
        socket_close(sockfd);
        return MSS_ERROR_CONNECTION;
    }

    int length = recv(sockfd, rsp, sizeof(rsp)-1, 0);
    socket_close(sockfd);

    if (length <= 0) {
        sa_log("ERROR: No response from payload");
        return MSS_ERROR_CONNECTION;
    }

    char *zero = rsp;
    while (*zero != '\0') ++zero;

    memcpy(version_buf, rsp, zero - rsp + 1);
    memcpy(capabilities, zero+1, sizeof(uint32_t));

    if (version) *version = version_buf;

    sa_log("Handshake successful - Version: %s, Capabilities: 0x%X", version_buf, *capabilities);

    return MSS_SUCCESS;
}

// ============================================================================
// Requirements Checking
// ============================================================================

int mss_check_requirements(mss_context *ctx)
{
    if (!ctx) return MSS_ERROR_INVALID_ARG;

    sa_log("Checking system requirements...");

    int result = sa_validate_requirements(true);

    if (result == MSS_SUCCESS) {
        sa_log("✓ All system requirements met");
    }

    return result;
}

// ============================================================================
// Installation & Loading
// ============================================================================

int mss_install(mss_context *ctx)
{
    if (!ctx) return MSS_ERROR_INVALID_ARG;

    // Validate all system requirements
    int validation_result = sa_validate_requirements(true);
    if (validation_result != MSS_SUCCESS) {
        return validation_result;
    }

    sa_log("Installing scripting addition to /Library/ScriptingAdditions/mss.osax/");

    char osax_base_dir[MAXLEN];
    char osax_contents_dir[MAXLEN];
    char osax_contents_macos_dir[MAXLEN];
    char osax_contents_res_dir[MAXLEN];
    char osax_info_plist[MAXLEN];
    char osax_payload_dir[MAXLEN];
    char osax_payload_contents_dir[MAXLEN];
    char osax_payload_contents_macos_dir[MAXLEN];
    char osax_payload_plist[MAXLEN];
    char osax_bin_payload[MAXLEN];
    char osax_bin_loader[MAXLEN];

    snprintf(osax_base_dir, sizeof(osax_base_dir), "%s", "/Library/ScriptingAdditions/mss.osax");
    snprintf(osax_contents_dir, sizeof(osax_contents_dir), "%s/Contents", osax_base_dir);
    snprintf(osax_contents_macos_dir, sizeof(osax_contents_macos_dir), "%s/MacOS", osax_contents_dir);
    snprintf(osax_contents_res_dir, sizeof(osax_contents_res_dir), "%s/Resources", osax_contents_dir);
    snprintf(osax_info_plist, sizeof(osax_info_plist), "%s/Info.plist", osax_contents_dir);
    snprintf(osax_payload_dir, sizeof(osax_payload_dir), "%s/payload.bundle", osax_contents_res_dir);
    snprintf(osax_payload_contents_dir, sizeof(osax_payload_contents_dir), "%s/Contents", osax_payload_dir);
    snprintf(osax_payload_contents_macos_dir, sizeof(osax_payload_contents_macos_dir), "%s/MacOS", osax_payload_contents_dir);
    snprintf(osax_payload_plist, sizeof(osax_payload_plist), "%s/Info.plist", osax_payload_contents_dir);
    snprintf(osax_bin_loader, sizeof(osax_bin_loader), "%s/loader", osax_contents_macos_dir);
    snprintf(osax_bin_payload, sizeof(osax_bin_payload), "%s/payload", osax_payload_contents_macos_dir);

    // Remove existing installation if present
    char cmd[MAXLEN];
    snprintf(cmd, sizeof(cmd), "rm -rf %s 2>/dev/null", osax_base_dir);
    system(cmd);

    sa_log("Creating directory structure...");

    // Create directory structure
    umask(S_IWGRP | S_IWOTH);

    if (mkdir(osax_base_dir, 0755)) {
        sa_log("ERROR: Failed to create base directory");
        return MSS_ERROR_INSTALL;
    }
    if (mkdir(osax_contents_dir, 0755)) goto cleanup;
    if (mkdir(osax_contents_macos_dir, 0755)) goto cleanup;
    if (mkdir(osax_contents_res_dir, 0755)) goto cleanup;
    if (mkdir(osax_payload_dir, 0755)) goto cleanup;
    if (mkdir(osax_payload_contents_dir, 0755)) goto cleanup;
    if (mkdir(osax_payload_contents_macos_dir, 0755)) goto cleanup;

    sa_log("Writing plist files...");

    // Write plist files
    if (!sa_write_file(sa_plist, strlen(sa_plist), osax_info_plist, "w")) goto cleanup;
    if (!sa_write_file(sa_bundle_plist, strlen(sa_bundle_plist), osax_payload_plist, "w")) goto cleanup;

    sa_log("Writing loader and payload binaries...");

    // Write binaries
    if (!sa_write_file((char *) __src_osax_loader, __src_osax_loader_len, osax_bin_loader, "wb")) goto cleanup;
    if (!sa_write_file((char *) __src_osax_payload, __src_osax_payload_len, osax_bin_payload, "wb")) goto cleanup;

    // Write entitlements for loader
    char osax_loader_entitlements[MAXLEN];
    snprintf(osax_loader_entitlements, sizeof(osax_loader_entitlements), "%s/loader.entitlements", osax_contents_dir);
    const char *entitlements_content =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\">\n"
        "<dict>\n"
        "\t<key>com.apple.security.cs.debugger</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.security.cs.allow-unsigned-executable-memory</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.security.get-task-allow</key>\n"
        "\t<true/>\n"
        "</dict>\n"
        "</plist>\n";
    if (!sa_write_file((char *) entitlements_content, strlen(entitlements_content), osax_loader_entitlements, "w")) {
        goto cleanup;
    }

    sa_log("Code signing binaries...");

    // Set permissions and codesign
    snprintf(cmd, sizeof(cmd), "chmod +x %s", osax_bin_loader);
    system(cmd);
    snprintf(cmd, sizeof(cmd), "codesign -f -s - --entitlements %s %s 2>/dev/null", osax_loader_entitlements, osax_bin_loader);
    system(cmd);
    snprintf(cmd, sizeof(cmd), "chmod +x %s", osax_bin_payload);
    system(cmd);
    snprintf(cmd, sizeof(cmd), "codesign -f -s - %s 2>/dev/null", osax_bin_payload);
    system(cmd);

    sa_log("Restarting Dock.app to load scripting addition...");

    // Restart Dock
    sa_restart_dock();

    sa_log("Installation complete");
    return MSS_SUCCESS;

cleanup:
    sa_log("ERROR: Installation failed, cleaning up...");
    snprintf(cmd, sizeof(cmd), "rm -rf %s 2>/dev/null", osax_base_dir);
    system(cmd);
    return MSS_ERROR_INSTALL;
}

int mss_uninstall(mss_context *ctx)
{
    if (!ctx) return MSS_ERROR_INVALID_ARG;

    if (!is_root()) {
        sa_log("ERROR: Root privileges required for uninstallation");
        sa_log("");
        sa_log("To fix:");
        sa_log("  Run this program with sudo:");
        sa_log("  $ sudo %s", getprogname());
        return MSS_ERROR_ROOT;
    }

    if (!sa_is_sip_friendly()) {
        sa_log("ERROR: SIP must be partially disabled to uninstall");
        return MSS_ERROR_INSTALL;
    }

    sa_log("Uninstalling scripting addition from /Library/ScriptingAdditions/mss.osax/");

    char cmd[MAXLEN];
    snprintf(cmd, sizeof(cmd), "rm -rf /Library/ScriptingAdditions/mss.osax 2>/dev/null");

    int code = system(cmd);

    if (code == 0) {
        sa_log("Uninstallation complete");
        return MSS_SUCCESS;
    } else {
        sa_log("ERROR: Failed to remove scripting addition");
        return MSS_ERROR_OPERATION;
    }
}

int mss_load(mss_context *ctx)
{
    if (!ctx) return MSS_ERROR_INVALID_ARG;

    // Validate all system requirements (root, SIP, boot args)
    int validation_result = sa_validate_requirements(true);
    if (validation_result != MSS_SUCCESS) {
        return validation_result;
    }

    // Auto-install if not already installed
    if (!sa_is_installed()) {
        sa_log("Scripting addition not installed, installing...");
        int result = mss_install(ctx);
        if (result != MSS_SUCCESS) {
            return result;
        }
    }

    sa_log("Loading scripting addition into Dock.app...");

    // Wait for Dock.app to be ready (up to 5 seconds)
    sa_log("Waiting for Dock.app to be ready...");
    bool dock_ready = false;
    for (int i = 0; i < 50; i++) {
        NSArray *dock = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
        if (dock.count == 1) {
            NSRunningApplication *app = [dock firstObject];
            if ([app isFinishedLaunching]) {
                dock_ready = true;
                sa_log("Dock.app is ready");
                usleep(100000); // Extra 100ms for stability
                break;
            }
        }
        usleep(100000); // 100ms between checks
    }

    if (!dock_ready) {
        sa_log("WARNING: Dock.app may not be fully ready, attempting injection anyway...");
    }

    sa_log("Injecting payload into Dock.app...");

    FILE *handle = popen("/Library/ScriptingAdditions/mss.osax/Contents/MacOS/loader", "r");
    if (!handle) {
        sa_log("ERROR: Failed to execute loader");
        return MSS_ERROR_LOAD;
    }

    // Read any output from the loader
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), handle) != NULL) {
        // Strip newline
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len-1] == '\n') buffer[len-1] = '\0';
        sa_log("loader: %s", buffer);
    }

    int result = pclose(handle);
    sa_log("pclose returned: 0x%x (WIFEXITED=%d, WEXITSTATUS=%d)",
           result, WIFEXITED(result), WIFEXITED(result) ? WEXITSTATUS(result) : -1);

    if (WIFEXITED(result)) {
        int exit_code = WEXITSTATUS(result);
        if (exit_code == 0) {
            sa_log("Payload injection successful");
            return MSS_SUCCESS;
        } else {
            sa_log("ERROR: Loader failed with exit code %d", exit_code);
            return MSS_ERROR_LOAD;
        }
    } else if (WIFSIGNALED(result)) {
        sa_log("ERROR: Loader was terminated by signal %d", WTERMSIG(result));
        return MSS_ERROR_LOAD;
    } else {
        sa_log("ERROR: Loader terminated abnormally (status: 0x%x)", result);
        return MSS_ERROR_LOAD;
    }
}

// ============================================================================
// Message sending macros
// ============================================================================

#define sa_payload_init() char bytes[0x1000]; int16_t length = 1+sizeof(length)
#define pack(v) memcpy(bytes+length, &v, sizeof(v)); length += sizeof(v)
#define sa_payload_send(ctx, op) *(int16_t*)bytes = length-sizeof(length), bytes[sizeof(length)] = op, sa_send_bytes(ctx, bytes, length)

// Query operation macros
#define sa_query_init() char send_buf[0x1000]; char recv_buf[0x1000]; int16_t send_len = 1+sizeof(send_len); int recv_len = 0
#define query_pack(v) do { typeof(v) _tmp = (v); memcpy(send_buf+send_len, &_tmp, sizeof(_tmp)); send_len += sizeof(_tmp); } while(0)
#define sa_query_send(ctx, op) (*(int16_t*)send_buf = send_len-sizeof(send_len), send_buf[sizeof(send_len)] = op, sa_query_bytes(ctx, send_buf, send_len, recv_buf, sizeof(recv_buf), &recv_len))
#define unpack_response(v) do { memcpy(&v, recv_buf + unpack_offset, sizeof(v)); unpack_offset += sizeof(v); } while(0)

// ============================================================================
// Space Operations
// ============================================================================

bool mss_space_create(mss_context *ctx, uint64_t sid)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(sid);
    return sa_payload_send(ctx, SA_OPCODE_SPACE_CREATE);
}

bool mss_space_destroy(mss_context *ctx, uint64_t sid)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(sid);
    return sa_payload_send(ctx, SA_OPCODE_SPACE_DESTROY);
}

bool mss_space_focus(mss_context *ctx, uint64_t sid)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(sid);
    return sa_payload_send(ctx, SA_OPCODE_SPACE_FOCUS);
}

bool mss_space_move(mss_context *ctx, uint64_t src_sid,
                          uint64_t dst_sid, uint64_t src_prev_sid, bool focus)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(src_sid);
    pack(dst_sid);
    pack(src_prev_sid);
    pack(focus);
    return sa_payload_send(ctx, SA_OPCODE_SPACE_MOVE);
}

// ============================================================================
// Window Operations
// ============================================================================

bool mss_window_move(mss_context *ctx, uint32_t wid, int x, int y)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    pack(x);
    pack(y);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_MOVE);
}

bool mss_window_set_opacity(mss_context *ctx, uint32_t wid, float opacity)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    pack(opacity);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_OPACITY);
}

bool mss_window_fade_opacity(mss_context *ctx, uint32_t wid,
                                   float opacity, float duration)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    pack(opacity);
    pack(duration);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_OPACITY_FADE);
}

bool mss_window_set_layer(mss_context *ctx, uint32_t wid,
                                enum mss_window_layer layer)
{
    if (!ctx) return false;
    int layer_value = (int)layer;
    sa_payload_init();
    pack(wid);
    pack(layer_value);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_LAYER);
}

bool mss_window_set_sticky(mss_context *ctx, uint32_t wid, bool sticky)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    pack(sticky);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_STICKY);
}

bool mss_window_set_shadow(mss_context *ctx, uint32_t wid, bool shadow)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    pack(shadow);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_SHADOW);
}

bool mss_window_focus(mss_context *ctx, uint32_t wid)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_FOCUS);
}

bool mss_window_scale(mss_context *ctx, uint32_t wid,
                            float x, float y, float w, float h)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    pack(x);
    pack(y);
    pack(w);
    pack(h);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_SCALE);
}

bool mss_window_order(mss_context *ctx, uint32_t wid,
                            enum mss_window_order order, uint32_t relative_wid)
{
    if (!ctx) return false;
    int order_value = (int)order;
    sa_payload_init();
    pack(wid);
    pack(order_value);
    pack(relative_wid);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_ORDER);
}

bool mss_window_order_in(mss_context *ctx, uint32_t *window_list, int count)
{
    if (!ctx || !window_list) return false;

    uint32_t dummy_wid = 0;
    uint8_t ordered_in = 0;

    sa_payload_init();
    pack(count);
    for (int i = 0; i < count; ++i) {
        SLSWindowIsOrderedIn(ctx->connection_id, window_list[i], &ordered_in);
        if (ordered_in) {
            pack(dummy_wid);
        } else {
            pack(window_list[i]);
        }
    }
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_ORDER_IN);
}

bool mss_window_move_to_space(mss_context *ctx, uint32_t wid, uint64_t sid)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(sid);
    pack(wid);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_TO_SPACE);
}

bool mss_window_list_move_to_space(mss_context *ctx, uint32_t *window_list,
                                         int count, uint64_t sid)
{
    if (!ctx || !window_list) return false;
    sa_payload_init();
    pack(sid);
    pack(count);
    for (int i = 0; i < count; ++i) {
        pack(window_list[i]);
    }
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_LIST_TO_SPACE);
}

bool mss_window_resize(mss_context *ctx, uint32_t wid, int width, int height)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    pack(width);
    pack(height);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_RESIZE);
}

bool mss_window_set_frame(mss_context *ctx, uint32_t wid,
                                 int x, int y, int width, int height)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    pack(x);
    pack(y);
    pack(width);
    pack(height);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_SET_FRAME);
}

bool mss_window_minimize(mss_context *ctx, uint32_t wid)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_MINIMIZE);
}

bool mss_window_unminimize(mss_context *ctx, uint32_t wid)
{
    if (!ctx) return false;
    sa_payload_init();
    pack(wid);
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_UNMINIMIZE);
}

bool mss_window_is_minimized(mss_context *ctx, uint32_t wid, bool *result)
{
    if (!ctx || !result) return false;

    sa_query_init();
    query_pack(wid);

    if (!sa_query_send(ctx, SA_OPCODE_WINDOW_IS_MINIMIZED)) {
        return false;
    }

    // Unpack response
    int unpack_offset = 0;
    uint8_t minimized_byte;
    unpack_response(minimized_byte);
    *result = (minimized_byte != 0);

    return true;
}

bool mss_window_get_opacity(mss_context *ctx, uint32_t wid, float *opacity)
{
    if (!ctx || !opacity) return false;

    sa_query_init();
    query_pack(wid);

    if (!sa_query_send(ctx, SA_OPCODE_WINDOW_GET_OPACITY)) {
        return false;
    }

    // Unpack response
    int unpack_offset = 0;
    unpack_response(*opacity);

    return true;
}

bool mss_window_get_frame(mss_context *ctx, uint32_t wid,
                                 int *x, int *y, int *width, int *height)
{
    if (!ctx || !x || !y || !width || !height) return false;

    sa_query_init();
    query_pack(wid);

    if (!sa_query_send(ctx, SA_OPCODE_WINDOW_GET_FRAME)) {
        return false;
    }

    // Unpack response (x, y, width, height)
    int unpack_offset = 0;
    unpack_response(*x);
    unpack_response(*y);
    unpack_response(*width);
    unpack_response(*height);

    return true;
}

bool mss_window_is_sticky(mss_context *ctx, uint32_t wid, bool *sticky)
{
    if (!ctx || !sticky) return false;

    sa_query_init();
    query_pack(wid);

    if (!sa_query_send(ctx, SA_OPCODE_WINDOW_IS_STICKY)) {
        return false;
    }

    // Unpack response
    int unpack_offset = 0;
    uint8_t sticky_byte;
    unpack_response(sticky_byte);
    *sticky = (sticky_byte != 0);

    return true;
}

bool mss_window_get_layer(mss_context *ctx, uint32_t wid,
                                 enum mss_window_layer *layer)
{
    if (!ctx || !layer) return false;

    sa_query_init();
    query_pack(wid);

    if (!sa_query_send(ctx, SA_OPCODE_WINDOW_GET_LAYER)) {
        return false;
    }

    // Unpack response
    int unpack_offset = 0;
    int layer_val;
    unpack_response(layer_val);
    *layer = (enum mss_window_layer)layer_val;

    return true;
}

int mss_display_get_count(mss_context *ctx, uint32_t *count)
{
    if (!ctx || !count) return MSS_ERROR_INVALID_ARG;

    sa_query_init();

    if (!sa_query_send(ctx, SA_OPCODE_DISPLAY_GET_COUNT)) {
        return MSS_ERROR_CONNECTION;
    }

    // Unpack response
    int unpack_offset = 0;
    unpack_response(*count);

    return MSS_SUCCESS;
}

int mss_display_get_list(mss_context *ctx, uint32_t *displays, size_t max_count)
{
    if (!ctx || !displays) return MSS_ERROR_INVALID_ARG;

    sa_query_init();
    query_pack((uint32_t)max_count);

    if (!sa_query_send(ctx, SA_OPCODE_DISPLAY_GET_LIST)) {
        return MSS_ERROR_CONNECTION;
    }

    // Unpack response: count followed by display IDs
    int unpack_offset = 0;
    uint32_t count;
    unpack_response(count);

    // Copy display IDs
    for (size_t i = 0; i < count && i < max_count; i++) {
        unpack_response(displays[i]);
    }

    return MSS_SUCCESS;
}

// ============================================================================
// Window Animation
// ============================================================================

bool mss_window_swap_proxy_in(mss_context *ctx,
                                    struct mss_window_animation *animations,
                                    int count)
{
    if (!ctx || !animations) return false;

    sa_payload_init();
    pack(count);
    for (int i = 0; i < count; ++i) {
        pack(animations[i].wid);
        pack(animations[i].proxy_wid);
    }
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_SWAP_PROXY_IN);
}

bool mss_window_swap_proxy_out(mss_context *ctx,
                                     struct mss_window_animation *animations,
                                     int count)
{
    if (!ctx || !animations) return false;

    sa_payload_init();
    pack(count);
    for (int i = 0; i < count; ++i) {
        pack(animations[i].wid);
        pack(animations[i].proxy_wid);
    }
    return sa_payload_send(ctx, SA_OPCODE_WINDOW_SWAP_PROXY_OUT);
}

#undef sa_payload_init
#undef pack
#undef sa_payload_send
