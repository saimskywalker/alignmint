#!/usr/bin/env bash
#
# Test suite for android-16kb-check.
#
# Needs nothing but bash, coreutils and unzip. The external tools the checker
# depends on (llvm-objdump, bundletool, zipalign) are replaced by the stubs in
# test/stubs, and the artifacts by the tiny archives in test/fixtures, so the
# suite runs anywhere without an Android SDK.
#
# The load-bearing case is "toolchain missing must exit 2, never 0". A checker
# that reports success when it could not look is worse than no checker, so
# several tests here exist only to pin that down.
#
# Usage: test/run.sh [name-filter]

# Test bodies and assertion helpers are invoked indirectly, by name, from
# check(). ShellCheck cannot see that, so it reports every one of them as dead
# code. BOTH codes are needed: shellcheck <= 0.9 reports it as SC2317, and
# 0.10 onward split the function case out into SC2329. Disabling only SC2329
# is clean on a current local shellcheck and red on ubuntu-latest, which still
# ships 0.9.
# shellcheck disable=SC2317,SC2329

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
TOOL="${ROOT}/android-16kb-check"
FIXTURES="${HERE}/fixtures"
STUBS="${HERE}/stubs"
FILTER="${1:-}"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "${TMPROOT}"' EXIT

# An isolated PATH holding only the coreutils the checker needs — no
# llvm-objdump, no bundletool, no zipalign. This is how "toolchain absent" is
# simulated without touching the machine's real environment.
BARE_BIN="${TMPROOT}/bare-bin"
mkdir -p "${BARE_BIN}"
for prog in bash env sh unzip mktemp find awk sort grep basename tail wc tr rm cat sed; do
  src="$(command -v "${prog}" 2>/dev/null || true)"
  if [[ -n "${src}" ]]; then
    ln -sf "${src}" "${BARE_BIN}/${prog}"
  fi
done
BARE_PATH="${BARE_BIN}"
FULL_PATH="${STUBS}:${BARE_BIN}"

# A HOME with no ~/Library/Android/sdk, so auto-detection cannot wander off
# onto the developer's real SDK mid-test.
FAKE_HOME="${TMPROOT}/home"
mkdir -p "${FAKE_HOME}"

# An NDK-shaped directory that contains no llvm-objdump.
BOGUS_NDK="${TMPROOT}/bogus-ndk"
mkdir -p "${BOGUS_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin"

export -n ANDROID_HOME ANDROID_SDK_ROOT ANDROID_NDK_HOME ANDROID_NDK_ROOT BUNDLETOOL 2>/dev/null || true
unset ANDROID_HOME ANDROID_SDK_ROOT ANDROID_NDK_HOME ANDROID_NDK_ROOT BUNDLETOOL

PASSED=0
FAILED=0
CURRENT=""
OUT=""
RC=0

# Run the checker with a controlled environment. Everything after the first
# argument is passed to the tool; env overrides come in via TEST_ENV.
run_tool() {
  local -a env_args=("HOME=${FAKE_HOME}" "PATH=${TEST_PATH:-${FULL_PATH}}")
  if [[ -n "${TEST_ENV:-}" ]]; then
    # shellcheck disable=SC2206  # deliberate word splitting: TEST_ENV is a
    # space-separated list of KEY=VALUE pairs written by the tests themselves.
    local -a extra=(${TEST_ENV})
    env_args+=("${extra[@]}")
  fi
  OUT="$(env -i "${env_args[@]}" "${TOOL}" "$@" 2>&1)"
  RC=$?
  return 0
}

start() {
  CURRENT="$1"
  TEST_PATH=""
  TEST_ENV=""
}

fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL  %s\n' "${CURRENT}"
  printf '      %s\n' "$1"
  printf '      --- output (exit %s) ---\n' "${RC}"
  printf '%s\n' "${OUT}" | sed 's/^/      /'
  printf '      ---\n'
}

pass() {
  PASSED=$((PASSED + 1))
  printf 'ok    %s\n' "${CURRENT}"
}

assert_rc() {
  if [[ "${RC}" != "$1" ]]; then
    fail "expected exit $1, got ${RC}"
    return 1
  fi
  return 0
}

assert_out() {
  if ! printf '%s' "${OUT}" | grep -qF -- "$1"; then
    fail "expected output to contain: $1"
    return 1
  fi
  return 0
}

assert_not_out() {
  if printf '%s' "${OUT}" | grep -qF -- "$1"; then
    fail "expected output NOT to contain: $1"
    return 1
  fi
  return 0
}

# One line of output holding both $1 and $2: a verdict is only useful if it
# sits on the line that names the library it is about.
assert_line() {
  if ! printf '%s\n' "${OUT}" | grep -F -- "$1" | grep -qF -- "$2"; then
    fail "expected a line containing both: $1 / $2"
    return 1
  fi
  return 0
}

# A test body is a function named t_<something>; check() runs one unless the
# filter excludes it.
check() {
  local name="$1"
  if [[ -n "${FILTER}" && "${name}" != *"${FILTER}"* ]]; then
    return 0
  fi
  start "${name}"
  if "$2"; then
    pass
  fi
}

# --------------------------------------------------------------- help/version

t_help_exits_zero() {
  run_tool --help
  assert_rc 0 || return 1
  assert_out "USAGE" || return 1
  assert_out "EXIT CODES" || return 1
  # The exit-2 caveat must survive any future rewrite of the help text.
  assert_out "NOT A PASS" || return 1
}

t_help_short_flag() {
  run_tool -h
  assert_rc 0 || return 1
  assert_out "USAGE" || return 1
}

t_version() {
  run_tool --version
  assert_rc 0 || return 1
  assert_out "android-16kb-check" || return 1
}

t_version_short_flag() {
  run_tool -V
  assert_rc 0 || return 1
  assert_out "android-16kb-check" || return 1
}

# ---------------------------------------------------------- argument handling

t_no_arguments() {
  run_tool
  assert_rc 2 || return 1
  assert_out "no artifact given" || return 1
  assert_out "--help" || return 1
}

t_missing_file() {
  run_tool "${TMPROOT}/does-not-exist.apk"
  assert_rc 2 || return 1
  assert_out "artifact not found" || return 1
  assert_out "does-not-exist.apk" || return 1
}

t_directory_instead_of_file() {
  run_tool "${TMPROOT}"
  assert_rc 2 || return 1
  return 0
}

t_wrong_extension() {
  : > "${TMPROOT}/thing.zip"
  run_tool "${TMPROOT}/thing.zip"
  assert_rc 2 || return 1
  assert_out "expected a .aab or .apk" || return 1
}

t_unknown_option() {
  run_tool --wat "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "unknown option: --wat" || return 1
}

t_ndk_flag_requires_value() {
  run_tool --ndk
  assert_rc 2 || return 1
  assert_out "--ndk requires a value" || return 1
}

t_bundletool_flag_requires_value() {
  run_tool --bundletool
  assert_rc 2 || return 1
  assert_out "--bundletool requires a value" || return 1
}

t_two_artifacts_rejected() {
  run_tool "${FIXTURES}/sample.apk" "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  assert_out "expected exactly one artifact" || return 1
}

t_double_dash_ends_options() {
  # After `--`, a leading dash is part of the filename, not a flag. Proven by
  # the error naming the file rather than complaining about an unknown option.
  run_tool -- -weird-name.apk
  assert_rc 2 || return 1
  assert_out "artifact not found: -weird-name.apk" || return 1
  assert_not_out "unknown option" || return 1
}

t_equals_form_of_ndk_flag() {
  run_tool "--ndk=${BOGUS_NDK}" "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "no llvm-objdump under the NDK named by --ndk" || return 1
}

# ----------------------------------------------- the exit-2 contract (core)

t_missing_toolchain_is_two_not_zero() {
  # THE test. Nothing that resolves the toolchain is on PATH, so there is no
  # way to know whether this artifact is aligned. Reporting 0 here is the bug
  # this tool exists to avoid.
  TEST_PATH="${BARE_PATH}"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "llvm-objdump" || return 1
  assert_out "Exit code 2 means unproven, not passed." || return 1
  assert_not_out "PASS" || return 1
}

t_missing_toolchain_on_aab_is_two() {
  TEST_PATH="${BARE_PATH}"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  assert_not_out "PASS" || return 1
}

t_bogus_ndk_dir_is_two() {
  # An explicitly named NDK with nothing in it must fail, not quietly fall back
  # to some other objdump that happens to be on PATH.
  run_tool --ndk "${BOGUS_NDK}" "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "no llvm-objdump under the NDK named by --ndk" || return 1
  assert_out "sdkmanager" || return 1
}

t_bogus_android_ndk_home_is_two() {
  TEST_ENV="ANDROID_NDK_HOME=${BOGUS_NDK}"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "ANDROID_NDK_HOME" || return 1
}

t_missing_bundletool_is_two() {
  # objdump present, bundletool absent: still unproven.
  TEST_PATH="${TMPROOT}/objdump-only:${BARE_BIN}"
  mkdir -p "${TMPROOT}/objdump-only"
  ln -sf "${STUBS}/llvm-objdump" "${TMPROOT}/objdump-only/llvm-objdump"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  assert_out "bundletool not found on PATH" || return 1
  assert_out "brew install bundletool" || return 1
}

t_missing_zipalign_is_two() {
  TEST_PATH="${TMPROOT}/objdump-only:${BARE_BIN}"
  mkdir -p "${TMPROOT}/objdump-only"
  ln -sf "${STUBS}/llvm-objdump" "${TMPROOT}/objdump-only/llvm-objdump"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "zipalign not found" || return 1
}

t_missing_bundletool_jar_is_two() {
  run_tool --bundletool "${TMPROOT}/nope.jar" "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  return 0
}

t_artifact_without_native_libs_is_two() {
  # No .so at all is not a pass — there was nothing to measure.
  run_tool "${FIXTURES}/no-native-libs.apk"
  assert_rc 2 || return 1
  assert_out "no native libraries found" || return 1
  assert_not_out "PASS" || return 1
}

t_sixtyfour_bit_dir_with_no_libs_is_two() {
  # lib/arm64-v8a/ exists but holds no .so — only a wrap.sh. Nothing 64-bit was
  # measured, so there is no basis for a pass. Before this was fixed the run
  # printed PASS and exited 0 without naming arm64-v8a anywhere: a green gate
  # over an artifact the tool had not read.
  run_tool "${FIXTURES}/empty-64bit-abi.apk"
  assert_rc 2 || return 1
  assert_out "nothing was measured" || return 1
  assert_not_out "PASS" || return 1
}

t_sixtyfour_bit_dir_with_no_libs_is_reported() {
  # And it has to be said out loud. A 64-bit ABI mentioned nowhere in the
  # report reads exactly like one that passed.
  run_tool "${FIXTURES}/empty-64bit-abi.apk"
  assert_out "arm64-v8a" || return 1
  assert_out "[none]" || return 1
}

t_objdump_that_cannot_run_is_two_not_one() {
  # objdump present but unable to read the file. Nothing was measured, so this
  # is "could not verify", not "Play will reject this upload" — the second
  # sends someone hunting an alignment bug that was never observed.
  TEST_ENV="STUB_OBJDUMP_FAIL=1"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "could not read" || return 1
  assert_not_out "Play will reject" || return 1
  assert_not_out "PASS" || return 1
}

t_empty_ndk_value_is_rejected() {
  # --ndk "$UNSET_VAR" must not degrade into "no --ndk given". Falling back to
  # auto-detection after being handed an explicit NDK is the silent-fallback
  # behaviour --ndk exists to prevent.
  run_tool --ndk "" "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "--ndk requires a value" || return 1
  assert_not_out "PASS" || return 1
}

t_empty_bundletool_value_is_rejected() {
  run_tool --bundletool "" "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  assert_out "--bundletool requires a value" || return 1
  assert_not_out "PASS" || return 1
}

t_highest_ndk_wins() {
  # 26.3.x must not beat 28.2.x. Sorting whole paths on '.' put the directory
  # prefix in field 1, where a numeric compare reads it as 0 on both BSD and
  # GNU sort, so the major version was never compared and the run silently
  # used an older NDK than the one it advertises. The '==> objdump' header
  # names the NDK that was chosen, so assert on that.
  local sdk="${TMPROOT}/sdk-many-ndks"
  local v bin
  rm -rf "${sdk}"
  for v in 9.0.8775105 26.3.11579264 27.0.12077973 28.2.13676358; do
    bin="${sdk}/ndk/${v}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    mkdir -p "${bin}"
    ln -sf "${STUBS}/llvm-objdump" "${bin}/llvm-objdump"
  done
  # No objdump on PATH, so the only way to resolve one is through the SDK.
  TEST_PATH="${BARE_BIN}"
  TEST_ENV="ANDROID_HOME=${sdk} BUNDLETOOL=${STUBS}/bundletool"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  assert_out "ndk/28.2.13676358/" || return 1
  assert_not_out "ndk/26.3.11579264/" || return 1
}

t_zipalign_that_cannot_run_is_two_not_one() {
  # zipalign present but unable to do the check. Its status distinguishes the
  # two: 1 is "read the archive, it is misaligned", anything else is "never
  # got that far". Build-tools older than 35 has no -P flag and exits 2 on
  # the usage error, so a correctly aligned APK was being reported as a Play
  # rejection by a tool that had measured nothing.
  TEST_ENV="STUB_ZIPALIGN_RC=2"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "could not perform the check" || return 1
  assert_not_out "not stored 16 KB-aligned" || return 1
  assert_not_out "PASS" || return 1
}

t_partial_extraction_is_two_not_pass() {
  # unzip refuses one of the two 64-bit libraries and says so in its exit
  # status. Discarding that status leaves a run that measured half the
  # artifact and printed PASS — the same green-without-looking answer as
  # measuring none of it.
  run_tool "${FIXTURES}/unreadable-entry.apk"
  assert_rc 2 || return 1
  assert_out "Part of the archive was skipped" || return 1
  assert_not_out "PASS" || return 1
}

t_only_32bit_is_two_not_zero() {
  # A 32-bit-only artifact proves nothing about the 64-bit build users install.
  run_tool "${FIXTURES}/only-32bit.apk"
  assert_rc 2 || return 1
  assert_out "no 64-bit ABI" || return 1
  assert_not_out "PASS" || return 1
}

# --------------------------------------------------------- aligned / unaligned

t_apk_aligned_passes() {
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 0 || return 1
  assert_out "PASS" || return 1
  assert_out "libexample.so" || return 1
  assert_out "min align 2**14" || return 1
}

t_apk_reports_32bit_as_skip() {
  # Reported explicitly: an ABI mentioned nowhere reads like one that passed.
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 0 || return 1
  assert_out "armeabi-v7a" || return 1
  assert_out "[SKIP]" || return 1
}

t_apk_over_aligned_passes() {
  TEST_ENV="STUB_OBJDUMP_ALIGN=2**16"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 0 || return 1
  assert_out "PASS" || return 1
}

t_apk_underaligned_elf_fails_with_one() {
  TEST_ENV="STUB_OBJDUMP_ALIGN=2**12"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 1 || return 1
  assert_out "min align 2**12" || return 1
  assert_out "Play will reject this upload" || return 1
  # The remedy has to point at the dependency, not at the caller's own NDK.
  assert_out "PREBUILT" || return 1
}

t_apk_unaligned_zip_fails_with_one() {
  TEST_ENV="STUB_ZIPALIGN_RC=1"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 1 || return 1
  assert_out "not 16 KB aligned" || return 1
  assert_out "AGP 8.5.1" || return 1
}

t_unreadable_elf_fails_with_one() {
  TEST_ENV="STUB_OBJDUMP_NO_LOAD=1"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 1 || return 1
  assert_out "no LOAD segments readable" || return 1
}

t_aab_aligned_passes() {
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  assert_out "PAGE_ALIGNMENT_16K" || return 1
  assert_out "PASS" || return 1
}

t_aab_without_page_alignment_fails_with_one() {
  TEST_ENV="STUB_BUNDLETOOL_ALIGNED=0"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 1 || return 1
  assert_out "does NOT declare PAGE_ALIGNMENT_16K" || return 1
  assert_out "AGP 8.5.1" || return 1
}

t_aab_bundletool_failure_is_two() {
  TEST_ENV="STUB_BUNDLETOOL_FAIL=1"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  assert_out "could not read" || return 1
}

t_bundletool_env_var_is_honoured() {
  TEST_PATH="${TMPROOT}/objdump-only:${BARE_BIN}"
  mkdir -p "${TMPROOT}/objdump-only"
  ln -sf "${STUBS}/llvm-objdump" "${TMPROOT}/objdump-only/llvm-objdump"
  TEST_ENV="BUNDLETOOL=${STUBS}/bundletool"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  assert_out "PASS" || return 1
}

t_bundletool_flag_is_honoured() {
  TEST_PATH="${TMPROOT}/objdump-only:${BARE_BIN}"
  mkdir -p "${TMPROOT}/objdump-only"
  ln -sf "${STUBS}/llvm-objdump" "${TMPROOT}/objdump-only/llvm-objdump"
  run_tool --bundletool "${STUBS}/bundletool" "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  assert_out "PASS" || return 1
}

t_aab_feature_module_aligned_passes() {
  # Every module's libraries are read, and the ones outside base are named by
  # their path in the bundle. base keeps the short form it always had.
  run_tool "${FIXTURES}/feature-module.aab"
  assert_rc 0 || return 1
  assert_out "PASS" || return 1
  assert_line "feature_camera/lib/arm64-v8a/libcamera.so" "[ok]" || return 1
  assert_line "feature_camera/lib/armeabi-v7a" "[SKIP]" || return 1
  assert_line "libexample.so" "[ok]" || return 1
  assert_not_out "base/lib/" || return 1
  # A .so shipped as an asset, and bundletool's debug symbols, are not
  # libraries the device loads; lib/ in their path does not make them one.
  assert_not_out "libasset_decoy.so" || return 1
  assert_not_out "BUNDLE-METADATA" || return 1
}

t_aab_unaligned_lib_in_feature_module_fails_with_one() {
  # The bug in #4: only base/lib/ was extracted, so an unaligned .so in a
  # dynamic feature module was never looked at and the run printed PASS and
  # exited 0 over a bundle Play would reject.
  TEST_ENV="STUB_OBJDUMP_UNALIGNED_PATH=/feature_camera/"
  run_tool "${FIXTURES}/feature-module.aab"
  assert_rc 1 || return 1
  assert_line "feature_camera/lib/arm64-v8a/libcamera.so" "[FAIL] min align 2**12" || return 1
  assert_line "libexample.so" "[ok]" || return 1
  assert_out "Play will reject this upload" || return 1
  assert_not_out "PASS" || return 1
}

t_aab_libs_only_in_feature_module_are_measured() {
  # No base/lib/ at all. This used to be "no native libraries found", exit 2,
  # about a bundle that has native code.
  run_tool "${FIXTURES}/feature-only-libs.aab"
  assert_rc 0 || return 1
  assert_line "feature_ml/lib/arm64-v8a/libmlkit_prebuilt.so" "[ok]" || return 1
  assert_out "PASS" || return 1
}

t_aab_libs_only_in_feature_module_unaligned_fails_with_one() {
  TEST_ENV="STUB_OBJDUMP_ALIGN=2**12"
  run_tool "${FIXTURES}/feature-only-libs.aab"
  assert_rc 1 || return 1
  assert_line "feature_ml/lib/arm64-v8a/libmlkit_prebuilt.so" "[FAIL] min align 2**12" || return 1
  assert_not_out "PASS" || return 1
}

t_aab_feature_module_objdump_failure_is_two() {
  # Reading more modules must not weaken the exit-2 contract: a library in a
  # feature module the tool could not read leaves the bundle unproven.
  TEST_ENV="STUB_OBJDUMP_FAIL=1"
  run_tool "${FIXTURES}/feature-only-libs.aab"
  assert_rc 2 || return 1
  assert_out "could not read feature_ml/lib/arm64-v8a/libmlkit_prebuilt.so" || return 1
  assert_not_out "PASS" || return 1
}

# -------------------------------------------------------------------- runner

printf 'android-16kb-check test suite\n\n'

check "--help exits 0"                              t_help_exits_zero
check "-h exits 0"                                  t_help_short_flag
check "--version exits 0"                           t_version
check "-V exits 0"                                  t_version_short_flag
check "no arguments is a clear error"               t_no_arguments
check "missing file is a clear error"               t_missing_file
check "a directory is rejected"                     t_directory_instead_of_file
check "wrong extension is rejected"                 t_wrong_extension
check "unknown option is rejected"                  t_unknown_option
check "--ndk requires a value"                      t_ndk_flag_requires_value
check "--bundletool requires a value"               t_bundletool_flag_requires_value
check "two artifacts are rejected"                  t_two_artifacts_rejected
check "-- ends option parsing"                      t_double_dash_ends_options
check "--ndk=VALUE form works"                      t_equals_form_of_ndk_flag
check "missing toolchain exits 2, not 0"            t_missing_toolchain_is_two_not_zero
check "missing toolchain on an AAB exits 2"         t_missing_toolchain_on_aab_is_two
check "bogus --ndk exits 2 without falling back"    t_bogus_ndk_dir_is_two
check "bogus ANDROID_NDK_HOME exits 2"              t_bogus_android_ndk_home_is_two
check "missing bundletool exits 2"                  t_missing_bundletool_is_two
check "missing zipalign exits 2"                    t_missing_zipalign_is_two
check "missing bundletool jar exits 2"              t_missing_bundletool_jar_is_two
check "an artifact with no .so exits 2"             t_artifact_without_native_libs_is_two
check "a 32-bit-only artifact exits 2, not 0"       t_only_32bit_is_two_not_zero
check "a zipalign that cannot run exits 2, not 1"   t_zipalign_that_cannot_run_is_two_not_one
check "a partly-extractable archive exits 2"        t_partial_extraction_is_two_not_pass
check "a 64-bit dir with no .so exits 2, not 0"     t_sixtyfour_bit_dir_with_no_libs_is_two
check "a 64-bit dir with no .so is reported"        t_sixtyfour_bit_dir_with_no_libs_is_reported
check "an objdump that cannot run exits 2, not 1"   t_objdump_that_cannot_run_is_two_not_one
check "an empty --ndk value is rejected"            t_empty_ndk_value_is_rejected
check "an empty --bundletool value is rejected"     t_empty_bundletool_value_is_rejected
check "the highest installed NDK is chosen"         t_highest_ndk_wins
check "an aligned APK exits 0"                      t_apk_aligned_passes
check "32-bit ABIs are reported as SKIP"            t_apk_reports_32bit_as_skip
check "over-aligned libraries pass"                 t_apk_over_aligned_passes
check "an under-aligned library exits 1"            t_apk_underaligned_elf_fails_with_one
check "an unaligned zip exits 1"                    t_apk_unaligned_zip_fails_with_one
check "an unreadable ELF exits 1"                   t_unreadable_elf_fails_with_one
check "an aligned AAB exits 0"                      t_aab_aligned_passes
check "an AAB without PAGE_ALIGNMENT_16K exits 1"   t_aab_without_page_alignment_fails_with_one
check "a bundletool failure exits 2"                t_aab_bundletool_failure_is_two
check "BUNDLETOOL env var is honoured"              t_bundletool_env_var_is_honoured
check "--bundletool flag is honoured"               t_bundletool_flag_is_honoured
check "an AAB with aligned feature modules exits 0" t_aab_feature_module_aligned_passes
check "an unaligned lib in a feature module exits 1" t_aab_unaligned_lib_in_feature_module_fails_with_one
check "libs only in a feature module are measured"  t_aab_libs_only_in_feature_module_are_measured
check "unaligned libs only in a feature module exit 1" t_aab_libs_only_in_feature_module_unaligned_fails_with_one
check "objdump failing in a feature module exits 2" t_aab_feature_module_objdump_failure_is_two

printf '\n%s passed, %s failed\n' "${PASSED}" "${FAILED}"
if (( FAILED > 0 )); then
  exit 1
fi
exit 0
