# Contributing to Perchfall

Thank you for your interest in contributing. All skill levels are welcome — whether this is your first open source contribution or your hundredth.

## Before you start

**Open an issue first.** Before writing any code, please open a GitHub issue describing what you want to do and why. This saves everyone time: it avoids duplicate work, surfaces design concerns early, and gives us a chance to agree on scope before you invest effort in an implementation.

The exception is typos and documentation fixes, which can go straight to a PR.

## Proposing a significant change

For anything that changes behavior, adds a new concept, or touches security — please propose it as a GitHub Discussion before opening an issue or PR. Structure your proposal like an ADR:

- **Context** — what problem are you solving, and why does it matter?
- **Options considered** — what alternatives did you weigh?
- **Decision** — what are you proposing, and why?
- **Consequences** — what does this make easier or harder?

You can look at the existing ADRs in [doc/adr/](doc/adr/) for examples of this format. Discussion lets the proposal get feedback before any code is written, and the thread becomes useful context for the eventual PR.

## Submitting a pull request

- Tests are required. If you're adding behavior, cover it. If you're fixing a bug, add a test that would have caught it.
- Rubocop must pass. Run `bundle exec rubocop` before pushing.
- Keep commits focused. One logical change per commit is easier to review and revert if needed.
- Update the CHANGELOG under `[Unreleased]` following the existing format.

## Response time

I'll do my best to respond to issues, discussions, and PRs in a reasonable time. This is a small project maintained by one person, so I appreciate your patience.

## Code of conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold it.
