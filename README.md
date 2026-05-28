# x265

Standalone build of [x265](https://www.x265.org/) — MulticoreWare's HEVC / H.265 video encoder.

[![CI](https://github.com/unpins/x265/actions/workflows/x265.yml/badge.svg)](https://github.com/unpins/x265/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

Encodes Y4M / YUV input to a raw HEVC bitstream (`.hevc`) or a Matroska / MP4-ready elementary stream. Includes 8-bit, Main10 (HDR10), and Main12 depth support in a single binary.

## Installation

Install with [unpin](https://github.com/unpins/unpin):

```bash
unpin x265
```

Or run without installing:

```bash
unpin run x265
```

## Build locally

```bash
nix build github:unpins/x265
./result/bin/x265 --version
```

Or run directly:

```bash
nix run github:unpins/x265 -- --input in.y4m --output out.hevc
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/x265/releases) page has standalone binaries for manual download.

## Build notes

- **Multi bit-depth in one binary** — 8-bit + Main10/HDR10 + Main12 (Linux x86_64 / Windows / macOS). aarch64-linux is 8-bit only (nixpkgs disables multi bit-depth there).
- **Windows:** `mingw` cross, single `.exe`, no companion DLLs.
- **No upstream features disabled** on any platform.

Platform fixes live in [`nix-lib/native-overlay/x265.nix`](https://github.com/unpins/nix-lib/blob/main/native-overlay/x265.nix).
