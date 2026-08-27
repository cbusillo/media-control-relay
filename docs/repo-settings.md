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
- the `validation` status check is required and must be current with `main`;
- administrators follow the same protection rules;
- review conversations must be resolved;
- force pushes and branch deletion are blocked; and
- linear history is not required because merge commits are the repository
  convention.

GitHub does not require an approving review for this single-maintainer project.
Issue-specific independent review requirements remain part of the owning plan
or pull request and are not replaced by the branch rule.

## Validation

The stable required check is the `validation` job in the `Validation` workflow.
It runs `scripts/check.sh`, which includes Swift tests, secret checks, shell and
workflow linting, immutable GitHub Action pin checks, repository metadata and
Dependabot syntax checks, plist and entitlement validation, diff checks, Xcode
project generation, Debug tests, and Release and App Store builds.

Real-device tests remain opt-in and never block public continuous integration.

## Dependency Maintenance

Dependabot checks Swift Package Manager and GitHub Actions weekly. It groups
routine and security updates by ecosystem and limits concurrent pull requests
to keep review noise bounded.

Third-party GitHub Actions must use immutable 40-character commit SHAs. A
release-tag comment keeps each pin readable, while Dependabot proposes future
pin updates through normal pull requests.

## Intentional Omissions

- `CODEOWNERS` is unnecessary while the repository has one maintainer and no
  code-owner review requirement.
- A pull-request template is not required while the repository has one stable
  validation command and plan issues carry device-evidence requirements.
- Release and distribution workflows remain out of scope until the product has
  a downloadable release candidate.
