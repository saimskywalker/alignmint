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
ERR=""
RC=0
TOOL_ENV=()

# The controlled environment every run gets: the fake HOME, TEST_PATH (or the
# stubbed PATH), and any KEY=VALUE overrides from TEST_ENV.
tool_env() {
  TOOL_ENV=("HOME=${FAKE_HOME}" "PATH=${TEST_PATH:-${FULL_PATH}}")
  if [[ -n "${TEST_ENV:-}" ]]; then
    # shellcheck disable=SC2206  # deliberate word splitting: TEST_ENV is a
    # space-separated list of KEY=VALUE pairs written by the tests themselves.
    local -a extra=(${TEST_ENV})
    TOOL_ENV+=("${extra[@]}")
  fi
}

# Run the checker with a controlled environment. Everything after the first
# argument is passed to the tool; env overrides come in via TEST_ENV.
run_tool() {
  tool_env
  OUT="$(env -i "${TOOL_ENV[@]}" "${TOOL}" "$@" 2>&1)"
  RC=$?
  return 0
}

# Like run_tool, but keeps the two streams apart: stdout in OUT (and, byte
# for byte, in ${STDOUT_FILE}), stderr in ERR. With --format json, stdout on
# its own is the interface, so it cannot be read mixed with stderr.
STDOUT_FILE="${TMPROOT}/stdout"
STDERR_FILE="${TMPROOT}/stderr"
run_tool_split() {
  tool_env
  env -i "${TOOL_ENV[@]}" "${TOOL}" "$@" >"${STDOUT_FILE}" 2>"${STDERR_FILE}"
  RC=$?
  OUT="$(cat "${STDOUT_FILE}")"
  ERR="$(cat "${STDERR_FILE}")"
  return 0
}

start() {
  CURRENT="$1"
  TEST_PATH=""
  TEST_ENV=""
  ERR=""
}

fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL  %s\n' "${CURRENT}"
  printf '      %s\n' "$1"
  printf '      --- output (exit %s) ---\n' "${RC}"
  printf '%s\n' "${OUT}" | sed 's/^/      /'
  if [[ -n "${ERR}" ]]; then
    printf '      --- stderr ---\n'
    printf '%s\n' "${ERR}" | sed 's/^/      /'
  fi
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

# Compressed libraries are extracted at install, so zip alignment does not
# apply and the ELF check alone decides. useLegacyPackaging = true gives an
# AAB whose bundle config disables uncompressNativeLibraries.
t_aab_compressed_aligned_passes() {
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=disabled"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  assert_out "[info] native libraries are stored compressed" || return 1
  assert_out "archive alignment does not apply (compressed)" || return 1
}

t_aab_compressed_unaligned_fails_with_one() {
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=disabled STUB_OBJDUMP_ALIGN=2**12"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 1 || return 1
  assert_out "[FAIL] min align 2**12" || return 1
}

# A missing block or alignment takes the default of the bundletool version
# recorded in the config (bundletool's OptimizationsMerger): uncompressed
# from 0.6.0, and 16 KB-aligned from 1.17.0.
t_aab_default_alignment_follows_bundletool_version() {
  TEST_ENV="STUB_BUNDLETOOL_ALIGNED=0 STUB_BUNDLETOOL_VERSION=1.17.0"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  assert_out "default of bundletool 1.17.0: 16 KB" || return 1
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=absent STUB_BUNDLETOOL_VERSION=1.18.3"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=absent STUB_BUNDLETOOL_VERSION=1.16.0"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 1 || return 1
  assert_out "(not present at all)" || return 1
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=absent STUB_BUNDLETOOL_VERSION=0.5.0"
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  assert_out "stored compressed" || return 1
}

t_aab_default_without_bundletool_version_is_two() {
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=absent STUB_BUNDLETOOL_VERSION="
  run_tool "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  assert_out "records no bundletool version" || return 1
}

# zipalign skips compressed entries; a zipalign that says "misaligned" here
# must not decide the verdict, the central directory does.
t_apk_compressed_libs_skip_zipalign() {
  TEST_ENV="STUB_ZIPALIGN_RC=1"
  run_tool "${FIXTURES}/compressed-libs.apk"
  assert_rc 0 || return 1
  assert_out "every lib/**.so entry is compressed" || return 1
  TEST_ENV="STUB_ZIPALIGN_RC=1 STUB_OBJDUMP_ALIGN=2**12"
  run_tool "${FIXTURES}/compressed-libs.apk"
  assert_rc 1 || return 1
}

t_json_aab_compressed() {
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=disabled"
  run_tool_split --format json "${FIXTURES}/sample.aab"
  assert_rc 0 || return 1
  assert_json_object || return 1
  assert_out '"summary":{"error":0,"warning":0,"info":1},"findings":[{"id":"archive-compressed","severity":"info"' || return 1
  assert_out '"archive":{"check":"bundleConfig","status":"ok","detail":"native libraries are stored compressed (uncompressNativeLibraries is off); zip alignment does not apply"}' || return 1
  TEST_ENV="STUB_ZIPALIGN_RC=1"
  run_tool_split --format json "${FIXTURES}/compressed-libs.apk"
  assert_rc 0 || return 1
  assert_json_object || return 1
  assert_out '"archive":{"check":"centralDirectory","status":"ok"' || return 1
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=absent STUB_BUNDLETOOL_VERSION="
  run_tool_split --format json "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"bundle-config-unversioned","severity":"error"' || return 1
}

# ------------------------------------------------------------ golden output
#
# The text report is read by people and, until --format json, by scripts that
# scraped it, so it must not move by a byte when the JSON output is touched.
# Each file in test/golden/ is a transcript of one run of the text report:
# exit code, then stdout, then stderr, exactly as the tool wrote them. The
# repository's own paths are replaced by @FIXTURES@ and @STUBS@ so the files
# do not depend on where the checkout lives.
#
# These are not regenerated casually. If a change to the text report is
# intended, regenerate with GOLDEN_UPDATE=1 test/run.sh golden, review the
# diff, and say so in CHANGELOG.md.
GOLDEN="${HERE}/golden"

# Read a whole file into the variable named $2, trailing newlines included.
slurp() {
  local _content
  _content="$(cat "$1"; printf x)"
  printf -v "$2" '%s' "${_content%x}"
}

# The last run_tool_split, as a transcript with the paths replaced.
transcript() {
  local _out _err _t
  slurp "${STDOUT_FILE}" _out
  slurp "${STDERR_FILE}" _err
  _t="$(printf -- '--- exit %s\n--- stdout\n%s--- stderr\n%s' "${RC}" "${_out}" "${_err}"; printf x)"
  _t="${_t%x}"
  _t="${_t//"${FIXTURES}"/@FIXTURES@}"
  _t="${_t//"${STUBS}"/@STUBS@}"
  printf -v "$1" '%s' "${_t}"
}

# $1 = golden file name, the rest = arguments for the tool. The run must
# match the golden file with no --format at all, with --format text and with
# --format=text.
golden_case() {
  local name="$1" file="${GOLDEN}/$1.txt" expected actual form
  shift
  if [[ -n "${GOLDEN_UPDATE:-}" ]]; then
    run_tool_split "$@"
    transcript actual
    mkdir -p "${GOLDEN}"
    printf '%s' "${actual}" > "${file}"
    return 0
  fi
  if [[ ! -f "${file}" ]]; then
    fail "missing golden file ${file}"
    return 1
  fi
  slurp "${file}" expected
  for form in none --format --format=text; do
    case "${form}" in
      none)     run_tool_split "$@" ;;
      --format) run_tool_split --format text "$@" ;;
      *)        run_tool_split "${form}" "$@" ;;
    esac
    transcript actual
    if [[ "${actual}" != "${expected}" ]]; then
      printf '%s' "${actual}" > "${TMPROOT}/golden-actual"
      OUT="$(diff -u "${file}" "${TMPROOT}/golden-actual")"
      ERR=""
      fail "text report differs from ${name}.txt (format option: ${form})"
      return 1
    fi
  done
  return 0
}

# ------------------------------------------------------------- JSON helpers

# stdout holds exactly one JSON object on one line, and nothing else. The
# harness needs nothing beyond bash, so the structural check is done here;
# where python3 happens to be installed, test/check-json.py also parses the
# object strictly and checks the envelope (summary counts match findings).
# CI parses a set of runs with python3 -m json.tool as well.
assert_json_object() {
  local s
  slurp "${STDOUT_FILE}" s
  if [[ "${s}" != "{"*"}"$'\n' ]]; then
    fail "stdout is not a single JSON object followed by a newline"
    return 1
  fi
  s="${s%$'\n'}"
  if [[ "${s}" == *$'\n'* ]]; then
    fail "stdout holds more than one line"
    return 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 -I "${HERE}/check-json.py" < "${STDOUT_FILE}" > "${TMPROOT}/check-json.out" 2>&1; then
      fail "stdout is not a valid result object: $(cat "${TMPROOT}/check-json.out")"
      return 1
    fi
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

t_help_states_play_requirement() {
  # 1.1.0 said Play rejects an unaligned upload. The documented rule is that
  # from 2027-02-01 such an update cannot be released.
  run_tool --help
  assert_rc 0 || return 1
  assert_out "From 1 February 2027 Google Play will not release an" || return 1
  assert_out "update like this for an app that targets API 35 or higher." || return 1
  assert_not_out "reject" || return 1
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
  # is "could not verify", not a FAIL — the second sends someone hunting an
  # alignment bug that was never observed.
  TEST_ENV="STUB_OBJDUMP_FAIL=1"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out "could not read" || return 1
  assert_not_out "not 16 KB aligned" || return 1
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
  assert_out "updates of apps that target Android 15" || return 1
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

t_fail_message_states_play_requirement() {
  TEST_ENV="STUB_OBJDUMP_ALIGN=2**12"
  run_tool "${FIXTURES}/sample.apk"
  assert_rc 1 || return 1
  local want
  want="$(cat <<'EOF'
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
EOF
)"
  # grep -F would match the lines one by one; the block has to appear whole.
  if [[ "${OUT}" != *"${want}"* ]]; then
    fail "expected the FAIL message block, in order"
    return 1
  fi
  assert_not_out "reject" || return 1
  assert_not_out "AT UPLOAD" || return 1
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
  assert_out "updates of apps that target Android 15" || return 1
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

# ---------------------------------------------------------------- --format json
#
# With --format json, stdout is the interface: exactly one JSON object that
# opens with the family envelope (schemaVersion, tool, exitCode, summary,
# findings) and carries the same verdict as the exit code. These run with
# stdout and stderr apart.

t_json_apk_aligned() {
  run_tool_split --format json "${FIXTURES}/sample.apk"
  assert_rc 0 || return 1
  assert_json_object || return 1
  assert_out '{"schemaVersion":1,"tool":{"name":"alignmint","version":"' || return 1
  assert_out '"exitCode":0,"summary":{"error":0,"warning":0,"info":0},"findings":[],"verdict":"aligned","reason":null' || return 1
  assert_out '"artifact":"'"${FIXTURES}"'/sample.apk","kind":"apk"' || return 1
  assert_out '"tools":{"objdump":"'"${STUBS}"'/llvm-objdump","archive":"'"${STUBS}"'/zipalign"}' || return 1
  assert_out '"archive":{"check":"zipalign","status":"ok","detail":"zipalign -c -P 16 4: verification successful"}' || return 1
  assert_out '{"module":null,"abi":"arm64-v8a","name":"libexample.so","path":"lib/arm64-v8a/libexample.so","status":"ok","minAlignLog2":14,"relro":{"status":"notChecked"}}' || return 1
  assert_out '{"module":null,"abi":"armeabi-v7a","path":"lib/armeabi-v7a","status":"skip","reason":"32-bit","libraryCount":1}' || return 1
  assert_out '"hints":[]}' || return 1
  # The text report is still there for the log, on stderr.
  if ! printf '%s' "${ERR}" | grep -qF "PASS"; then
    fail "expected the text report on stderr"
    return 1
  fi
}

t_json_aab_feature_module_unaligned() {
  TEST_ENV="STUB_OBJDUMP_UNALIGNED_PATH=/feature_camera/"
  run_tool_split --format json "${FIXTURES}/feature-module.aab"
  assert_rc 1 || return 1
  assert_json_object || return 1
  assert_out '"exitCode":1,"summary":{"error":1,"warning":0,"info":0},"findings":[{"id":"library-unaligned","severity":"error","message":"feature_camera/lib/arm64-v8a/libcamera.so: LOAD segments aligned to 2**12, below the 2**14 that 16 KB pages need.","path":"'"${FIXTURES}"'/feature-module.aab"}]' || return 1
  assert_out '"verdict":"unaligned","reason":"at least one 64-bit library is not 16 KB aligned."' || return 1
  assert_out '"kind":"aab"' || return 1
  assert_out '"archive":{"check":"bundleConfig","status":"ok","detail":"bundle config declares PAGE_ALIGNMENT_16K"}' || return 1
  assert_out '{"module":"base","abi":"arm64-v8a","name":"libexample.so","path":"base/lib/arm64-v8a/libexample.so","status":"ok","minAlignLog2":14,"relro":{"status":"notChecked"}}' || return 1
  assert_out '{"module":"feature_camera","abi":"arm64-v8a","name":"libcamera.so","path":"feature_camera/lib/arm64-v8a/libcamera.so","status":"fail","minAlignLog2":12,"reason":"min align 2**12, below 2**14","relro":{"status":"notChecked"}}' || return 1
  assert_out '{"module":"feature_camera","abi":"armeabi-v7a","path":"feature_camera/lib/armeabi-v7a","status":"skip"' || return 1
  assert_not_out "libasset_decoy.so" || return 1
}

t_json_unreadable_elf_is_fail() {
  TEST_ENV="STUB_OBJDUMP_NO_LOAD=1"
  run_tool_split --format json "${FIXTURES}/sample.apk"
  assert_rc 1 || return 1
  assert_json_object || return 1
  # Two 64-bit libraries, two findings, and the summary counts them.
  assert_out '"summary":{"error":2,"warning":0,"info":0}' || return 1
  assert_out '{"id":"library-no-load","severity":"error","message":"lib/arm64-v8a/libexample.so: objdump read the library but found no readable LOAD segments."' || return 1
  assert_out '"name":"libexample.so","path":"lib/arm64-v8a/libexample.so","status":"fail","minAlignLog2":null,"reason":"no LOAD segments readable","relro":{"status":"notChecked"}}' || return 1
  assert_out '"verdict":"unaligned"' || return 1
}

t_json_aab_archive_unaligned() {
  TEST_ENV="STUB_BUNDLETOOL_ALIGNED=0"
  run_tool_split --format json "${FIXTURES}/sample.aab"
  assert_rc 1 || return 1
  assert_json_object || return 1
  assert_out '"summary":{"error":1,"warning":0,"info":0},"findings":[{"id":"archive-unaligned","severity":"error"' || return 1
  assert_out '"archive":{"check":"bundleConfig","status":"fail","detail":"bundle config does NOT declare PAGE_ALIGNMENT_16K"},"libraries":[]' || return 1
  assert_out '"verdict":"unaligned"' || return 1
}

t_json_apk_zip_unaligned() {
  TEST_ENV="STUB_ZIPALIGN_RC=1"
  run_tool_split --format json "${FIXTURES}/sample.apk"
  assert_rc 1 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"archive-unaligned","severity":"error"' || return 1
  assert_out '"archive":{"check":"zipalign","status":"fail"' || return 1
  assert_out '"verdict":"unaligned"' || return 1
}

t_json_only_32bit_is_unverified() {
  run_tool_split --format json "${FIXTURES}/only-32bit.apk"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"exitCode":2,"summary":{"error":1,"warning":0,"info":0},"findings":[{"id":"32-bit-only","severity":"error","message":"the artifact contains no 64-bit ABI, so there is nothing to check.","path":"'"${FIXTURES}"'/only-32bit.apk"}]' || return 1
  assert_out '"verdict":"unverified","reason":"the artifact contains no 64-bit ABI, so there is nothing to check."' || return 1
  assert_out '"status":"skip","reason":"32-bit","libraryCount":1}' || return 1
  assert_out '"hints":["16 KB pages only apply to arm64-v8a and x86_64.",' || return 1
}

t_json_empty_64bit_abi_is_unverified() {
  run_tool_split --format json "${FIXTURES}/empty-64bit-abi.apk"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"summary":{"error":1,"warning":1,"info":0},"findings":[{"id":"abi-without-libraries","severity":"warning","message":"lib/arm64-v8a/ is a 64-bit ABI directory that holds no .so, so nothing in it was measured."' || return 1
  assert_out '{"id":"nothing-measured","severity":"error"' || return 1
  assert_out '{"module":null,"abi":"arm64-v8a","path":"lib/arm64-v8a","status":"none","reason":"directory present but holds no .so","libraryCount":0}' || return 1
  assert_out '"verdict":"unverified"' || return 1
}

t_json_missing_toolchain_is_unverified() {
  TEST_PATH="${BARE_PATH}"
  run_tool_split --format json "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"exitCode":2,"summary":{"error":1,"warning":0,"info":0},"findings":[{"id":"tool-missing","severity":"error","message":"no llvm-objdump found."' || return 1
  assert_out '"verdict":"unverified","reason":"no llvm-objdump found."' || return 1
  assert_out '"tools":{"objdump":null,"archive":null},"archive":null,"libraries":[]' || return 1
  assert_not_out '"verdict":"aligned"' || return 1
  # The human message still goes to stderr.
  if ! printf '%s' "${ERR}" | grep -qF "CANNOT VERIFY"; then
    fail "expected the CANNOT VERIFY message on stderr"
    return 1
  fi
}

t_json_hints_are_whole_sentences() {
  # The text report wraps its explanation over several lines; in JSON each
  # hint is one whole sentence or paragraph, never a piece of one.
  TEST_PATH="${TMPROOT}/objdump-only:${BARE_BIN}"
  mkdir -p "${TMPROOT}/objdump-only"
  ln -sf "${STUBS}/llvm-objdump" "${TMPROOT}/objdump-only/llvm-objdump"
  run_tool_split --format json "${FIXTURES}/sample.aab"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '{"id":"tool-missing","severity":"error","message":"bundletool not found on PATH."' || return 1
  assert_out '"hints":["It reads the bundle config, which is where an AAB records its archive alignment. Install it: brew install bundletool","Or download bundletool-all.jar from https://github.com/google/bundletool/releases and pass --bundletool /path/to/bundletool-all.jar","An APK needs zipalign instead of bundletool."]}' || return 1
}

t_json_hints_join_wrapped_lines() {
  run_tool_split --format json "${FIXTURES}/empty-64bit-abi.apk"
  assert_rc 2 || return 1
  assert_out '"hints":["The artifact has a 64-bit ABI directory, but it contains no .so files.","Either this is not the artifact you meant to check, or its 64-bit native code is missing. Neither is evidence of alignment."]}' || return 1
  TEST_ENV="STUB_ZIPALIGN_RC=2"
  run_tool_split --format json "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_out '{"id":"tool-failed","severity":"error","message":"zipalign could not perform the check (exit 2)."' || return 1
  assert_out '"The usual cause is build-tools older than 35, whose zipalign has no -P flag: '"${STUBS}"'/zipalign"' || return 1
  assert_out '"It returns 1 when it has read the archive and found it misaligned; any other status means it never got that far, so nothing was measured."' || return 1
}

t_json_objdump_failure_is_unverified() {
  TEST_ENV="STUB_OBJDUMP_FAIL=1"
  run_tool_split --format json "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"tool-failed","severity":"error","message":"llvm-objdump could not read arm64-v8a/libexample.so."' || return 1
  assert_out '"verdict":"unverified"' || return 1
}

t_json_archive_unreadable_is_unverified() {
  run_tool_split --format json "${FIXTURES}/unreadable-entry.apk"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"archive-unreadable","severity":"error"' || return 1
  assert_out '"verdict":"unverified"' || return 1
}

t_json_no_native_libraries_is_unverified() {
  run_tool_split --format json "${FIXTURES}/no-native-libs.apk"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"no-native-libraries","severity":"error"' || return 1
}

t_json_artifact_errors_are_unverified() {
  run_tool_split --format json "${TMPROOT}/does-not-exist.apk"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"artifact-missing","severity":"error","message":"artifact not found: '"${TMPROOT}"'/does-not-exist.apk","path":"'"${TMPROOT}"'/does-not-exist.apk"}]' || return 1
  : > "${TMPROOT}/thing.zip"
  run_tool_split --format json "${TMPROOT}/thing.zip"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"artifact-invalid","severity":"error"' || return 1
}

t_json_option_error_is_unverified() {
  # The unknown option comes before --format, and is still reported as JSON.
  # No artifact has been named yet, so the finding has no path.
  run_tool_split --wat --format json "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"exitCode":2,"summary":{"error":1,"warning":0,"info":0},"findings":[{"id":"option-invalid","severity":"error","message":"unknown option: --wat"}]' || return 1
  assert_out '"verdict":"unverified","reason":"unknown option: --wat","artifact":null,"kind":null' || return 1
}

t_json_after_ndk_value_is_unverified() {
  # --ndk takes the next argument as its value; the scan for --format has to
  # skip it the same way and still find the --format after it.
  run_tool_split --ndk "${BOGUS_NDK}" "${FIXTURES}/sample.apk" --format json
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"tool-missing","severity":"error","message":"no llvm-objdump under the NDK named by --ndk: '"${BOGUS_NDK}"'"' || return 1
  assert_out '"verdict":"unverified"' || return 1
}

t_json_equals_form_no_artifact() {
  run_tool_split --format=json
  assert_rc 2 || return 1
  assert_json_object || return 1
  assert_out '"findings":[{"id":"artifact-missing","severity":"error","message":"no artifact given."}]' || return 1
  assert_out '"verdict":"unverified","reason":"no artifact given."' || return 1
}

t_json_escapes_quote_and_backslash() {
  # The library is named lib"quote\back.so inside the archive.
  run_tool_split --format json "${FIXTURES}/escape-names.apk"
  assert_rc 0 || return 1
  assert_json_object || return 1
  assert_out '"name":"lib\"quote\\back.so","path":"lib/arm64-v8a/lib\"quote\\back.so"' || return 1
}

t_json_escapes_control_characters() {
  # unzip drops control characters from entry names, but the artifact path is
  # whatever the caller passed, and a tab in it must not break the object.
  local dir="${TMPROOT}/tab"$'\t'"dir"
  mkdir -p "${dir}"
  cp "${FIXTURES}/sample.apk" "${dir}/sample.apk"
  run_tool_split --format json "${dir}/sample.apk"
  assert_rc 0 || return 1
  assert_json_object || return 1
  assert_out '/tab\u0009dir/sample.apk"' || return 1
}

t_format_text_is_the_default() {
  run_tool_split --format json --format text "${FIXTURES}/sample.apk"
  assert_rc 0 || return 1
  assert_out "PASS" || return 1
  assert_not_out '"verdict"' || return 1
}

t_format_last_one_wins() {
  run_tool_split --format text --format=json "${FIXTURES}/sample.apk"
  assert_rc 0 || return 1
  assert_json_object || return 1
}

t_format_unknown_value_is_text() {
  # No agreed format to answer in, so this one stays text, as --help says.
  run_tool_split --format yaml "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  if [[ -n "${OUT}" ]]; then
    fail "expected nothing on stdout"
    return 1
  fi
  OUT="${ERR}"
  assert_out "unknown --format value: yaml" || return 1
}

t_format_unknown_value_wins_over_json() {
  run_tool_split --format json --format=xml "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_not_out "{" || return 1
  OUT="${ERR}"
  assert_out "unknown --format value: xml" || return 1
}

t_format_requires_a_value() {
  run_tool_split --format
  assert_rc 2 || return 1
  assert_not_out "{" || return 1
  OUT="${ERR}"
  assert_out "--format requires a value" || return 1
}

t_format_as_ndk_value_is_not_a_format() {
  # Here --format is the value of --ndk, as the real parse reads it, so json
  # was never asked for: "json" is a second artifact and the error is text.
  run_tool_split --ndk --format json "${FIXTURES}/sample.apk"
  assert_rc 2 || return 1
  assert_not_out "{" || return 1
  OUT="${ERR}"
  assert_out "expected exactly one artifact" || return 1
}

t_json_help_stays_text() {
  run_tool_split --format json --help
  assert_rc 0 || return 1
  assert_out "USAGE" || return 1
  assert_out "--format <fmt>" || return 1
  assert_out "stay text" || return 1
}

# ------------------------------------------------- text report, byte for byte

t_golden_apk_pass()          { golden_case apk-pass "${FIXTURES}/sample.apk"; }
t_golden_apk_elf_fail() {
  TEST_ENV="STUB_OBJDUMP_ALIGN=2**12"
  golden_case apk-elf-fail "${FIXTURES}/sample.apk"
}
t_golden_apk_no_load() {
  TEST_ENV="STUB_OBJDUMP_NO_LOAD=1"
  golden_case apk-no-load "${FIXTURES}/sample.apk"
}
t_golden_apk_zip_fail() {
  TEST_ENV="STUB_ZIPALIGN_RC=1"
  golden_case apk-zip-fail "${FIXTURES}/sample.apk"
}
t_golden_aab_feature_fail() {
  TEST_ENV="STUB_OBJDUMP_UNALIGNED_PATH=/feature_camera/"
  golden_case aab-feature-fail "${FIXTURES}/feature-module.aab"
}
t_golden_aab_archive_fail() {
  TEST_ENV="STUB_BUNDLETOOL_ALIGNED=0"
  golden_case aab-archive-fail "${FIXTURES}/sample.aab"
}
t_golden_aab_compressed() {
  TEST_ENV="STUB_BUNDLETOOL_NATIVE=disabled"
  golden_case aab-compressed "${FIXTURES}/sample.aab"
}
t_golden_only_32bit()        { golden_case only-32bit "${FIXTURES}/only-32bit.apk"; }
t_golden_empty_64bit_abi()   { golden_case empty-64bit-abi "${FIXTURES}/empty-64bit-abi.apk"; }
t_golden_missing_toolchain() {
  TEST_PATH="${BARE_PATH}"
  golden_case missing-toolchain "${FIXTURES}/sample.apk"
}

# -------------------------------------------------------------------- runner

printf 'android-16kb-check test suite\n\n'

check "--help exits 0"                              t_help_exits_zero
check "--help states the Play requirement"         t_help_states_play_requirement
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
check "the FAIL message states the Play requirement" t_fail_message_states_play_requirement
check "an unaligned zip exits 1"                    t_apk_unaligned_zip_fails_with_one
check "an unreadable ELF exits 1"                   t_unreadable_elf_fails_with_one
check "an aligned AAB exits 0"                      t_aab_aligned_passes
check "an AAB without PAGE_ALIGNMENT_16K exits 1"   t_aab_without_page_alignment_fails_with_one
check "a compressed AAB with aligned ELF exits 0"   t_aab_compressed_aligned_passes
check "a compressed AAB with unaligned ELF exits 1" t_aab_compressed_unaligned_fails_with_one
check "AAB defaults follow the bundletool version"  t_aab_default_alignment_follows_bundletool_version
check "an AAB default with no version exits 2"     t_aab_default_without_bundletool_version_is_two
check "an APK with compressed libs skips zipalign"  t_apk_compressed_libs_skip_zipalign
check "a bundletool failure exits 2"                t_aab_bundletool_failure_is_two
check "BUNDLETOOL env var is honoured"              t_bundletool_env_var_is_honoured
check "--bundletool flag is honoured"               t_bundletool_flag_is_honoured
check "an AAB with aligned feature modules exits 0" t_aab_feature_module_aligned_passes
check "an unaligned lib in a feature module exits 1" t_aab_unaligned_lib_in_feature_module_fails_with_one
check "libs only in a feature module are measured"  t_aab_libs_only_in_feature_module_are_measured
check "unaligned libs only in a feature module exit 1" t_aab_libs_only_in_feature_module_unaligned_fails_with_one
check "objdump failing in a feature module exits 2" t_aab_feature_module_objdump_failure_is_two
check "json: an aligned APK"                       t_json_apk_aligned
check "json: an unaligned feature module"           t_json_aab_feature_module_unaligned
check "json: an unreadable ELF is fail"             t_json_unreadable_elf_is_fail
check "json: an AAB without PAGE_ALIGNMENT_16K"     t_json_aab_archive_unaligned
check "json: compressed libraries"                 t_json_aab_compressed
check "json: an unaligned zip"                      t_json_apk_zip_unaligned
check "json: a 32-bit-only APK is unverified"       t_json_only_32bit_is_unverified
check "json: a 64-bit dir with no .so"              t_json_empty_64bit_abi_is_unverified
check "json: a missing toolchain is unverified"     t_json_missing_toolchain_is_unverified
check "json: hints are whole sentences"           t_json_hints_are_whole_sentences
check "json: wrapped hint lines are joined"         t_json_hints_join_wrapped_lines
check "json: an objdump failure is unverified"      t_json_objdump_failure_is_unverified
check "json: an unreadable archive is unverified"  t_json_archive_unreadable_is_unverified
check "json: no native libraries is unverified"    t_json_no_native_libraries_is_unverified
check "json: artifact errors are unverified"        t_json_artifact_errors_are_unverified
check "json: an option error is unverified"         t_json_option_error_is_unverified
check "json: --format after an --ndk value"         t_json_after_ndk_value_is_unverified
check "json: --format=json with no artifact"        t_json_equals_form_no_artifact
check "json: quote and backslash are escaped"       t_json_escapes_quote_and_backslash
check "json: control characters are escaped"        t_json_escapes_control_characters
check "--format text after json gives text"         t_format_text_is_the_default
check "the last --format wins"                      t_format_last_one_wins
check "an unknown --format value is text, exit 2"   t_format_unknown_value_is_text
check "an unknown --format beats an earlier json"   t_format_unknown_value_wins_over_json
check "--format requires a value"                   t_format_requires_a_value
check "--format as the --ndk value is not a format" t_format_as_ndk_value_is_not_a_format
check "--help stays text under --format json"       t_json_help_stays_text
check "golden: aligned APK"                         t_golden_apk_pass
check "golden: under-aligned library"               t_golden_apk_elf_fail
check "golden: no readable LOAD segments"           t_golden_apk_no_load
check "golden: unaligned zip"                       t_golden_apk_zip_fail
check "golden: unaligned lib in a feature module"   t_golden_aab_feature_fail
check "golden: AAB without PAGE_ALIGNMENT_16K"      t_golden_aab_archive_fail
check "golden: AAB with compressed libraries"       t_golden_aab_compressed
check "golden: 32-bit-only artifact"                t_golden_only_32bit
check "golden: 64-bit dir with no .so"              t_golden_empty_64bit_abi
check "golden: missing toolchain"                   t_golden_missing_toolchain

printf '\n%s passed, %s failed\n' "${PASSED}" "${FAILED}"
if (( FAILED > 0 )); then
  exit 1
fi
exit 0
