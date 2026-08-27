# Repository Settings

## Authority

Live GitHub repository settings enforce this policy. `.github/github.json`
records the expected state in the shared repository-metadata schema. Current
snapshot automation verifies merged-branch deletion and exposes the live
default branch; merge-method and protection drift still require a live GitHub
settings check. This document explains the human-facing intent.

Repository documentation is canonical. The GitHub wiki is disabled to avoid a
second, drifting documentation surface.

## Merge Policy

Pull requests merge with normal merge commits. Squash and rebase merges are
disabled. This matches the established convention in the owner's maintained
repositories and preserves the reviewed branch history as one integration
unit.

GitHub deletes merged remote branches automatically. Local merged branches and
clean merged worktrees are removed during normal closeout.

## Default-Branch Protection

`main` is protected with these rules:

- changes require a pull request;
- the `validation` and `Analyze Swift` status checks are required and must be
  current with `main`;
- administrators follow the same protection rules;
- review conversations must be resolved;
- force pushes and branch deletion are blocked; and
- linear history is not required because merge commits are the repository
  convention.

GitHub does not require an approving review for this single-maintainer project.
Issue-specific independent review requirements remain part of the owning plan
or pull request and are not replaced by the branch rule.

## Validation

The stable required build check is the `validation` job in the `Validation`
workflow. It runs `scripts/check.sh`, which includes Swift tests, secret checks,
shell and workflow linting, immutable GitHub Action pin checks, repository
metadata and Dependabot syntax checks, plist and entitlement validation, diff
checks, Xcode project generation, Debug tests, and Release and App Store builds.

Real-device tests remain opt-in and never block public continuous integration.

## Security Automation And Reporting

The `CodeQL` workflow analyzes Swift on pull requests, pushes to `main`, a
weekly schedule, and manual dispatch. It uses manual build tracing around the
repository's deterministic XcodeGen-generated macOS application build. The
`Analyze Swift` job is a required status check. CodeQL and checkout actions are
pinned to immutable commit SHAs and maintained through Dependabot.

Suspected vulnerabilities must be reported through GitHub Private
Vulnerability Reporting rather than public issues. `SECURITY.md` defines the
supported-version posture, safe evidence requirements, response expectations,
and project-specific security scope.

## Dependency Maintenance

Dependabot checks Swift Package Manager and GitHub Actions weekly. It groups
routine and security updates by ecosystem and limits concurrent pull requests
to keep review noise bounded.

XcodeGen is installed from Homebrew during GitHub-hosted runs. `project.yml`
enforces the minimum supported XcodeGen version, and runner-image migration
pull requests provide the compatibility checkpoint for newer formula versions.

Third-party GitHub Actions must use immutable 40-character commit SHAs. A
release-tag comment keeps each pin readable, while Dependabot proposes future
pin updates through normal pull requests.

## Runner Image Refresh Policy

Validation and CodeQL use the explicit `macos-15` GitHub-hosted image. They do
not use `macos-latest`, because an explicit image keeps Xcode and Swift changes
reviewable instead of allowing the toolchain to move without a repository
change.

Maintainers review the image baseline quarterly and sooner when GitHub announces
an image deprecation or removal, CI emits retirement warnings, the required
Xcode or Swift baseline changes, or Apple distribution requirements change.

An image migration uses a focused task-branch pull request. The candidate image
must pass `scripts/check.sh`, CodeQL, and any then-current signing or release
checks before Validation and CodeQL move together. The previous image is a
rollback option only while GitHub still supports it; the repository does not
carry a permanent compatibility matrix for retired images.

If an image retirement prevents the required check from starting, maintainers
update the workflow on a governance task branch first. Branch protection stays
enabled whenever a runnable required check exists. Any unavoidable temporary
protection change must be recorded, narrowly scoped, and restored immediately
after the replacement image produces a green run.

## Intentional Omissions

- `CODEOWNERS` is unnecessary while the repository has one maintainer and no
  code-owner review requirement.
- A pull-request template is not required while the repository has one stable
  validation command and plan issues carry device-evidence requirements.
- Release and distribution workflows remain out of scope until the product has
  a downloadable release candidate.
