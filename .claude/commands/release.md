---
description: Tag, push, and release the current version — requires all gate suites passing at HEAD
---

# Release

Push the current commit, create a version tag, and push it. Only proceeds if all gate suites pass at HEAD.

## Steps

### 1. Pre-flight Checks

Read the current version from `scripts/autoload/version.gd` and build the tag name `vMAJOR.MINOR.PATCH`.

Verify there are NO uncommitted changes:
```bash
git status --porcelain
```
If dirty, STOP: "Uncommitted changes — run /ship-it first."

### 2. Verify Gate Suites

Check that ALL gate suites have a `ts/<suite>/pass` tag pointing at HEAD:

```bash
for suite in chained combat leaping scaling; do
  tag=$(git tag -l "ts/$suite/pass")
  if [ -z "$tag" ]; then
    echo "MISSING: ts/$suite/pass"
  else
    tag_commit=$(git rev-list -1 "$tag")
    head_commit=$(git rev-list -1 HEAD)
    if [ "$tag_commit" != "$head_commit" ]; then
      echo "STALE: ts/$suite/pass is at $(echo $tag_commit | head -c 7), HEAD is $(echo $head_commit | head -c 7)"
    fi
  fi
done
```

If ANY gate suite is missing or stale, STOP with:
> "Gate suites not passing at HEAD. Run /test-gate first."

List which suites are blocking.

### 3. Check Tag Doesn't Already Exist

```bash
git tag -l "vX.Y.Z"
```

If the tag already exists, STOP: "Tag vX.Y.Z already exists. Bump the version in version.gd first."

### 4. Push, Tag, Push Tag

```bash
git push origin trunk
git tag -a "vX.Y.Z" -m "vX.Y.Z"
git push origin "vX.Y.Z"
```

### 5. Report

Print:
```
Released vX.Y.Z
  Commit: <hash>
  Gate suites: chained PASS, combat PASS, leaping PASS, scaling PASS
  Tag: vX.Y.Z pushed to origin
```
