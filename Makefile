# mss Makefile
# Static library for macOS window/space management via Scripting Addition

# Configuration
ARCHS            := x86_64 arm64
ARCHS_OSAX       := x86_64 arm64e
FRAMEWORKS       := -framework Cocoa -framework CoreGraphics
FRAMEWORKS_SA    := -framework SkyLight -framework Carbon
FRAMEWORKS_LOADER := -framework Cocoa
MIN_VERSION      := -mmacosx-version-min=11.0
CFLAGS        := -O3 -fno-objc-arc -Wall -Wextra
PREFIX        := /usr/local
VERSION       := $(shell grep 'MSS_VERSION' include/mss_types.h | cut -d'"' -f2)

# Directories
SRC_DIR       := src
BUILD_DIR     := build
LIB_DIR       := lib
INCLUDE_DIR   := include

# Output files
STATIC_LIB    := $(LIB_DIR)/libmss.a
PAYLOAD       := $(BUILD_DIR)/payload
LOADER        := $(BUILD_DIR)/loader
PAYLOAD_BIN_C := $(BUILD_DIR)/payload_bin.c
LOADER_BIN_C  := $(BUILD_DIR)/loader_bin.c

# Source files
PAYLOAD_SRC   := $(SRC_DIR)/payload.m
LOADER_SRC    := $(SRC_DIR)/loader.m
CLIENT_SRC    := $(SRC_DIR)/client.m
CLIENT_OBJ    := $(BUILD_DIR)/client.o

# Headers
PUBLIC_HEADERS := $(INCLUDE_DIR)/mss.h $(INCLUDE_DIR)/mss_types.h

# Tools
CC            := xcrun clang
AR            := ar
XXD           := xxd

# ============================================================================
# Main targets
# ============================================================================

.PHONY: all clean install uninstall cli help dist

all: $(STATIC_LIB)
	@echo "✓ Built libmss.a"
	@echo "  Location: $(STATIC_LIB)"
	@echo "  Headers:  $(INCLUDE_DIR)/"
	@echo ""
	@echo "To install: make install"
	@echo "To build cli: make cli"

$(STATIC_LIB): $(PAYLOAD_BIN_C) $(LOADER_BIN_C) $(CLIENT_OBJ) | $(LIB_DIR)
	@echo "Creating static library..."
	$(AR) rcs $@ $(CLIENT_OBJ)

# ============================================================================
# Build steps
# ============================================================================

# Compile payload shared library
$(PAYLOAD): $(PAYLOAD_SRC) $(SRC_DIR)/common.h $(SRC_DIR)/hashtable.h \
            $(SRC_DIR)/arm64_payload.m $(SRC_DIR)/x64_payload.m | $(BUILD_DIR)
	@echo "Building payload for $(ARCHS_OSAX)..."
	$(CC) $(PAYLOAD_SRC) -shared -fPIC $(CFLAGS) $(MIN_VERSION) \
		$(foreach arch,$(ARCHS_OSAX),-arch $(arch)) \
		-DOSAX_VERSION=\"$(VERSION)\" \
		-o $@ \
		-F/System/Library/PrivateFrameworks \
		$(FRAMEWORKS) $(FRAMEWORKS_SA)
	@echo "Signing payload..."
	codesign -fs - $@ 2>/dev/null || true

# Compile loader executable
$(LOADER): $(LOADER_SRC) | $(BUILD_DIR)
	@echo "Building loader for $(ARCHS_OSAX)..."
	$(CC) $(LOADER_SRC) $(CFLAGS) $(MIN_VERSION) \
		$(foreach arch,$(ARCHS_OSAX),-arch $(arch)) \
		-o $@ \
		$(FRAMEWORKS_LOADER)
	@echo "Signing loader with entitlements..."
	codesign -fs - --entitlements loader.entitlements $@ 2>/dev/null || true

# Convert payload binary to C array
$(PAYLOAD_BIN_C): $(PAYLOAD)
	@echo "Converting payload to C array..."
	$(XXD) -i -a $< | sed 's/build_payload/__src_osax_payload/g' > $@

# Convert loader binary to C array
$(LOADER_BIN_C): $(LOADER)
	@echo "Converting loader to C array..."
	$(XXD) -i -a $< | sed 's/build_loader/__src_osax_loader/g' > $@

# Compile client with embedded binaries
$(CLIENT_OBJ): $(CLIENT_SRC) $(PAYLOAD_BIN_C) $(LOADER_BIN_C) $(PUBLIC_HEADERS) \
               $(SRC_DIR)/common.h $(SRC_DIR)/util.h | $(BUILD_DIR)
	@echo "Compiling client library..."
	$(CC) -c $(CLIENT_SRC) $(CFLAGS) $(MIN_VERSION) \
		$(foreach arch,$(ARCHS),-arch $(arch)) \
		-DOSAX_VERSION=\"$(VERSION)\" \
		$(FRAMEWORKS) \
		-F/System/Library/PrivateFrameworks \
		-I$(INCLUDE_DIR) \
		-include $(PAYLOAD_BIN_C) \
		-include $(LOADER_BIN_C) \
		-o $@

# ============================================================================
# Directory creation
# ============================================================================

$(BUILD_DIR):
	@mkdir -p $@

$(LIB_DIR):
	@mkdir -p $@

# ============================================================================
# Installation
# ============================================================================

install: $(STATIC_LIB) cli
	@echo "Installing mss..."
	install -d $(PREFIX)/lib
	install -m 644 $(STATIC_LIB) $(PREFIX)/lib/
	install -d $(PREFIX)/include/mss
	install -m 644 $(INCLUDE_DIR)/mss.h $(PREFIX)/include/mss/
	install -m 644 $(INCLUDE_DIR)/mss_types.h $(PREFIX)/include/mss/
	install -d $(PREFIX)/bin
	install -m 755 $(BUILD_DIR)/mss $(PREFIX)/bin/mss
	install -d $(PREFIX)/lib/pkgconfig
	@sed 's|@PREFIX@|$(PREFIX)|g; s|@VERSION@|$(VERSION)|g' mss.pc.in > $(PREFIX)/lib/pkgconfig/mss.pc
	@echo "✓ Installed to $(PREFIX)"
	@echo "  Library: $(PREFIX)/lib/libmss.a"
	@echo "  Headers: $(PREFIX)/include/mss/"
	@echo "  CLI:     $(PREFIX)/bin/mss"
	@echo "  Pkg-cfg: $(PREFIX)/lib/pkgconfig/mss.pc"

uninstall:
	@echo "Uninstalling mss..."
	rm -f $(PREFIX)/lib/libmss.a
	rm -rf $(PREFIX)/include/mss
	rm -f $(PREFIX)/bin/mss
	rm -f $(PREFIX)/lib/pkgconfig/mss.pc
	@echo "✓ Uninstalled from $(PREFIX)"

# ============================================================================
# CLI Installer
# ============================================================================

cli: all
	@echo "Building mss CLI..."
	$(CC) cli/cli.c $(CFLAGS) $(MIN_VERSION) \
		$(foreach arch,$(ARCHS),-arch $(arch)) \
		-I$(INCLUDE_DIR) \
		-L$(LIB_DIR) -lmss \
		$(FRAMEWORKS) $(FRAMEWORKS_SA) \
		-F/System/Library/PrivateFrameworks \
		-o $(BUILD_DIR)/mss
	@echo "Signing installer..."
	codesign -fs - $(BUILD_DIR)/mss 2>/dev/null || true
	@echo "✓ Built installer: $(BUILD_DIR)/mss"
	@echo ""
	@echo "Run with: sudo $(BUILD_DIR)/mss <command>"
	@echo "For help: $(BUILD_DIR)/mss --help"

# ============================================================================
# Cleaning
# ============================================================================

clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	rm -rf $(LIB_DIR)
	@echo "✓ Clean complete"

# ============================================================================
# Help
# ============================================================================

help:
	@echo "mss - Standalone macOS Scripting Addition Library"
	@echo ""
	@echo "Targets:"
	@echo "  make              - Build the static library"
	@echo "  make install      - Install to $(PREFIX)"
	@echo "  make uninstall    - Remove from $(PREFIX)"
	@echo "  make cli          - Build CLI installer tool"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make dist         - Create release tarball"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Requirements:"
	@echo "  - macOS 11.0+ (Big Sur or later)"
	@echo "  - Xcode Command Line Tools"
	@echo "  - SIP partially disabled for usage (not for building)"
	@echo ""
	@echo "Build output:"
	@echo "  Library:   $(STATIC_LIB)"
	@echo "  Headers:   $(INCLUDE_DIR)/"
	@echo "  Installer: $(BUILD_DIR)/mss"

# ============================================================================
# Distribution
# ============================================================================

dist: all cli
	@echo "Creating distribution tarball..."
	@mkdir -p dist/mss-$(VERSION)
	@cp -r $(LIB_DIR) dist/mss-$(VERSION)/
	@cp -r $(INCLUDE_DIR) dist/mss-$(VERSION)/
	@mkdir -p dist/mss-$(VERSION)/bin
	@cp $(BUILD_DIR)/mss dist/mss-$(VERSION)/bin/mss
	@cp mss.pc.in dist/mss-$(VERSION)/
	@cp Makefile dist/mss-$(VERSION)/
	@cp LICENSE dist/mss-$(VERSION)/
	@cp CLAUDE.md dist/mss-$(VERSION)/ 2>/dev/null || true
	@cp SWIFT_INTEGRATION.md dist/mss-$(VERSION)/ 2>/dev/null || true
	@cp README.md dist/mss-$(VERSION)/ 2>/dev/null || true
	@cd dist && tar -czf mss-$(VERSION).tar.gz mss-$(VERSION)
	@mv dist/mss-$(VERSION).tar.gz .
	@rm -rf dist
	@echo "✓ Created mss-$(VERSION).tar.gz"
	@shasum -a 256 mss-$(VERSION).tar.gz
