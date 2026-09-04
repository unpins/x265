{
  description = "x265 (HEVC / H.265 video encoder) as a single self-contained binary";

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
      smoke = [ "--version" ];
      smokePattern = "HEVC encoder version [0-9]+\\.[0-9]+";
      # Build via the unpin-llvm engine + emit a bitcode multicall module. Single
      # binary (`x265`), self-folds N=1 from its own module.bc. C++ CLI over the
      # x265 asm kernels (SIMD → native sidecar); requires.cxx pulls libc++.
      engine = "unpin-llvm";
      multicall = {
        # The `.exe` on the engine too, not the nixpkgs mingw-gcc cross.
        windows = true;
        programs = [{ name = "x265"; }];
        requires.cxx = true;
      };
      # The x265 CLI is C++. On darwin it otherwise links the system
      # /usr/lib/libc++.1.dylib dynamically, which action-build's verify
      # rejects (libc++ must be folded in statically). darwin clang ignores
      # `-static-libstdc++`, so suppress the implicit dynamic `-lc++` with
      # `-nostdlib++` and append the static libc++.a + libc++abi.a from
      # pkgsStatic.libcxx (unwinding still comes from the system libunwind
      # in libSystem). CMAKE_CXX_STANDARD_LIBRARIES lands them last on the
      # link line, after the objects that reference them.
      build = pkgs:
        let
          sp = pkgs.pkgsStatic;
          base = ulib.nativeFixes.x265 sp;
        in
        if sp.stdenv.hostPlatform.isDarwin
        then base.overrideAttrs (oa: {
          preConfigure = (oa.preConfigure or "") + ''
            cmakeFlagsArray+=(
              "-DCMAKE_EXE_LINKER_FLAGS=-nostdlib++"
              "-DCMAKE_CXX_STANDARD_LIBRARIES=${sp.libcxx}/lib/libc++.a ${sp.libcxx}/lib/libc++abi.a"
            )
          '';
        })
        else base;
      # The `.exe` comes off the engine (clang/lld + libc++, static-only),
      # so the mingw-gcc runtime DLLs this used to fight (libstdc++-6,
      # libgcc_s_seh-1, libmcfgthread-2) have no way in — no link flags
      # needed beyond the cross itself.
      windowsBuild = pkgs: ulib.nativeFixes.x265 (ulib.mingwStaticCross pkgs);
    };
}
