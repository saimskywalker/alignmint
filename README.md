# alignmint — Google Play 16 KB page-size check for APK/AAB

[![CI](https://github.com/saimskywalker/alignmint/actions/workflows/ci.yml/badge.svg)](https://github.com/saimskywalker/alignmint/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/saimskywalker/alignmint)](https://github.com/saimskywalker/alignmint/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Status:** maintained. Bug fixes continue; larger new features are on hold for now.

Play Console warned you about 16 KB page alignment, or you want to find out
before you upload. This is a shell script that answers that question
against the actual `.apk` or `.aab` file, on your machine, in a few seconds.

The run below is a real one, on a small APK built with NDK r28. One of its
libraries was linked with `-z max-page-size=4096`, the way an older prebuilt
`.so` from a dependency often is.

```
$ android-16kb-check app-release.apk
==> artifact : app-release.apk
==> objdump  : /Users/you/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump
==> archive  : /Users/you/Library/Android/sdk/build-tools/36.1.0/zipalign (zipalign)

==> Archive alignment
    [ok]   zipalign -c -P 16 4: verification successful

==> ELF LOAD segment alignment (must be >= 2**14)
    arm64-v8a      libdemo.so                             [ok]   min align 2**14
    arm64-v8a      libprebuilt_old.so                     [FAIL] min align 2**12
    armeabi-v7a    [SKIP] 32-bit, exempt (1 libs)
    x86_64         libdemo.so                             [ok]   min align 2**14

FAIL — at least one 64-bit library is not 16 KB aligned.
  Google Play: from 1 February 2027, updates of apps that target Android 15
  (API 35) or higher cannot be released unless they support 16 KB memory pages.
  https://developer.android.com/guide/practices/page-sizes#google-play-compatibility-requirement
  This check does not read targetSdk. Since 31 August 2026 Play requires phone
  app updates to target API 36, so this applies to almost every update.
  https://developer.android.com/google/play/requirements/target-sdk
  On 16 KB devices an unaligned library may still run in backcompat mode;
  that does not lift the Play requirement.

  Libraries you compile yourself are aligned by NDK r28 or newer.
  A failure here is usually a PREBUILT .so shipped inside a dependency.
  Bumping your own ndkVersion cannot fix that binary — find the dependency
  that owns the .so named above and upgrade it to a release that ships
  16 KB-aligned libraries, or drop it.
$ echo $?
1
```

Quick start:

```bash
curl -fsSLo android-16kb-check \
  https://raw.githubusercontent.com/saimskywalker/alignmint/v1.2.0/android-16kb-check
chmod +x android-16kb-check
./android-16kb-check path/to/app-release.aab
```

It finds the NDK and build-tools under `ANDROID_HOME` or the default SDK
location. An AAB also needs `bundletool`; see [Prerequisites](#prerequisites).

## The requirement

Google Play requires apps that target API 35 or higher to support 16 KB memory
pages on 64-bit devices. From **1 February 2027**, an update that does not
support them cannot be released
([Android docs](https://developer.android.com/guide/practices/page-sizes#google-play-compatibility-requirement)).
This check does not read `targetSdk`, but since 31 August 2026 phone app
updates have to target API 36
([target API requirement](https://developer.android.com/google/play/requirements/target-sdk)),
so the requirement applies to almost every update. On a 16 KB device an
unaligned library may still run in backcompat mode; that does not lift the
Play requirement.

Two independent things have to hold, and both are checked here:

1. **Archive alignment.** Native libraries have to be stored uncompressed and
   16 KB-aligned inside the zip. The Android Gradle Plugin does this from
   8.5.1 onward. In an AAB it appears as `PAGE_ALIGNMENT_16K` in the bundle
   config; in an APK it is what `zipalign -c -P 16 4` verifies.

2. **ELF alignment.** Every `LOAD` segment of every 64-bit `.so` must be
   aligned to at least `2**14`. NDK r28 and newer link this way by default.

These fail independently. A perfectly linked library stored compressed still
breaks on device, and a badly linked library stored with flawless zip alignment
breaks too. Checking one is not checking the other.

32-bit `armeabi-v7a` is exempt — 16 KB pages are a 64-bit feature — and is
reported as `SKIP` rather than passed over silently.

## Exit codes

| exit | meaning | what to do |
|---|---|---|
| `0` | Aligned. Archive alignment is correct and every 64-bit library has all LOAD segments at `2**14` or better. | Upload. |
| `1` | Not aligned. From 1 February 2027 Play will not release an update like this. | Fix it — see below. |
| `2` | **Could not verify.** A required tool or the artifact is missing, or the artifact has nothing to check. | Install the missing tool and run again. |

**Exit code 2 is not a pass.** This matters more than it looks. A checker that
cannot find its toolchain has learned nothing about the artifact, and the
common failure mode in scripts like this one is to report success anyway —
which turns a build gate into a decoration. Here, every path that could not
look ends in `2`, distinct from both the pass and the fail, and says so in
plain words on stderr.

The practical consequence: if you wire this into a build script, treat `1` as
fatal and `2` as a loud warning that the gate is **unproven**. Never fold `2`
into `0`.

```bash
android-16kb-check "$AAB" || case $? in
  1) echo "unaligned — refusing to release"; exit 1 ;;
  2) echo "WARNING: 16 KB alignment is UNVERIFIED on this machine" ;;
esac
```

Cases that deliberately return `2` rather than `0`:

- No `llvm-objdump`, no `bundletool`, or no `zipalign`.
- An artifact containing no native libraries at all — there was nothing to
  measure.
- An artifact containing only 32-bit ABIs. That proves nothing about the
  64-bit build users will install.
- An artifact whose 64-bit ABI directory holds no `.so` at all — `lib/<abi>/`
  can legitimately contain other files, such as `wrap.sh`. The directory is
  reported as `[none]`, because an ABI that appears nowhere in the report
  reads exactly like one that passed.
- `objdump` present but unable to read a library. That is a tool that could
  not look, not a library that failed; a failure to measure never becomes a
  measured failure.
- `zipalign` present but unable to run the check. Build-tools older than 35
  has no `-P` flag, so its zipalign exits on a usage error rather than
  reporting an alignment; that is not an answer about the archive.
- An archive `unzip` could only partly extract. Whatever came out is a subset
  of the artifact, and a verdict on a subset is not a verdict on the upload.

## Install

It is one file with no dependencies beyond the Android toolchain it calls.

```bash
sudo curl -fsSLo /usr/local/bin/android-16kb-check \
  https://raw.githubusercontent.com/saimskywalker/alignmint/v1.2.0/android-16kb-check
sudo chmod +x /usr/local/bin/android-16kb-check
```

`/usr/local/bin` is root-owned on macOS and on a stock Ubuntu, so without
`sudo` curl exits `56` having written nothing. To install without root, put it
somewhere you own and make sure that directory is on `PATH`:

```bash
mkdir -p ~/.local/bin
curl -fsSLo ~/.local/bin/android-16kb-check \
  https://raw.githubusercontent.com/saimskywalker/alignmint/v1.2.0/android-16kb-check
chmod +x ~/.local/bin/android-16kb-check
```

Or clone the repository and run `./android-16kb-check` in place.

The repository was called `android-16kb-check` until October 2026; the script
keeps that name, so installed copies and CI steps that call it are unaffected.

## Usage

```bash
# An app bundle (what you upload to Play)
android-16kb-check build/app/outputs/bundle/release/app-release.aab

# An APK
android-16kb-check build/app/outputs/apk/release/app-release.apk

# Point at a specific NDK rather than letting it auto-detect
android-16kb-check --ndk "$ANDROID_HOME/ndk/28.2.13676358" app-release.aab

# bundletool as a downloaded jar instead of a PATH executable
android-16kb-check --bundletool ~/tools/bundletool-all.jar app-release.aab

# One JSON object on stdout for a script to read; the text report goes to stderr
android-16kb-check --format json app-release.aab > alignment.json
```

| option | effect |
|---|---|
| `--ndk <dir>` | Take `llvm-objdump` from this NDK. Overrides auto-detection; if the directory has no `llvm-objdump` the run fails rather than falling back to some other one. An empty value is an error, not "no `--ndk` given" — `--ndk "$UNSET_VAR"` must not silently become auto-detection. |
| `--bundletool <cmd>` | Executable, or a path ending in `.jar` which is run as `java -jar`. AAB only. An empty value is an error, as for `--ndk`. |
| `--format <text\|json>` | `text` (the default) is the report shown above. `json` prints one JSON object on stdout instead and moves the text report to stderr; see [Machine-readable output](#machine-readable-output). `--format=json` works too. The exit codes are the same in both. |
| `-h`, `--help` | Usage, then exit 0. |
| `-V`, `--version` | Version, then exit 0. |

Environment variables: `ANDROID_NDK_HOME` (or `ANDROID_NDK_ROOT`) is equivalent
to `--ndk`; `ANDROID_HOME` (or `ANDROID_SDK_ROOT`) is used to find the highest
installed `ndk/<version>` and the newest `build-tools/<version>/zipalign`;
`BUNDLETOOL` is equivalent to `--bundletool`.

## In GitHub Actions

GitHub's `ubuntu-latest` runners already have an NDK and build-tools under
`ANDROID_HOME`, and a JDK. They do not have `bundletool`, so an AAB check
downloads the jar. Add this after the step that builds your release:

```yaml
- name: Check 16 KB page alignment
  run: |
    curl -fsSLo android-16kb-check \
      https://raw.githubusercontent.com/saimskywalker/alignmint/v1.2.0/android-16kb-check
    chmod +x android-16kb-check
    curl -fsSLo bundletool-all.jar \
      https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar
    ./android-16kb-check --bundletool bundletool-all.jar \
      app/build/outputs/bundle/release/app-release.aab
```

For an APK, drop the bundletool lines and the `--bundletool` flag; `zipalign`
is found in the runner's build-tools.

Any non-zero exit fails the step, including `2`, because Actions runs `run:`
blocks with `bash -e`. On a release job that is what you want: a gate that
could not run should not let the build through. If you would rather keep `2`
as a warning, use the `case` pattern from [Exit codes](#exit-codes).

## Machine-readable output

`--format json` is for CI jobs, pull request comments and dashboards that need
to know *which* library failed, not only that something did. stdout then holds
exactly one JSON object on a single line, followed by a newline, and nothing
else. The usual text report is written to stderr instead, so a CI log still
shows it; add `2>/dev/null` to drop it. The exit code is the same 0, 1 or 2 as
in text mode, and `exit_code` in the object repeats it.

```bash
android-16kb-check --format json app-release.aab > alignment.json
```

The object starts with the envelope shared by alignmint, storehound and
husk_sdk: `schemaVersion`, `tool`, `exitCode`, `summary` and `findings`, in
that order. The fields for this check follow it. Keys are camelCase. Here is
the feature-module failure from the tests, pretty-printed (the tool prints it
on one line):

```json
{
  "schemaVersion": 1,
  "tool": {"name": "alignmint", "version": "1.2.0"},
  "exitCode": 1,
  "summary": {"error": 1, "warning": 0, "info": 0},
  "findings": [
    {"id": "library-unaligned", "severity": "error",
     "message": "feature_camera/lib/arm64-v8a/libcamera.so: LOAD segments aligned to 2**12, below the 2**14 that 16 KB pages need.",
     "path": "app-release.aab"}
  ],
  "verdict": "unaligned",
  "reason": "at least one 64-bit library is not 16 KB aligned.",
  "artifact": "app-release.aab",
  "kind": "aab",
  "tools": {"objdump": "/path/to/llvm-objdump", "archive": "bundletool"},
  "archive": {"check": "bundleConfig", "status": "ok",
              "detail": "bundle config declares PAGE_ALIGNMENT_16K"},
  "libraries": [
    {"module": "base", "abi": "arm64-v8a", "name": "libexample.so",
     "path": "base/lib/arm64-v8a/libexample.so", "status": "ok",
     "minAlignLog2": 14, "relro": {"status": "notChecked"}},
    {"module": "base", "abi": "armeabi-v7a", "path": "base/lib/armeabi-v7a",
     "status": "skip", "reason": "32-bit", "libraryCount": 1},
    {"module": "feature_camera", "abi": "arm64-v8a", "name": "libcamera.so",
     "path": "feature_camera/lib/arm64-v8a/libcamera.so", "status": "fail",
     "minAlignLog2": 12, "reason": "min align 2**12, below 2**14",
     "relro": {"status": "notChecked"}},
    {"module": "feature_camera", "abi": "armeabi-v7a",
     "path": "feature_camera/lib/armeabi-v7a", "status": "skip",
     "reason": "32-bit", "libraryCount": 1}
  ],
  "hints": ["A failure is usually a prebuilt .so shipped inside a dependency, built with an older NDK; upgrade or drop the dependency that owns it."]
}
```

| field | meaning |
|---|---|
| `schemaVersion` | `1`. Raised only when a field is removed, renamed or changes meaning; new fields can appear without it changing, so ignore keys you do not know. |
| `tool` | `{"name": "alignmint", "version": ...}`, the version of the script that wrote it. |
| `exitCode` | The process exit code: 0, 1 or 2. |
| `summary` | `{"error", "warning", "info"}`: how many findings have each severity. |
| `findings` | One entry per problem found, each with `id` (stable, see below), `severity` (`error`, `warning` or `info`), `message`, and `path`, the artifact, once one was named. Empty when aligned with nothing to report. |
| `verdict` | `"aligned"` (exit 0), `"unaligned"` (exit 1) or `"unverified"` (exit 2). |
| `reason` | Why the verdict is not `aligned`: the `FAIL —` or `CANNOT VERIFY —` line of the text report. `null` when aligned. |
| `artifact` | The path as given on the command line, or `null` if the run stopped before one was known. |
| `kind` | `"apk"`, `"aab"`, or `null` if the run stopped before that was known. |
| `tools` | `objdump` and `archive` (bundletool for an AAB, zipalign for an APK), as the text report's header names them; `null` for one that was not resolved. |
| `archive` | The archive-alignment check: `check` is `"bundleConfig"` or `"zipalign"`, `status` is `"ok"` or `"fail"`, `detail` is the text report's line. `null` if the run stopped before the check gave an answer. |
| `libraries` | One entry per line of the ELF section of the text report, in the same order. Empty if the run stopped before it. |
| `hints` | What to do next, as a list of strings; empty when aligned. Each string is one whole sentence or paragraph: for `unverified` these are the lines the text report prints under `CANNOT VERIFY`, with the lines it wraps for the terminal joined back together. |

Each entry in `libraries` is either a 64-bit library (`ok` or `fail`) or a
whole ABI directory (`skip` or `none`). Keys that do not apply are left out.

| field | meaning |
|---|---|
| `module` | The AAB module (`"base"`, `"feature_camera"`, ...). `null` for an APK. |
| `abi` | `"arm64-v8a"`, `"armeabi-v7a"`, ... |
| `name` | Libraries only: the file name. |
| `path` | Path inside the archive: the library, or the ABI directory. |
| `status` | `"ok"`, `"fail"`, `"skip"` (32-bit, exempt) or `"none"` (a 64-bit ABI directory holding no `.so`), matching `[ok]`, `[FAIL]`, `[SKIP]` and `[none]` in the text report. |
| `minAlignLog2` | Libraries only: the lowest LOAD segment alignment as a power of two (`14` is 16 KB), or `null` when no LOAD segment could be read. |
| `reason` | Why it is not `ok`. Left out for `ok`. |
| `relro` | Libraries only: `{"status": "notChecked"}`. This script does not check GNU_RELRO yet; the field is there so that a later check can fill it in without changing the shape. |
| `libraryCount` | `skip` and `none` only: how many `.so` files the directory holds. |

### Finding ids

The ids are stable: a script can match on them, and they will not be renamed
without a new `schemaVersion`. A 32-bit ABI directory is not a finding; it is
reported in `libraries` with status `skip`.

| id | severity | verdict | when |
|---|---|---|---|
| `library-unaligned` | error | unaligned | A 64-bit library has a LOAD segment aligned below `2**14`. One finding per library; the message names it. |
| `library-no-load` | error | unaligned | objdump read a 64-bit library but found no readable LOAD segment in it. |
| `archive-unaligned` | error | unaligned | The bundle config does not declare `PAGE_ALIGNMENT_16K`, or zipalign reports the APK is not 16 KB aligned. |
| `abi-without-libraries` | warning | any | A 64-bit ABI directory holds no `.so` (the `[none]` line). If no other 64-bit library was read either, `nothing-measured` follows. |
| `option-invalid` | error | unverified | An unknown option, an option missing its value, or more than one artifact. |
| `artifact-missing` | error | unverified | No artifact was given, or the path does not exist. |
| `artifact-invalid` | error | unverified | The path is not a regular file, or does not end in `.apk` or `.aab`. |
| `tool-missing` | error | unverified | A required tool was not found: llvm-objdump (including under the NDK named by `--ndk` or `ANDROID_NDK_HOME`), bundletool, java for a bundletool `.jar`, zipalign or unzip. |
| `tool-failed` | error | unverified | A tool was found but could not do its check: zipalign exited with something other than 0 or 1, or objdump could not read a library. |
| `archive-unreadable` | error | unverified | bundletool could not read the bundle config, or unzip could not list or fully extract the native libraries. |
| `no-native-libraries` | error | unverified | The artifact has no native libraries at all. |
| `32-bit-only` | error | unverified | The artifact has only 32-bit ABIs, so there is nothing to check. |
| `nothing-measured` | error | unverified | There is a 64-bit ABI directory, but no 64-bit library was read. |

Every run that exits `2`, including an unknown option, a missing artifact and
a missing toolchain, still prints the object, with `"verdict": "unverified"`.
Two things stay text even with `--format json`: a missing or unknown
`--format` value, since there is then no agreed format to answer in, and
`--help` and `--version`, which print text and exit 0.

## Prerequisites

| tool | needed for | install |
|---|---|---|
| `llvm-objdump` | the ELF check, always | ships in the NDK: `sdkmanager 'ndk;28.2.13676358'`. GNU `objdump` on PATH also works — it prints the same `align 2**N` form. |
| `bundletool` | AAB input | `brew install bundletool`, or download `bundletool-all.jar` from [the releases page](https://github.com/google/bundletool/releases) and pass `--bundletool` |
| `zipalign` | APK input | ships in the SDK: `sdkmanager 'build-tools;35.0.0'` |
| `unzip` | reading libraries out of the archive | preinstalled on macOS; `apt-get install unzip` on Debian/Ubuntu |

If the NDK lives somewhere non-standard, set `ANDROID_HOME` or pass `--ndk`.
Auto-detection looks at `$ANDROID_HOME/ndk/*` (highest version wins), then
`~/Library/Android/sdk` and `~/Android/Sdk`, then PATH.

## Reading a failure

A `[FAIL]` line names the ABI and the library. In an AAB, a library outside
the base module is named by its path in the bundle instead, such as
`feature_camera/lib/arm64-v8a/libfoo.so`, so the module it ships in is on the
same line. That name is the whole answer, because the fix depends on who built
the file.

**Libraries you compile yourself** are aligned by NDK r28 or newer. If one of
yours fails, raise the NDK version your build uses and rebuild.

**Libraries that arrive prebuilt inside a dependency** — an AAR, a Flutter
plugin, a Maven artifact — were built with whatever NDK their author used, and
your own NDK version has no effect on them whatsoever. This is the common case,
and it is the one this tool exists for: your NDK pin tells you nothing about
these files, so they have to be measured on the artifact.

**This tool cannot fix a prebuilt `.so`.** Relinking someone else's binary is
not something a checker can do. The remedy is to find the dependency that ships
the named library and upgrade it to a release built with a 16 KB-capable NDK,
or drop the dependency. If neither is possible, the upstream project needs a
bug report; there is no local workaround.

A failure on the archive half instead — `PAGE_ALIGNMENT_16K` missing, or
`zipalign` reporting bad entries — is a build configuration problem, not a
dependency problem. Upgrade the Android Gradle Plugin to 8.5.1 or newer.

## What this does and does not prove

It proves what a static read of the artifact can prove: how the libraries are
stored in the zip, and what alignment each 64-bit ELF declares for its LOAD
segments. Those are the two properties the Play requirement is about, which
is why passing here and passing there tend to agree.

It does not run the app. A library can be aligned and still crash on a 16 KB
device for unrelated reasons — a hardcoded `PAGE_SIZE` constant, an assumption
about `mmap` granularity, a bundled runtime that pages things in itself. Static
alignment is a necessary condition, not a sufficient one. Testing on a 16 KB
page-size emulator image remains worthwhile.

It also says nothing about libraries loaded at runtime rather than shipped in
the archive.

For an AAB it reads the libraries of every module in the bundle: `base/lib/`
and the `lib/` of each dynamic feature or other module, since Play checks all
of them.

## Running the tests

```bash
test/run.sh                # everything
test/run.sh toolchain      # a substring filter on test names
```

The suite needs no Android SDK and no real APK. External tools are replaced by
stubs in `test/stubs`, and the artifacts by small archives in `test/fixtures`
that have the right internal layout and nothing else. The text report is
pinned byte for byte by the transcripts in `test/golden`. Where `python3` is
installed, `test/check-json.py` also checks each `--format json` result
strictly; neither the script nor the suite needs Python. `shellcheck` runs over
the script, the harness and the stubs in CI.

## Contributing

Bug reports and pull requests are welcome. Issues labelled
[good first issue](https://github.com/saimskywalker/alignmint/labels/good%20first%20issue)
are small and come with pointers to the code and how to test the change.
Questions and "does this work with my setup" go in
[Discussions](https://github.com/saimskywalker/alignmint/discussions).
Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.

## Trademarks

Google Play and Android are trademarks of Google LLC. This project is
independent and is not affiliated with, sponsored by or endorsed by Google.

## License

MIT. See [LICENSE](LICENSE).
