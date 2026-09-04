# Changelog

## [Unreleased]

### Fixed

- Encoding works again on Linux. Every Linux build since the toolchain change
  crashed the moment it started encoding and wrote an empty file; only
  `--version` still worked, so nothing caught it. No release shipped with this.
  Encoded files now match the previous release's byte for byte.

### Changed

- The Windows binary is now built by the same compiler as the Linux and macOS
  ones, and is 18% smaller (23.7 MB to 19.4 MB). Checked on Windows 10: it
  still encodes 8-, 10- and 12-bit video, and each of the three produces a file
  byte-for-byte identical to the previous binary's.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.
