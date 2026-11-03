# Releasing

**A release is started by a person, everything else is automatic.** You decide *when* (and whether it is a patch,
minor or major version); the workflow decides nothing and skips no check.

## How to release
1. Make sure `main` contains what you want to ship (and is green).
2. GitHub → **Actions → Release → Run workflow** on `main`, or from a terminal:
   ```
   gh workflow run release.yml -f bump=minor            # patch (default) | minor | major
   gh workflow run release.yml -f version=v1.0.0        # an explicit version instead of a bump
   gh workflow run release.yml -f dry_run=true          # show the version and release notes, publish nothing
   gh workflow run release.yml -f draft=true            # create a draft release you publish by hand
   ```
3. That's it. The run takes as long as the test suite (~10 minutes).

## What the workflow does
```
plan ──► build (build.yml)  ─┐
     └─► tests (tests.yml)  ─┴─► release ──► verify
```
1. **plan** – works out the next version from the latest `vX.Y.Z` git tag (`scripts/releasing/next_version.sh`; it
   refuses a version that already exists or is not newer). Only runs from `main`.
2. **build + tests** – the *same* workflows that gate every pull request, run on the exact commit being released. A red
   test means no release. The `plugin.wasm` they build is the one that gets published (it is never rebuilt).
3. **release** – writes the notes (the sha256, a ready-to-paste sqlc config, and GitHub's generated list of merged pull
   requests, grouped by label as configured in `.github/release.yml`), then creates the tag and the GitHub release with
   `sqlc-gen-ruby.wasm` and `sqlc-gen-ruby.wasm.sha256` attached.
4. **verify** – plays the user: downloads the plugin from the release's public URL, checks the sha256 and runs
   `sqlc diff` with it over the examples. If this fails, fix forward and release again (a published tag is not rewritten).

## Versioning
[Semantic versioning](https://semver.org), tags are `vMAJOR.MINOR.PATCH`. The version describes **the generated
code and the options**, because that is what users depend on:

| Bump | When |
|---|---|
| patch | bug fixes; output changes that cannot break callers (comments, formatting, a fixed type) |
| minor | new options, new query features, new drivers; output that only adds API (e.g. a new method) |
| major | existing generated method signatures, constants or options change incompatibly |

Label pull requests `bug`, `enhancement` or `documentation` (`breaking` for incompatible changes, `skip-changelog` to
hide one; create those two labels the first time they are needed) so the generated notes
are grouped sensibly, and pick the bump from the labels of what is merged since the last release.

## Using a release
```yaml
plugins:
- name: ruby
  wasm:
    url: https://github.com/DaredevilOSS/sqlc-gen-ruby/releases/download/v0.1.0/sqlc-gen-ruby.wasm
    sha256: <the sha256 in the release notes>
```

## If something goes wrong
* *Dry run first when unsure:* `-f dry_run=true` runs the whole gate and prints the notes without publishing.
* *A published release is bad:* mark it as a pre-release or delete the release **and** its tag in the GitHub UI, then fix
  and release the next version. Do not re-use a version number: users pin the sha256 of a version.
* *The workflow cannot find a tag / wrong version:* the version comes from `git tag`; check that tags are intact
  (`git ls-remote --tags origin`).
