# Claude Code Instructions for resurrect.wezterm

## Repository Structure

This is a fork of MLFlexer/resurrect.wezterm. The upstream repo is NOT owned by us.

## CRITICAL: Pull Request Policy

**NEVER create pull requests to the upstream repository (MLFlexer/resurrect.wezterm).**

All PRs must target this fork's main branch:
- Correct: `gh pr create --repo gcc42/resurrect.wezterm`
- WRONG: `gh pr create --repo MLFlexer/resurrect.wezterm`

## Git Workflow

1. Create feature branches from main
2. Push to origin (this fork)
3. Create PRs targeting `gcc42/resurrect.wezterm` main branch
4. Squash merge, then delete the feature branch
5. NEVER force push unless explicitly approved by the user

## Commit Guidelines

- No Claude/Anthropic attribution in commits or PRs
- No Co-Authored-By lines mentioning Claude or Anthropic

## Quality Gates

Run before committing:
```bash
make all  # Runs: fix → lint → check → test
```

All lint checks and tests must pass.

## Code Style

- Tabs for indentation (width 4)
- 120 character line limit
- LuaLS type annotations required on all functions
- All code must be as declarative, functional and simple as possible
- Use the functional core imperative shell pattern to separate the IO from the core
- Keep the robustness and error handling in mind
