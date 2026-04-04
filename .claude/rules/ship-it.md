## Ship-It Overrides — TUMU/DAX

### Version Source
File: `scripts/autoload/version.gd`
Pattern: `const PATCH := (\d+)` — increment PATCH by 1

### Pre-flight
Run gate suite check: verify all `ts/*/pass` tags point at HEAD.
Gate suites: `chained`, `combat`, `leaping`, `scaling`
Skip with `--force`.

### Test Results
After bumping version, copy test results from old version dir to new:
```bash
OLD_VER="X.Y.Z"
NEW_VER="X.Y.W"
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
fi
```

### Docs to Update
- `README.md` — add version section under `## Release Notes`
- `docs/design/*.md` — update if monster behavior, skeleton, scaling, or combat changed
- `docs/epics/*.md` — update status of completed stories
- `CLAUDE.md` — update Important Files table if new files added

### Post-Release
```bash
bash .claude/scripts/discord-release.sh "<version>"
```
If webhook not configured, warn but don't fail.

### Git
Remote: `origin`
Branch: `trunk`
