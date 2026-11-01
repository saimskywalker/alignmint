# Security policy

## Supported versions

Only the latest release line gets security fixes.

| Version | Supported |
|---|---|
| 1.0.x | yes |
| older | no |

## Reporting a vulnerability

Please do not open a public issue for a vulnerability.

Report it privately through GitHub's private vulnerability reporting: open the
[Security tab](https://github.com/saimskywalker/alignmint/security)
and choose "Report a vulnerability". Only the maintainer can see the report.

`android-16kb-check` extracts and reads APKs and AABs that may come from
someone else, so the interesting cases are things like a crafted archive that
writes outside the temporary directory, an entry name that ends up executed by
the shell, or an artifact that makes the check exit `0` without having
measured it.

Please include:

- what an attacker controls (the artifact, an environment variable, a path)
- the smallest artifact or command that shows it, or how to build one
- the output and exit code you saw, and what you expected
- the version (`android-16kb-check --version`), OS and bash version

You should hear back usually within a week. Once a fix is ready it is released
and the advisory is published, with credit to you unless you prefer otherwise.
