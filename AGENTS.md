# AGENTS.md

Rules for AI coding agents working in this repository. People should read
[CONTRIBUTING.md](CONTRIBUTING.md); everything here applies to them too. The
`PR rules` check enforces the rules marked (checked); a pull request that
breaks one cannot be merged.

## What alignmint is

One bash script, `android-16kb-check`, that reads an `.apk` or `.aab` and
reports whether it meets Google Play's 16 KB page-size requirement. Its exit
code is the interface: `0` aligned, `1` unaligned, `2` could not verify.
`test/run.sh` tests it against stubbed tools (`test/stubs/`) and tiny archives
(`test/fixtures/`), with no Android SDK.

Read before you touch:

- anything: the "The exit codes are the interface" and "Things to be careful
  with" sections of CONTRIBUTING.md.
- a test: "What a good bug fix looks like" in CONTRIBUTING.md and
  `test/fixtures/README.md`.
- the output: `test/golden/` pins the text report byte for byte; the README
  "Finding ids" table and `test/check-json.py` pin `--format json`.

## Commands

Every one of these must pass before you open or update a pull request. CI
(`.github/workflows/ci.yml`, on `ubuntu-latest`) runs the same ones:

```bash
shellcheck android-16kb-check test/run.sh test/stubs/*
test/run.sh
test -x android-16kb-check && ./android-16kb-check --help > /dev/null
./android-16kb-check --ndk /nonexistent-ndk test/fixtures/sample.apk; echo $?   # must print 2
```

CI also parses several `--format json` runs with `test/check-json.py` (the
"--format json output parses" step). CI's shellcheck is 0.9; see CONTRIBUTING.md
for how its codes differ from a current one.

Run the tests whose name contains a word while iterating: `test/run.sh golden`.

## Stop and ask the human

Some things must come from the real world. An agent must never invent them.
Stop and ask the person you work for to provide them:

- **Real tool output.** What `llvm-objdump -p`, `zipalign`, `bundletool` or
  `unzip` print and which exit codes they return, with the tool and version.
  A stub copies real output (see `test/stubs/zipalign`); never write a stub
  from memory or guess an exit code.
- **Real artifacts and Play results.** A claim that Play rejects or accepts an
  artifact, or that a real APK or AAB passes, comes from a real run on a real
  file. Fixtures only mimic the layout and are invented; never commit an app
  that is not yours.
- **The requirement itself.** Cite the Android developer documentation for
  what Play requires. If you cannot find it, say so; do not guess.
- **An accepted issue.** If the change has no issue labelled `accepted`, stop
  and ask the human to open one and wait for a maintainer.

## Code

- **English only** for code, identifiers, comments, commit messages and docs.
  Answer the person you work for in their language.
- Target bash 3.2, the `/bin/bash` macOS ships, and Linux. The script and
  `test/run.sh` must not need jq or Python.
- No new path may reach exit `0` without reading the artifact. New exit paths
  go through `cannot_verify` or `finish`; diagnostics go to stderr.
- Comments are sparse: only where the code is not self-evident. Do not add
  comments to code you did not change.

## Tests (checked)

- Every change to `android-16kb-check` comes with a test change under `test/`:
  a `t_<name>` function and a `check` line in `test/run.sh`. A bug fix has a
  test that fails without the fix; check that it does before you open the
  pull request.
- Tests use the stubs and fixtures; never make the suite need an Android SDK,
  a JDK or a real APK.

## Never

- Never silence shellcheck (checked): no new `# shellcheck disable` lines, no
  `.shellcheckrc`. Fix the finding instead. Only a maintainer can waive this,
  with the `suppression-ok` label.
- Never delete, skip, loosen or rewrite an existing test, golden file or
  fixture to make CI pass. If a test looks wrong, say so in the issue.
- Never change what an exit code means, rename a finding id or `--format json`
  field, or change a flag. Scripts and CI jobs depend on them.
- Never change `VERSION` in `android-16kb-check`, edit a released
  `CHANGELOG.md` section, tag or release. Add your entry under
  `## [Unreleased]` in `CHANGELOG.md`.
- Never add a dependency or change CI workflows unless the issue asks for it.
- Never add unrelated "improvements": no drive-by refactors, renames,
  reformatting of untouched code or dead code.
- Never open pull requests, issues or comments on your own. The human reviews
  your work and posts it.

## Pull requests (checked)

- First an issue, labelled `accepted` by a maintainer. The pull request says
  `Closes #N`.
- One issue per pull request, at most 400 changed lines.
- At most 2 open pull requests per person.
- Fill in the pull request template, including `### AI use` with the tool and
  model.
- The person submitting has read, run and understood every line, and writes
  the description in their own words. Pull requests that are raw, unreviewed
  agent output will be closed.
