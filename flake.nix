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
    let
      ulib = unpins-lib.lib;

      # A `--version` smoke passes an encoder that crashes: every released Linux
      # binary with 10- and 12-bit support segfaulted on any 10- or 12-bit encode
      # (musl's 128 KB thread stack), and a later build crashed on every encode.
      # So the native build encodes for real: lossless 8-bit, and 10- and 12-bit
      # where the build has them, must decode (with ffmpeg) back to the exact
      # input in the requested depth, and encoding through stdin/stdout must match
      # encoding files. The input is generated with awk. Runs wherever the build
      # machine can execute the result.
      withRoundTrip = pkgs: drv: drv.overrideAttrs (old: {
        doInstallCheck = pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform;
        nativeInstallCheckInputs = (old.nativeInstallCheckInputs or [ ])
          ++ [ pkgs.buildPackages.ffmpeg-headless ];
        installCheckPhase = ''
          runHook preInstallCheck
          x="''${bin:-$out}/bin/x265"
          fail() { echo "installCheck: $*"; exit 1; }
          LC_ALL=C awk 'BEGIN {
            for (f = 0; f < 3; f++) {
              for (i = 0; i < 64 * 64; i++) printf "%c", (i * 7 + f * 13 + int(i / 64) * 5) % 256
              for (i = 0; i < 32 * 32 * 2; i++) printf "%c", (i * 3 + f * 29) % 256
            }
          }' > src.yuv
          test "$(wc -c < src.yuv)" -eq 18432 || fail "probe input has the wrong size"
          in="--input-res 64x64 --fps 25 --log-level error"
          depths=8
          "$x" --version 2>&1 | grep -q '8bit+10bit+12bit' && depths="8 10 12"
          for d in $depths; do
            "$x" $in --lossless --output-depth $d --input src.yuv --output ll$d.hevc || fail "cannot encode $d-bit"
            fmt=$(ffprobe -v error -show_entries stream=pix_fmt -of csv=p=0 ll$d.hevc)
            case "$d:$fmt" in 8:yuv420p|10:yuv420p10le|12:yuv420p12le) ;; *) fail "$d-bit encode wrote $fmt" ;; esac
            ffmpeg -v error -i ll$d.hevc -f rawvideo -pix_fmt yuv420p back$d.yuv
            cmp -s src.yuv back$d.yuv || fail "lossless $d-bit encode is not exact"
          done
          # --no-info: the stream otherwise records the frame count, which is
          # unknown when reading stdin (total-frames=0), so the bytes differ.
          "$x" $in --pools 1 --frame-threads 1 --crf 28 --no-info --input src.yuv --output crf.hevc || fail "cannot encode at --crf"
          "$x" $in --pools 1 --frame-threads 1 --crf 28 --no-info --input - --output - < src.yuv > piped.hevc || fail "cannot encode through a pipe"
          cmp -s crf.hevc piped.hevc || fail "encoding through stdin/stdout differs from files"
          echo "installCheck: lossless round trips exact ($depths bit), stdin/stdout match files"
          runHook postInstallCheck
        '';
      });
    in
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
      build = pkgs: withRoundTrip pkgs (
        let
          # i686 only: without LTO. The engine's full LTO miscompiles x265 on
          # 32-bit x86 so that every floating-point option parses to garbage —
          # `--crf 28`, `--psy-rd 1.0`, `--aq-strength 1.0` are all rejected as
          # out of range, while integer options (`--qp`, `--bitrate`) work.
          # armv7l, also 32-bit, is unaffected. Same fix heif applies to its x265.
          # The file holding `main` still gets -flto: the single-binary fold
          # takes the program's entry point from the LTO module, and with every
          # object native it finds none and refuses to build (the x264 and
          # jpeg-tools recipe). x265.cpp parses no options itself.
          sp =
            if pkgs.pkgsStatic.stdenv.hostPlatform.isi686
            then pkgs.pkgsStatic.extend (final: prev: {
              x265 = (prev.x265.override {
                stdenv = ulib.unpinAdapterStdenv {
                  inherit pkgs;
                  target = prev.stdenv.hostPlatform.config;
                  native = pkgs.stdenv.buildPlatform.system == pkgs.stdenv.hostPlatform.system;
                  cxx = true;
                  lto = false;
                  captureLinks = true;
                };
              }).overrideAttrs (o: {
                postPatch = (o.postPatch or "") + ''
                  echo 'set_source_files_properties(x265.cpp PROPERTIES COMPILE_OPTIONS -flto)' >> CMakeLists.txt
                '';
              });
            })
            else pkgs.pkgsStatic;
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
        else base.overrideAttrs (oa: {
          # musl gives a thread 128 KB of stack. x265 runs the whole encode on
          # worker threads, and its analysis recursion needs ~192 KB when clang
          # lays out the frames (gcc fit under the limit, which is why this only
          # surfaced on the engine): every encode segfaulted in a frame worker,
          # while `--version` — the smoke — returned 0. musl takes the default
          # thread stack from PT_GNU_STACK, so ask the linker for 2 MB, ten
          # times the measured need. Costs address space, not memory: the pages
          # are only ever backed on touch.
          preConfigure = (oa.preConfigure or "") + ''
            cmakeFlagsArray+=("-DCMAKE_EXE_LINKER_FLAGS=-Wl,-z,stack-size=2097152")
          '';
        }));
      # The `.exe` comes off the engine (clang/lld + libc++, static-only),
      # so the mingw-gcc runtime DLLs this used to fight (libstdc++-6,
      # libgcc_s_seh-1, libmcfgthread-2) have no way in — no link flags
      # needed beyond the cross itself.
      windowsBuild = pkgs: ulib.nativeFixes.x265 (ulib.mingwStaticCross pkgs);
    };
}
