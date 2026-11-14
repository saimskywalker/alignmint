# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Because the exit codes are the interface, a change to what any of `0`, `1` or
`2` means is a breaking change and takes a major version, even if the script
looks barely different.

## [Unreleased]

## [1.1.1] - 2026-11-14

### Fixed

- The FAIL message, `--help` and the README no longer say that Play rejects
  an unaligned upload. The Android documentation says that from 1 February
  2027, updates of apps that target API 35 or higher cannot be released
  unless they support 16 KB pages, and the FAIL message now says that, with
  links to the page-size and target-API requirements. The exit codes are
  unchanged.
  ([#34](https://github.com/saimskywalker/alignmint/issues/34))

### Added

- `--format json` (also `--format=json`) prints the result as one JSON object
  on stdout, for CI jobs and scripts that need to know which library failed
  without scraping the text report. The text report moves to stderr in that
  mode. The object opens with the envelope shared with storehound and
  husk_sdk (`schemaVersion`, `tool`, `exitCode`, `summary`, `findings` with
  stable ids), followed by `verdict`, `reason`, `libraries` and the other
  fields for this check, all in camelCase. The exit codes are unchanged, and
  every exit `2` still prints the object, with `"verdict": "unverified"` and
  the reason. The shape and the finding ids are in the README under
  "Machine-readable output". `--format text` is the default and its output
  has not changed; the test suite now pins it byte for byte.
  ([#25](https://github.com/saimskywalker/alignmint/issues/25))

### Changed

- The repository is renamed to `saimskywalker/alignmint`. Old links and
  install URLs redirect; the script keeps its name, `android-16kb-check`.

## [1.1.0] - 2026-11-01

### Changed

- The repository is now `saimskywalker/android-imaji-16kb-alignment`, and the
  install URLs in the README point there. The script keeps its name,
  `android-16kb-check`, and its interface is unchanged.

### Fixed

- An AAB's native libraries are now checked in every module, not only in
  `base/lib/`. A `.so` in a dynamic feature module was never extracted or
  measured, so a bundle whose only unaligned library sat in a feature module
  reported `PASS` and exited `0`. Libraries outside base are reported by their
  path in the bundle (`feature_camera/lib/arm64-v8a/libfoo.so`); base keeps
  the short form. A bundle whose native code is only in feature modules is
  measured instead of exiting `2` with "no native libraries found".
  ([#4](https://github.com/saimskywalker/alignmint/issues/4))
- An artifact whose 64-bit ABI directory contains no `.so` no longer reports
  `PASS` and exits `0`. `lib/<abi>/` can hold files that are not libraries —
  `wrap.sh`, for one — and such a run measured nothing at all while printing
  a green result. It exits `2`, and the ABI directory is now reported as
  `[none]` instead of being omitted.
- `objdump` exiting non-zero is now `2` rather than `1`. A library the tool
  could not read was being reported as `[FAIL] no LOAD segments readable`
  under "Play will reject this upload", which claims a measurement that never
  happened. A library where objdump *succeeds* and prints no readable LOAD
  segments is still `[FAIL]`.
- `--ndk ""` and `--bundletool ""` are rejected instead of being treated as if
  the flag were absent. `--ndk "$UNSET_VAR"` used to fall through to
  auto-detection, which is the silent fallback `--ndk` exists to prevent. The
  `--ndk=` form already errored; the two forms now agree.
- Auto-detection picks the highest installed NDK again. Versions were sorted as
  whole paths on `.`, which put the directory prefix in field 1 where a numeric
  compare reads it as `0`, so the major version was never compared: with
  26.3.x, 27.0.x and 28.2.x installed it chose **26.3.x**.
- `zipalign` failing to run is now `2` rather than `1`. Its status separates
  the two cases — `1` means it read the archive and found it misaligned,
  anything else means it never got that far — and build-tools older than 35
  has no `-P` flag at all, so it exits `2` on the usage error. A correctly
  aligned APK was being reported as "Play will reject this upload" by a tool
  that had measured nothing. Same distinction the `objdump` entry above draws.
- A partial extraction is `2` rather than a `PASS` over what did come out.
  `unzip`'s exit status was discarded, so an archive holding an entry unzip
  refuses — an unsupported compression method, a truncated file, a full
  `${TMPDIR}` — was measured on the subset that extracted and reported green.
- CI is green on `ubuntu-latest` again. `test/run.sh` disabled only `SC2329`
  for its indirectly-invoked test bodies; the shellcheck 0.9 that Ubuntu ships
  reports the same finding as `SC2317`, so the lint step failed there while
  being clean on a current local shellcheck.
- The documented install command works as written. It wrote to root-owned
  `/usr/local/bin` without `sudo`, so it failed with `curl: (56)`.

## [1.0.0] - 2026-10-14

First release.

### Added

- `android-16kb-check <path.apk|path.aab>` — checks archive alignment and the
  ELF LOAD alignment of every 64-bit `.so` against Google Play's 16 KB page
  requirement.
- Three-way exit code: `0` aligned, `1` unaligned, `2` could not verify.
  `2` is deliberately distinct from `0`; a machine without the toolchain
  reports an unproven gate rather than a pass.
- `--ndk` and `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT` for naming the NDK that
  supplies `llvm-objdump`. An explicitly named NDK is authoritative: if it has
  no `llvm-objdump`, the run fails instead of falling back to another one.
- Auto-detection of the highest `$ANDROID_HOME/ndk/<version>`, the newest
  `$ANDROID_HOME/build-tools/<version>/zipalign`, and `~/Library/Android/sdk`
  or `~/Android/Sdk` when no SDK root is set.
- `--bundletool` and `BUNDLETOOL` for AAB input, accepting either an
  executable or a `.jar` path run through `java -jar`.
- 32-bit ABIs reported as `SKIP` rather than omitted, so an exempt ABI cannot
  be mistaken for one that passed.
- `--help` and `--version`.

[Unreleased]: https://github.com/saimskywalker/alignmint/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/saimskywalker/alignmint/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/saimskywalker/alignmint/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/saimskywalker/alignmint/releases/tag/v1.0.0
