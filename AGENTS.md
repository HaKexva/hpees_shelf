# AGENTS.md — project instructions for AI assistants

This file is the **Cursor project agent config** (same role as **`CLAUDE.md`** in Claude Code or similar tools in other IDEs). Cursor loads it for context and workflow.

## Git: never commit directly to `main`

- **Do not** commit, merge, or push directly to **`main`** for feature work or fixes.
- **Do** create a **branch** from `main`, push it, open a **pull request**, and merge via GitHub (or the user’s agreed PR flow).
- Treat **`main`** as updated only through merged PRs, not `git push origin main` from local feature work.

If the user explicitly asks to bypass this (e.g. hotfix), confirm before doing it.

## Development workflow

### When starting work

1. **Linear**
   - Prefer an existing Linear issue; if none, create one on the **HAK** team with:
     - **As a** / **I want to** / **So that**
   - For new issues: assign **ray120424@gmail.com** and add to the **hpees_shelf** project.
2. **Branch** — create or switch to a branch (e.g. `hak-XX-short-description`).
3. **PR** — when ready, open a PR with title **`[HAK-XX] ...`** matching the Linear key.

### When finishing

1. **Confirm with the user** that behavior and UI match expectations before merge.
2. **Lint** — run `bundle exec rubocop` and fix new offenses.
3. **Merge & Linear** — merge the PR into `main`, then mark the Linear issue **Done**.

### Language

- Use **English** for PR titles/descriptions, commit messages, and code comments.

### Summary

- One PR ≈ one Linear issue ≈ one focused change.
- Branch → PR → merge to `main`; no direct pushes to `main` for normal work.
