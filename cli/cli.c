/**
 * mss - CLI tool for mss library
 *
 * A command-line tool for installing, loading, and managing the
 * macOS scripting addition for window and space management.
 *
 * Requirements:
 * - Must run as root (sudo)
 * - SIP must be partially disabled
 * - On ARM64: boot-arg '-arm64e_preview_abi' must be set
 *
 * Build:
 *   make cli
 *
 * Usage:
 *   sudo ./build/mss <command> [options]
 */

#include "mss.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <sys/stat.h>

// Global flag for verbose mode
static bool g_verbose = false;

// ============================================================================
// Logging
// ============================================================================

static void log_callback(const char *message)
{
    if (g_verbose) {
        printf("[mss] %s\n", message);
    }
}

static void print_quiet(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
}

static void print_error(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    fprintf(stderr, "Error: ");
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
    va_end(args);
}

// ============================================================================
// Help Text
// ============================================================================

static void print_help(const char *program_name)
{
    printf("mss - macOS Scripting Addition Manager\n");
    printf("\n");
    printf("Usage: %s <command> [options]\n", program_name);
    printf("\n");
    printf("Commands:\n");
    printf("  check        Check system requirements\n");
    printf("  install      Install scripting addition\n");
    printf("  load         Load scripting addition (installs if needed)\n");
    printf("  uninstall    Remove scripting addition\n");
    printf("  status       Show installation status\n");
    printf("  test         Test if scripting addition is working\n");
    printf("\n");
    printf("Options:\n");
    printf("  -v, --verbose    Show detailed output\n");
    printf("  -h, --help       Show this help message\n");
    printf("\n");
    printf("Requirements:\n");
    printf("  - Root privileges (use sudo)\n");
    printf("  - SIP partially disabled (Filesystem + Debugging Restrictions)\n");
    printf("  - ARM64: boot-arg '-arm64e_preview_abi' must be set\n");
    printf("\n");
    printf("Examples:\n");
    printf("  sudo %s check          # Check requirements\n", program_name);
    printf("  sudo %s load -v        # Install and load with verbose output\n", program_name);
    printf("  sudo %s status         # Show current status\n", program_name);
    printf("  sudo %s test           # Verify it's working\n", program_name);
    printf("  sudo %s uninstall      # Remove completely\n", program_name);
    printf("\n");
}

// ============================================================================
// Utility Functions
// ============================================================================

static bool is_installed(void)
{
    struct stat st;
    return stat("/Library/ScriptingAdditions/mss.osax", &st) == 0;
}

// ============================================================================
// Command Handlers
// ============================================================================

static int cmd_check(mss_context *ctx)
{
    if (!g_verbose) {
        print_quiet("Checking system requirements...\n");
    }

    int result = mss_check_requirements(ctx);

    if (result == MSS_SUCCESS) {
        print_quiet("✓ All system requirements met\n");
        return 0;
    } else {
        print_error("System requirements not met");
        if (!g_verbose) {
            print_quiet("\nRun with --verbose for detailed information\n");
        }
        return 1;
    }
}

static int cmd_install(mss_context *ctx)
{
    if (!g_verbose) {
        print_quiet("Installing scripting addition...\n");
    }

    int result = mss_install(ctx);

    if (result == MSS_SUCCESS) {
        print_quiet("✓ Installed successfully\n");
        return 0;
    } else {
        print_error("Installation failed");
        if (!g_verbose) {
            print_quiet("\nRun with --verbose for detailed error information\n");
        }
        return 1;
    }
}

static int cmd_load(mss_context *ctx)
{
    if (!g_verbose) {
        print_quiet("Loading scripting addition...\n");
    }

    int result = mss_load(ctx);

    if (result == MSS_SUCCESS) {
        print_quiet("✓ Loaded successfully\n");
        return 0;
    } else {
        print_error("Loading failed");
        if (!g_verbose) {
            print_quiet("\nRun with --verbose for detailed error information\n");
        }
        return 1;
    }
}

static int cmd_uninstall(mss_context *ctx)
{
    if (!g_verbose) {
        print_quiet("Uninstalling scripting addition...\n");
    }

    int result = mss_uninstall(ctx);

    if (result == MSS_SUCCESS) {
        print_quiet("✓ Uninstalled successfully\n");
        return 0;
    } else {
        print_error("Uninstallation failed");
        if (!g_verbose) {
            print_quiet("\nRun with --verbose for detailed error information\n");
        }
        return 1;
    }
}

static int cmd_status(mss_context *ctx)
{
    printf("Status Report:\n");
    printf("\n");

    // Check installation
    if (is_installed()) {
        printf("Installation: ✓ Installed at /Library/ScriptingAdditions/mss.osax\n");
    } else {
        printf("Installation: ✗ Not installed\n");
    }

    // Check if loaded (try handshake)
    uint32_t capabilities = 0;
    const char *version = NULL;
    int result = mss_handshake(ctx, &capabilities, &version);

    if (result == MSS_SUCCESS) {
        int cap_count = 0;
        for (int i = 0; i < 7; i++) {
            if (capabilities & (1 << i)) cap_count++;
        }
        printf("Loading:      ✓ Loaded (version %s, %d/%d capabilities)\n", version, cap_count, 7);
    } else {
        printf("Loading:      ✗ Not loaded\n");
    }

    // Check requirements
    // Temporarily enable verbose to capture detailed status
    bool old_verbose = g_verbose;
    g_verbose = false;  // Don't show logs during status check
    result = mss_check_requirements(ctx);
    g_verbose = old_verbose;

    if (result == MSS_SUCCESS) {
        printf("Requirements: ✓ All requirements met\n");
    } else {
        printf("Requirements: ✗ Not met (run 'check' for details)\n");
    }

    printf("\n");
    return 0;
}

static int cmd_test(mss_context *ctx)
{
    printf("Testing scripting addition...\n");

    uint32_t capabilities = 0;
    const char *version = NULL;
    int result = mss_handshake(ctx, &capabilities, &version);

    if (result != MSS_SUCCESS) {
        print_error("Handshake failed - scripting addition not loaded");
        printf("\nTry running: sudo %s load\n", getprogname());
        return 1;
    }

    printf("✓ Handshake successful\n");
    printf("  Version: %s\n", version);
    printf("  Capabilities:\n");

    int cap_count = 0;
    if (capabilities & MSS_CAP_DOCK_SPACES)  { printf("    ✓ Dock Spaces\n"); cap_count++; }
    if (capabilities & MSS_CAP_DPPM)         { printf("    ✓ Desktop Picture Manager\n"); cap_count++; }
    if (capabilities & MSS_CAP_ADD_SPACE)    { printf("    ✓ Add Space\n"); cap_count++; }
    if (capabilities & MSS_CAP_REM_SPACE)    { printf("    ✓ Remove Space\n"); cap_count++; }
    if (capabilities & MSS_CAP_MOV_SPACE)    { printf("    ✓ Move Space\n"); cap_count++; }
    if (capabilities & MSS_CAP_SET_WINDOW)   { printf("    ✓ Set Window\n"); cap_count++; }
    if (capabilities & MSS_CAP_ANIM_TIME)    { printf("    ✓ Animation Time\n"); cap_count++; }

    printf("\n");
    if (cap_count == 7) {
        printf("✓ Scripting addition is working correctly (%d/%d capabilities)\n", cap_count, 7);
        return 0;
    } else {
        printf("⚠ Warning: Only %d/%d capabilities available\n", cap_count, 7);
        printf("  This may indicate compatibility issues with your macOS version\n");
        return 1;
    }
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, char **argv)
{
    const char *command = NULL;
    int result;

    // Parse arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            g_verbose = true;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_help(argv[0]);
            return 0;
        } else if (argv[i][0] == '-') {
            print_error("Unknown option: %s", argv[i]);
            print_help(argv[0]);
            return 1;
        } else if (command == NULL) {
            command = argv[i];
        } else {
            print_error("Unexpected argument: %s", argv[i]);
            print_help(argv[0]);
            return 1;
        }
    }

    // Require a command
    if (command == NULL) {
        print_error("No command specified");
        printf("\n");
        print_help(argv[0]);
        return 1;
    }

    // Enable logging if verbose
    mss_set_log_callback(log_callback);

    // Create context
    mss_context *ctx = mss_create(NULL);
    if (!ctx) {
        print_error("Failed to create context");
        return 1;
    }

    // Dispatch command
    if (strcmp(command, "check") == 0) {
        result = cmd_check(ctx);
    } else if (strcmp(command, "install") == 0) {
        result = cmd_install(ctx);
    } else if (strcmp(command, "load") == 0) {
        result = cmd_load(ctx);
    } else if (strcmp(command, "uninstall") == 0) {
        result = cmd_uninstall(ctx);
    } else if (strcmp(command, "status") == 0) {
        result = cmd_status(ctx);
    } else if (strcmp(command, "test") == 0) {
        result = cmd_test(ctx);
    } else {
        print_error("Unknown command: %s", command);
        printf("\n");
        print_help(argv[0]);
        result = 1;
    }

    // Cleanup
    mss_destroy(ctx);

    return result;
}
