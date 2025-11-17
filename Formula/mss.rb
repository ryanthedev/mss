class Mss < Formula
  desc "macOS Scripting Addition Library for window and space management"
  homepage "https://github.com/ryanthedev/mss"
  url "https://github.com/ryanthedev/mss/archive/refs/tags/v0.0.2.tar.gz"
  sha256 "6c3018b0702b59db0c6188cea314151056ad701fe2be019219fce4557c5e99c0" 
  license "MIT"
  version "0.0.2"

  depends_on :macos => :big_sur
  depends_on xcode: :build

  def install
    # Build library
    system "make"

    # Build CLI tool
    system "make", "cli"

    # Install library and headers
    lib.install "lib/libmss.a"
    include.install "include/mss.h"
    include.install "include/mss_types.h"

    # Install CLI tool
    bin.install "build/mss"

    # Install pkg-config file
    # Generate from template
    inreplace "mss.pc.in", "@PREFIX@", prefix
    inreplace "mss.pc.in", "@VERSION@", version
    (lib/"pkgconfig").install "mss.pc.in" => "mss.pc"
  end

  def caveats
    <<~EOS
      The mss library has been installed:
        Library: #{lib}/libmss.a
        Headers: #{include}/mss.h, #{include}/mss_types.h
        CLI:     #{bin}/mss

      To use in your projects:
        # With pkg-config
        gcc myapp.c $(pkg-config --cflags --libs mss) -o myapp

        # Or manually
        gcc myapp.c -I#{include} -L#{lib} -lmss \\
            -framework Cocoa -framework CoreGraphics -o myapp

      IMPORTANT: Runtime requires a scripting addition to be loaded into Dock.app

      Prerequisites:
        1. System Integrity Protection (SIP) must be partially disabled:
           - Boot to Recovery Mode (⌘R at startup)
           - Run: csrutil enable --without fs --without debug
           - Reboot

        2. ARM64 Macs only: Set boot argument
           - Run: sudo nvram boot-args="-arm64e_preview_abi"
           - Reboot

      Installation (requires sudo):
        sudo mss check    # Verify requirements
        sudo mss load     # Install and load scripting addition
        sudo mss status   # Check installation status

      For more information:
        mss --help

      Documentation:
        https://github.com/ryanthedev/mss
    EOS
  end

  test do
    # Test library linking
    (testpath/"test.c").write <<~EOS
      #include <mss.h>
      #include <stdio.h>
      int main() {
        mss_context *ctx = mss_create(NULL);
        if (ctx == NULL) {
          printf("Failed to create context\\n");
          return 1;
        }
        const char *path = mss_get_socket_path(ctx);
        if (path == NULL) {
          printf("Failed to get socket path\\n");
          return 1;
        }
        printf("Socket path: %s\\n", path);
        mss_destroy(ctx);
        return 0;
      }
    EOS

    system ENV.cc, "test.c",
           "-I#{include}",
           "-L#{lib}", "-lmss",
           "-framework", "Cocoa",
           "-framework", "CoreGraphics",
           "-o", "test"

    assert_match "/tmp/mss_", shell_output("./test")

    # Test CLI tool exists
    assert_predicate bin/"mss", :exist?
    assert_match "mss", shell_output("#{bin}/mss --help")
  end
end
