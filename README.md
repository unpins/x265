# x265

[x265](https://www.x265.org/) — MulticoreWare's HEVC / H.265 video encoder. A single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/x265/actions/workflows/x265.yml/badge.svg)](https://github.com/unpins/x265/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install x265`.

It reads Y4M or raw YUV video and writes a raw HEVC stream (`.hevc`), in 8-bit, 10-bit (Main10, used for HDR10) or 12-bit depth.

## Usage

Run the `x265` program with [unpin](https://github.com/unpins/unpin):

```bash
unpin x265 --input in.y4m --output out.hevc
unpin x265 --input in.y4m --output-depth 10 --crf 22 --output out.hevc
```

To install it onto your PATH:

```bash
unpin install x265
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

- **Bit depths:** 8-, 10- and 12-bit on Linux x86_64, aarch64, ppc64le and
  riscv64, macOS and Windows. The 32-bit Linux binaries (i686, armv7l) are 8-bit
  only, as in nixpkgs; asked for a higher depth, they print "falling back to
  default bit-depth" and encode 8-bit.
- **Windows:** a single `.exe`, no companion DLLs.
- **No upstream features disabled** on any platform.
- **No man pages** — x265 ships none; run `x265 --help` or `x265 --fullhelp`.
