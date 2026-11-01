# Test fixtures

These are tiny ZIP archives that mimic the *layout* of an APK and an AAB. The
`.so` entries are not real ELF files — the tests stub `llvm-objdump`, so what
matters here is only where the entries sit inside the archive.

| file | contains |
|---|---|
| `sample.apk` | `lib/arm64-v8a/` (two libs) and `lib/armeabi-v7a/` (one lib) |
| `sample.aab` | the same, nested under `base/lib/` as an AAB stores it |
| `feature-module.aab` | `base/lib/` plus a `feature_camera/lib/` module with its own 64-bit and 32-bit libs, a module with no `lib/`, and decoys that are not libraries to measure: a `.so` under `base/assets/lib/` and debug symbols under `BUNDLE-METADATA/` |
| `feature-only-libs.aab` | no `base/lib/`; the only 64-bit lib is in `feature_ml/lib/arm64-v8a/` |
| `no-native-libs.apk` | no `lib/` directory at all |
| `only-32bit.apk` | `lib/armeabi-v7a/` only, no 64-bit ABI |
| `empty-64bit-abi.apk` | `lib/arm64-v8a/` holding only a `wrap.sh`, so there is a 64-bit ABI directory but no 64-bit library to measure |
| `unreadable-entry.apk` | two 64-bit `.so`, one of them stored with a compression method `unzip` cannot decode, so extraction is necessarily partial |

Committed as binaries so the suite needs no zip tool. Regenerate with
`make-fixtures.py` if the layout ever has to change.
