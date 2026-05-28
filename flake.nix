{
  description = "Standalone build of x265 (H.265/HEVC encoder CLI)";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # Single CLI upstream (`x265`). Shared `nativeFixes.x265` covers:
  # (1) merge libx265.a + libx265-10.a + libx265-12.a into a unified
  #     archive (multibitdepth = HDR10 + Main12), since pkgsStatic
  #     doesn't auto-merge the way the .so build does;
  # (2) clear upstream's `postInstall` that nukes static archives;
  # (3) (mingw) rewrite `x265.pc Libs.private` to the static-libgcc
  #     form so consumer `.exe`s don't end up importing
  #     `libgcc_s_seh-1.dll`.
  # See nix-lib/native-overlay/x265.nix.
  outputs = { self, unpins-lib }:
    let ulib = unpins-lib.lib; in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "x265";
      build         = pkgs: ulib.nativeFixes.x265 pkgs.pkgsStatic;
      # mingw single-binary policy: by default x265.exe imports
      # libstdc++-6.dll + libgcc_s_seh-1.dll + libmcfgthread-2.dll.
      # Two layers conspire:
      #
      # (a) `-static -static-libgcc -static-libstdc++` on the link
      #     would normally fold all three in. They must go through
      #     `cmakeFlagsArray` (not `cmakeFlags`): nixpkgs joins
      #     `cmakeFlags` with spaces and bash word-splits them, so the
      #     spaces inside our `-D…=…` would shatter the value; the
      #     array form preserves it.
      #
      # (b) nixpkgs' multibitdepth recipe emits the 10/12-bit siblings
      #     wrapped as `-Wl,-Bstatic -lx265-10 -lx265-12 -Wl,-Bdynamic`
      #     into the cli link's `linkLibs.rsp`. That trailing
      #     `-Bdynamic` leaves the linker in dynamic mode, and the g++
      #     driver appends the C++ runtime (`-lstdc++ …`) *after* the
      #     rsp — so it resolves against the `.dll.a` import libs,
      #     defeating (a). `CMAKE_CXX_STANDARD_LIBRARIES=-Wl,-Bstatic`
      #     is appended right after the rsp (before the driver's
      #     implicit libs), flipping the linker back to static so the
      #     runtime resolves to `.a`. System DLLs (KERNEL32/SHELL32/…)
      #     are import stubs and link fine under -Bstatic.
      #
      # Result: single `.exe`, imports only KERNEL32 + msvcrt + ntdll
      # + SHELL32. CLI-only concern (ffmpeg's C link never pulls
      # libstdc++); doesn't belong in nix-lib's library overlay.
      windowsBuild  = pkgs:
        let cross = ulib.mingwStaticCross pkgs; in
        (ulib.nativeFixes.x265 cross).overrideAttrs (oa: {
          preConfigure = (oa.preConfigure or "") + ''
            cmakeFlagsArray+=(
              "-DCMAKE_EXE_LINKER_FLAGS=-static -static-libgcc -static-libstdc++"
              "-DCMAKE_CXX_STANDARD_LIBRARIES=-Wl,-Bstatic"
            )
          '';
        });
    };
}
