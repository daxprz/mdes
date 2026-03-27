---
description: Update docs, bump patch version, write release notes, and commit
---

# Ship It

Prepare a clean release: update all documentation, bump the patch version if needed, write release notes, and commit everything.

## Steps

### 1. Gather Context

Read the current state:
- `scripts/autoload/version.gd` — current MAJOR.MINOR.PATCH
- `git tag --sort=-creatordate | head -1` — latest release tag
- `git diff --stat` — all uncommitted changes
- `git log --oneline $(git describe --tags --abbrev=0)..HEAD` — commits since last tag

Compare the PATCH in `version.gd` against the latest tag. If they match (no bump since last release), increment PATCH by 1 in `version.gd`.

### 2. Update Documentation

Read and update ALL relevant docs based on the uncommitted changes:

- **Design docs** (`docs/design/quadruped_monster.md`) — update if monster behavior, skeleton, scaling, or combat changed
- **EPIC docs** (`docs/epics/`) — update status of any stories/tasks that were completed or progressed
- **CLAUDE.md** — update Important Files table if new files were added

Only update docs that are affected by the actual changes. Don't touch docs for unrelated systems. Keep updates succinct — document WHAT changed, not every line of code.

### 3. Update README.md Release Notes

Add a new version section under `## Release Notes` in `README.md`, ABOVE the previous version entry. Follow the existing format:

```markdown
### vX.Y.Z
**One-line summary of changes**

- Bullet point per notable change (keep to 5-15 bullets)
- Group related changes under bold sub-headers if there are many
- Focus on user-visible behavior, not implementation details
```

### 4. Copy Test Results Forward

After bumping the version, copy the latest test results from the old version to the new version directory. This preserves result validity across version bumps (script hashes still validate content).

```bash
OLD_VER="X.Y.Z"  # The version BEFORE the bump
NEW_VER="X.Y.W"  # The new version
BASE="$HOME/Library/Application Support/Godot/app_userdata/The Ultimate Muffin/test-output"
if [ -d "$BASE/$OLD_VER" ]; then
  for test_dir in "$BASE/$OLD_VER"/*/; do
    test_name=$(basename "$test_dir")
    latest=$(ls -1 "$test_dir" | sort | tail -1)
    if [ -n "$latest" ] && [ -d "$test_dir/$latest" ]; then
      mkdir -p "$BASE/$NEW_VER/$test_name/$latest"
      cp "$test_dir/$latest/results.json" "$BASE/$NEW_VER/$test_name/$latest/" 2>/dev/null
      cp "$test_dir/$latest/test.json" "$BASE/$NEW_VER/$test_name/$latest/" 2>/dev/null
    fi
  done
  echo "Copied test results: $OLD_VER → $NEW_VER"
fi
```

### 5. Commit

Stage and commit ALL changes (code + docs + version bump + README) in a single commit:

```
git add -A
git commit -m "Release vX.Y.Z — <short summary>"
```

Use the version number from step 1. The commit message should be concise (under 72 chars).

Do NOT push or tag — the user will do that manually if they want to.

### 6. Report

Print a summary:
- Version: old → new
- Files changed (count)
- Commit hash
- Reminder: `git push && git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z` if they want to release
