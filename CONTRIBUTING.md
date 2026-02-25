# Contributing

## Development workflow

### When starting work

1. **Linear issue**
   - Check if a Linear issue exists for the work.
   - If **no** issue exists, create one in the HAK team using this format:
     - **As a** (who wants to accomplish something)
     - **I want to** (what they want to accomplish)
     - **So that** (why they want to accomplish that thing)
   - When creating a new Linear issue, remember to:
     - **Assign** to ray120424@gmail.com
     - **Add to** the **hpees_shelf** project

2. **Branch**
   - Create or switch to a branch for the work (e.g. `hak-XX-short-description` or use the issue identifier).

3. **Pull request**
   - Open a PR when the work is ready.
   - PR title must start with the Linear issue key: **`[HAK-XX]`** followed by a short description.  
     Example: `[HAK-21] Add book tag filter in book page`
   - **One thing per PR:** Each PR should do exactly one thing and link to one Linear issue (use the subissue/child if applicable).

### Language
- Use **English** for PR description, commit messages, and comments inside source files.

### When finishing work

1. **Confirm with the user**
   - Before merging, confirm with the user that the implemented behavior and UI are correct.

2. **Lint**
   - Run `bundle exec rubocop` and ensure there are no new lint errors.

3. **Merge**
   - Merge the PR into `main`.

4. **Linear**
   - Mark the linked Linear issue as **Done**.

---

## Quick reference

- **PR title format:** `[HAK-XX] <short description>`
- **One PR = one Linear issue = one change.** Do not bundle unrelated changes in a single PR.
