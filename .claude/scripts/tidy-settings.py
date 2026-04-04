#!/usr/bin/env python3
"""
Tidy Claude Code settings files.

Triggered by PostToolUse hook on Write|Edit of settings files.
Enforces separation between shared (settings.json) and personal (settings.local.json).

Rules:
  settings.json (shared, committed):
    - General bash commands, project MCP tools, web domains, deny rules
    - NO absolute /Users/* paths
    - NO account-specific IDs (ADHI6MoVcbKkX_LYFtkqaA, AZqVDbVBeXaYUYL9ZZCJzQ, etc.)
    - NO personal MCP tools (Gmail, etc.)

  settings.local.json (personal, gitignored):
    - Machine-specific paths (/Users/*, /home/*)
    - Account-specific paths (contains account IDs)
    - Personal MCP tools
    - Personal additionalDirectories with absolute paths
    - NO general bash commands (those belong in shared)
    - NO project MCP tools (those belong in shared)
"""

import json
import re
import sys
from pathlib import Path

# --- Classification rules ---

# Patterns that indicate a PERSONAL entry (belongs in settings.local.json)
PERSONAL_PATTERNS = [
    re.compile(r'/Users/'),
    re.compile(r'/home/'),
    re.compile(r'ADHI6MoVcbKkX_LYFtkqaA'),
    re.compile(r'AZqVDbVBeXaYUYL9ZZCJzQ'),
    re.compile(r'//private/var/olai/accounts/'),
    re.compile(r'//var/olai/accounts/'),
    re.compile(r'mcp__claude_ai_Gmail'),
]

# Patterns that indicate JUNK (should be removed entirely)
JUNK_PATTERNS = [
    re.compile(r'^Bash\(__NEW_LINE_'),           # Auto-approve artifacts
    re.compile(r'^Bash\(fi\)$'),                 # Shell fragments
    re.compile(r'^Bash\(do\)$'),
    re.compile(r'^Bash\(do echo'),
    re.compile(r'^Bash\(do mkdir'),
    re.compile(r'^Bash\(for d'),
    re.compile(r'^Bash\(/dev/null echo'),
    re.compile(r'^Bash\(echo === \$'),
    re.compile(r'^Bash\(done\)$'),
]

# Legacy colon syntax pattern
COLON_SYNTAX = re.compile(r'^(Bash\([^)]+):(\*\))$')


def is_comment(entry: str) -> bool:
    return entry.startswith('//')


def is_personal(entry: str) -> bool:
    return any(p.search(entry) for p in PERSONAL_PATTERNS)


def is_junk(entry: str) -> bool:
    return any(p.search(entry) for p in JUNK_PATTERNS)


def fix_colon_syntax(entry: str) -> str:
    """Migrate Bash(cmd:*) -> Bash(cmd *)"""
    m = COLON_SYNTAX.match(entry)
    if m:
        return f"{m.group(1)} {m.group(2)}"
    return entry


def find_redundant(entries: list[str]) -> set[int]:
    """Find indices of entries made redundant by broader entries."""
    redundant = set()
    non_comment = [(i, e) for i, e in enumerate(entries) if not is_comment(e)]

    for i, entry in non_comment:
        if not entry.startswith('Bash('):
            continue
        # Extract the command prefix (everything before the closing paren)
        inner = entry[5:-1] if entry.endswith(')') else None
        if not inner:
            continue

        for j, other in non_comment:
            if i == j or j in redundant:
                continue
            if not other.startswith('Bash('):
                continue
            other_inner = other[5:-1] if other.endswith(')') else None
            if not other_inner:
                continue

            # Check if 'other' is a broader version of 'entry'
            # e.g., "git *" makes "git add *", "git -C /path add *" redundant
            if other_inner.endswith(' *') or other_inner.endswith('*'):
                prefix = other_inner.rstrip('*').rstrip()
                if prefix and inner.startswith(prefix) and i != j:
                    # other is broader — entry is redundant
                    redundant.add(i)

    return redundant


def deduplicate(entries: list[str]) -> list[str]:
    """Remove exact duplicates while preserving order and comments."""
    seen = set()
    result = []
    for entry in entries:
        if is_comment(entry):
            result.append(entry)
            continue
        if entry not in seen:
            seen.add(entry)
            result.append(entry)
    return result


def clean_empty_sections(entries: list[str]) -> list[str]:
    """Remove section headers that have no entries after them."""
    result = []
    i = 0
    while i < len(entries):
        if is_comment(entries[i]) and '====' in entries[i]:
            # Look ahead: collect consecutive comment lines (header block)
            header_block = []
            j = i
            while j < len(entries) and is_comment(entries[j]):
                header_block.append(entries[j])
                j += 1
            # Check if next non-comment entry exists before next header
            has_entries = False
            k = j
            while k < len(entries):
                if is_comment(entries[k]) and '====' in entries[k]:
                    break
                if not is_comment(entries[k]):
                    has_entries = True
                    break
                k += 1
            if has_entries:
                result.extend(header_block)
            i = j
        else:
            result.append(entries[i])
            i += 1
    return result


def classify_additional_dirs(dirs: list[str]) -> tuple[list[str], list[str]]:
    """Split additional directories into shared (relative) and personal (absolute)."""
    shared = []
    personal = []
    for d in dirs:
        if any(p.search(d) for p in PERSONAL_PATTERNS) or d.startswith('/'):
            personal.append(d)
        else:
            shared.append(d)
    return shared, personal


def tidy(project_root: str) -> dict:
    """Tidy both settings files. Returns a report dict."""
    shared_path = Path(project_root) / '.claude' / 'settings.json'
    local_path = Path(project_root) / '.claude' / 'settings.local.json'

    report = {
        'junk_removed': 0,
        'colon_migrated': 0,
        'duplicates_removed': 0,
        'redundant_removed': 0,
        'moved_to_local': 0,
        'moved_to_shared': 0,
        'issues': [],
    }

    # Load files
    shared_data = {}
    local_data = {}

    if shared_path.exists():
        with open(shared_path) as f:
            shared_data = json.load(f)

    if local_path.exists():
        with open(local_path) as f:
            local_data = json.load(f)

    shared_allow = shared_data.get('permissions', {}).get('allow', [])
    local_allow = local_data.get('permissions', {}).get('allow', [])

    # --- Phase 1: Remove junk from both ---
    new_shared = []
    for entry in shared_allow:
        if is_comment(entry):
            new_shared.append(entry)
        elif is_junk(entry):
            report['junk_removed'] += 1
        else:
            new_shared.append(entry)

    new_local = []
    for entry in local_allow:
        if is_comment(entry):
            new_local.append(entry)
        elif is_junk(entry):
            report['junk_removed'] += 1
        else:
            new_local.append(entry)

    # --- Phase 2: Fix colon syntax ---
    for i, entry in enumerate(new_shared):
        if not is_comment(entry):
            fixed = fix_colon_syntax(entry)
            if fixed != entry:
                report['colon_migrated'] += 1
                new_shared[i] = fixed

    for i, entry in enumerate(new_local):
        if not is_comment(entry):
            fixed = fix_colon_syntax(entry)
            if fixed != entry:
                report['colon_migrated'] += 1
                new_local[i] = fixed

    # --- Phase 3: Move misplaced entries ---
    # Personal entries in shared → move to local
    move_to_local = []
    keep_shared = []
    for entry in new_shared:
        if is_comment(entry):
            keep_shared.append(entry)
        elif is_personal(entry):
            move_to_local.append(entry)
            report['moved_to_local'] += 1
            report['issues'].append(f'Moved to local: {entry}')
        else:
            keep_shared.append(entry)

    # Generic entries in local → move to shared (only Bash, MCP project tools, core tools)
    move_to_shared = []
    keep_local = []
    for entry in new_local:
        if is_comment(entry):
            keep_local.append(entry)
        elif is_personal(entry):
            keep_local.append(entry)  # Correctly placed
        elif entry.startswith('Bash(') or entry.startswith('mcp__olai__') or \
             entry.startswith('mcp__ide__') or entry in ('Edit', 'Read', 'Write', 'WebSearch') or \
             entry.startswith('WebFetch('):
            move_to_shared.append(entry)
            report['moved_to_shared'] += 1
            report['issues'].append(f'Moved to shared: {entry}')
        else:
            keep_local.append(entry)

    # Merge
    new_shared = keep_shared + move_to_shared
    new_local = keep_local + move_to_local

    # --- Phase 4: Deduplicate ---
    before_shared = len([e for e in new_shared if not is_comment(e)])
    new_shared = deduplicate(new_shared)
    after_shared = len([e for e in new_shared if not is_comment(e)])
    report['duplicates_removed'] += before_shared - after_shared

    before_local = len([e for e in new_local if not is_comment(e)])
    new_local = deduplicate(new_local)
    after_local = len([e for e in new_local if not is_comment(e)])
    report['duplicates_removed'] += before_local - after_local

    # --- Phase 5: Remove redundant entries ---
    redundant_shared = find_redundant(new_shared)
    if redundant_shared:
        report['redundant_removed'] += len(redundant_shared)
        new_shared = [e for i, e in enumerate(new_shared) if i not in redundant_shared]

    redundant_local = find_redundant(new_local)
    if redundant_local:
        report['redundant_removed'] += len(redundant_local)
        new_local = [e for i, e in enumerate(new_local) if i not in redundant_local]

    # --- Phase 6: Clean empty sections ---
    new_shared = clean_empty_sections(new_shared)
    new_local = clean_empty_sections(new_local)

    # --- Phase 7: Tidy additionalDirectories ---
    shared_perm_dirs = shared_data.get('permissions', {}).get('additionalDirectories', [])
    local_perm_dirs = local_data.get('permissions', {}).get('additionalDirectories', [])
    # Top-level additionalDirectories are relative (shared) — leave them alone

    # Shared perm dirs should not have personal paths
    shared_dirs_clean = []
    for d in shared_perm_dirs:
        if any(p.search(d) for p in PERSONAL_PATTERNS) or (d.startswith('/') and not d.startswith('/var/olai')):
            if d not in local_perm_dirs:
                local_perm_dirs.append(d)
            report['moved_to_local'] += 1
        else:
            shared_dirs_clean.append(d)

    # Deduplicate dirs
    local_perm_dirs = list(dict.fromkeys(local_perm_dirs))

    # --- Write back ---
    shared_data.setdefault('permissions', {})['allow'] = new_shared
    if shared_dirs_clean:
        shared_data['permissions']['additionalDirectories'] = shared_dirs_clean
    elif 'additionalDirectories' in shared_data.get('permissions', {}):
        del shared_data['permissions']['additionalDirectories']

    local_data.setdefault('permissions', {})['allow'] = new_local
    if local_perm_dirs:
        local_data['permissions']['additionalDirectories'] = local_perm_dirs

    # Preserve deny and other keys
    if shared_path.exists():
        with open(shared_path, 'w') as f:
            json.dump(shared_data, f, indent=2, ensure_ascii=False)
            f.write('\n')

    if local_path.exists():
        with open(local_path, 'w') as f:
            json.dump(local_data, f, indent=2, ensure_ascii=False)
            f.write('\n')

    return report


def main():
    # Read hook input from stdin
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        hook_input = {}

    # Check if the edited file is a settings file
    file_path = hook_input.get('tool_input', {}).get('file_path', '')
    if not file_path:
        # Also check for 'path' key (Write tool uses 'file_path', Edit uses 'file_path')
        file_path = hook_input.get('tool_input', {}).get('path', '')

    if not ('settings.json' in file_path or 'settings.local.json' in file_path):
        sys.exit(0)  # Not a settings file, nothing to do

    # Find project root (walk up from the file)
    p = Path(file_path).resolve()
    project_root = None
    for parent in [p] + list(p.parents):
        if (parent / '.claude').is_dir():
            project_root = str(parent)
            break

    if not project_root:
        sys.exit(0)

    report = tidy(project_root)

    # If changes were made, output a summary for Claude's context
    total_changes = (
        report['junk_removed'] +
        report['colon_migrated'] +
        report['duplicates_removed'] +
        report['redundant_removed'] +
        report['moved_to_local'] +
        report['moved_to_shared']
    )

    if total_changes > 0:
        summary = {
            'additionalContext': (
                f"[tidy-settings] Auto-cleaned settings files: "
                f"{report['junk_removed']} junk removed, "
                f"{report['colon_migrated']} colon syntax migrated, "
                f"{report['duplicates_removed']} duplicates removed, "
                f"{report['redundant_removed']} redundant rules removed, "
                f"{report['moved_to_local']} moved to local, "
                f"{report['moved_to_shared']} moved to shared."
            )
        }
        if report['issues']:
            summary['additionalContext'] += '\nDetails: ' + '; '.join(report['issues'][:10])
        json.dump(summary, sys.stdout)


if __name__ == '__main__':
    main()
