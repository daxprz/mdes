---
description: Tag, push, and release the current version — requires all gate suites passing at HEAD
argument-hint: [-f|force] (skip gate suite check)
---

# Release

Push the current commit, create a version tag, and push it. Only proceeds if all gate suites pass at HEAD — unless forced.

## Steps

### 1. Check for Force Flag

If `$ARGUMENTS` contains `-f` or `force`, set FORCE mode. Skip step 2 (gate suite verification) and print a warning:
> "FORCE RELEASE — skipping gate suite verification."

### 2. Pre-flight Checks

Read the current version from `scripts/autoload/version.gd` and build the tag name `vMAJOR.MINOR.PATCH`.

Verify there are NO uncommitted changes:
```bash
git status --porcelain
```
If dirty, STOP: "Uncommitted changes — run /ship-it first." (This check applies even with force.)

### 3. Verify Gate Suites (skip if FORCE)

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
> "Gate suites not passing at HEAD. Run /test-gate first, or use /release force to skip."

### 4. Check Tag Doesn't Already Exist

```bash
git tag -l "vX.Y.Z"
```

If the tag already exists, STOP: "Tag vX.Y.Z already exists. Bump the version in version.gd first."

### 5. Push, Tag, Push Tag

```bash
git push origin trunk
git tag -a "vX.Y.Z" -m "vX.Y.Z"
git push origin "vX.Y.Z"
```

### 6. Post to Discord

Announce the release to Discord:
```bash
bash .claude/scripts/discord-release.sh "vX.Y.Z"
```

If forced, pass the flag:
```bash
bash .claude/scripts/discord-release.sh "vX.Y.Z" --force
```

If the webhook URL isn't configured (`/var/tumu/etc/discord.env`), this will print an error but NOT block the release — the tag is already pushed. Tell the user to configure the webhook.

### 7. Report

Print:
```
Released vX.Y.Z
  Commit: <hash>
  Gate suites: chained PASS, combat PASS, leaping PASS, scaling PASS  (or "SKIPPED (force)" if forced)
  Tag: vX.Y.Z pushed to origin
  Discord: posted (or "skipped — webhook not configured")
```
