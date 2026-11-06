# Contributing

Contributions are welcome. A few things worth knowing before you spend time.

## How changes land

Every change reaches `main` through a pull request that the maintainer reviews
and merges. That includes changes from forks, which is the normal path — you
cannot push to this repository directly, and nothing merges without a review.
If a PR sits without a response, a nudge is fine.

## Before opening a PR

```bash
shellcheck android-16kb-check test/run.sh test/stubs/*
test/run.sh
```

CI runs the same two commands on `ubuntu-latest`, plus a check that the script
is still executable and that a run with no toolchain exits 2. shellcheck must
be clean — not "clean apart from the informational ones". If a finding is
genuinely wrong, disable it by number with a comment saying why, the way
`test/run.sh` does for `SC2317,SC2329`.

Mind the version gap while you are there: `ubuntu-latest` still installs
shellcheck 0.9, and a current local shellcheck is 0.11. They do not always use
the same code for the same finding — indirectly-invoked functions are SC2317
on 0.9 and SC2329 from 0.10 onward — so a disable that names only one of a
pair is clean on the laptop and red on CI. Disabling both is harmless; an
unknown code is ignored rather than reported.

## The exit codes are the interface

This tool has three answers, and the third one is the reason it exists:

| exit | meaning |
|---|---|
| `0` | aligned |
| `1` | unaligned — Play would reject the upload |
| `2` | could not verify |

Most scripts in this space have two answers, and quietly fold "I could not
find my toolchain" into the passing one. That converts a release gate into
decoration, and the failure is invisible precisely when it matters — on the
machine that is missing something.

So the rule for any change here: **no new path may reach `0` without having
actually read the artifact.** If you are adding a fallback, a heuristic, or a
"probably fine" case, it belongs at `2`. Every such path goes through
`cannot_verify`, which exists so this cannot be blurred by a stray `exit 0`
somewhere down the file. Widening what counts as a pass needs a strong case and
a changelog entry; it is a breaking change to the interface, not a tweak.

The same reasoning is why a 32-bit-only artifact and an artifact with no `.so`
at all both exit `2` rather than `0`. Neither is evidence about the 64-bit
build users install.

## AI-assisted contributions

Using AI tools is fine; please just be open about it.

- Say in the PR description which AI tools you used, if any: none, some or most, plus the tool or agent and the model (for example "Claude Code, Opus 5.5" or "Copilot, GPT-5").
- Write the PR description and any issues yourself, in your own words. Short, plain descriptions are welcome; please don't paste generated text.
- Read, run and test every line you submit, and be ready to explain it in review.
- PRs without the disclosure may be closed.

## What a good bug fix looks like

A test that fails without the fix. `test/run.sh` is a plain bash harness — add
a `t_<name>` function and a `check` line at the bottom. Several existing tests
name the mistake they guard against in a comment, and that is the shape worth
adding to.

The suite deliberately does not need an Android SDK, a JDK, or a real APK.
External tools are replaced by stubs in `test/stubs` and artifacts by small
archives in `test/fixtures` that have the right internal layout and nothing
else. Please keep it that way — a suite that only runs on a configured Android
machine is a suite that stops being run. If a change genuinely cannot be tested
against a stub, say so in the PR rather than leaving it uncovered silently.

`bats` is not used. The harness is ~200 lines of bash with no install step,
which is a deliberate trade: one fewer thing to have installed before you can
run the tests on the machine where the bug reproduced.

## Things to be careful with

**Toolchain resolution.** It has to work on a laptop with Android Studio, on a
laptop with only command-line tools, and on a CI image with nothing but
`ANDROID_HOME`. When adding a new place to look, add it as a *fallback* after
the explicit ones — an NDK named by `--ndk` or `ANDROID_NDK_HOME` is
authoritative, and quietly using a different one is worse than failing.

**Parsing objdump output.** The ELF check reads `align 2**N` out of
`objdump -p`. GNU objdump and llvm-objdump both print that form today; a change
in either could silently produce zero matches, which is why a library with no
readable LOAD segments is a `[FAIL]` and not a shrug. That is specifically the
case where objdump *ran* and its output held nothing usable. objdump exiting
non-zero is the other case and is a `2`: nothing was measured, so there is no
verdict to report. Keep those two apart — reading a non-zero exit as `[FAIL]`
announces "Play will reject this upload" about a file the tool never opened.

**Any tool's exit status.** The objdump rule above is the general one, and it
applies to `zipalign` and `unzip` too: a status that means "I could not do the
check" must never be read as "the check failed". `zipalign` returns `1` for a
misaligned archive and something else when it never looked — build-tools below
35 has no `-P` and exits `2`. `unzip` returning anything but `0`, `1` or `11`
means it skipped entries, so the extracted tree is a subset of the artifact.

**Version comparison.** There is no portable `sort` spelling of it. `sort -V`
is GNU-only, and `sort -t. -k1,1n` silently compares nothing but the minor
field when the input is a path rather than a bare version, because the
directory prefix in field 1 reads as `0` under both BSD and GNU. `version_gt`
does it in bash for that reason; prefer it to adding a `sort` call.

**Anything printed to stdout on the passing path.** People pipe this into build
scripts. Keep failures and diagnostics on stderr. The text report is pinned
byte for byte by `test/golden/`, and with `--format json` stdout carries the
JSON object and nothing else. A new exit path goes through `cannot_verify` or
`finish`, so it reports in both formats. `cannot_verify` takes a finding id
first; reuse one from the README's "Finding ids" table where it fits, and add
a row there if a new one is needed.

## Scope

This reads an artifact and reports whether it meets the 16 KB page requirement.
It does not build anything, does not modify the artifact, and cannot repair an
unaligned library — relinking a `.so` that arrived prebuilt inside somebody
else's AAR is not something a checker can do, and pretending otherwise would be
the same failure as reporting a pass it did not earn.

Feature requests that fit: more places to find the toolchain, clearer failure
messages, support for artifact shapes that exist and are not handled. Feature
requests that do not: fixing alignment, wrapping Gradle, or guessing.

## Stay in touch

Don't forget to follow [@saimskywalker](https://github.com/saimskywalker) on
GitHub to see new releases and other open-source projects as they come out.
