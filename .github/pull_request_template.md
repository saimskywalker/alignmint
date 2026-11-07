## What this changes

<!-- One or two sentences. What is different after this merges? -->

## Why

<!-- The problem it solves. If it fixes a bug, what was the symptom? -->

## Checklist

- [ ] `shellcheck android-16kb-check test/run.sh test/stubs/*` is clean
- [ ] `test/run.sh` passes
- [ ] If this fixes a bug: there is a test that fails without the fix
- [ ] If this changes what an exit code means: `CHANGELOG.md` says so, and the
      README table matches

### AI use

<!-- Using AI is welcome. Please tick one, naming the tool and model if you used AI; a reminder appears if it is missing. See CONTRIBUTING.md. -->

- [ ] None
- [ ] Some (tool or agent, and model: ...)
- [ ] Most (tool or agent, and model: ...)
- [ ] I have read and tested every line.

## If this touches the exit codes

The three-way exit code is the interface, so please say explicitly which of
`0`, `1` and `2` a caller would see differently after this change. In
particular: is there any new path that can reach `0` without having actually
read the artifact? That is the one direction this project will not go.

## What you ran it against

<!-- If you have a real APK or AAB to hand, paste the output. Redact paths if
     they are yours to redact. The suite runs on stubs, so a run against a real
     artifact is worth more than it looks. -->
