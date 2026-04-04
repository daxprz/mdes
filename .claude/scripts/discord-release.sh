#!/bin/bash
# Post a release announcement to Discord via webhook.
#
# Usage: discord-release.sh <version> [--force]
#
# Reads:
#   /var/tumu/etc/discord.env     — DISCORD_WEBHOOK_URL
#   scripts/autoload/version.gd   — version confirmation
#   README.md                      — changelog bullets for this version
#   git log                        — commit hash, gate suite tags
#
# The message is a rich Discord embed with:
#   - Version number + title
#   - Changelog from README.md release notes
#   - Gate suite results
#   - Commit hash + timestamp

set -e

VERSION="${1:?Usage: discord-release.sh <version> [--force]}"
FORCE="${2:-}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Load webhook URL
ENV_FILE="/var/tumu/etc/discord.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found" >&2
    exit 1
fi
source "$ENV_FILE"

if [ -z "$DISCORD_WEBHOOK_URL" ]; then
    echo "Error: DISCORD_WEBHOOK_URL not set in $ENV_FILE" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

# Get commit info
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_DATE=$(git log -1 --format='%ci' | cut -d' ' -f1,2 | cut -d: -f1,2)

# Extract changelog for this version from README.md
# Looks for ### vX.Y.Z section and captures until next ### or ## heading
CHANGELOG=$(sed -n "/^### ${VERSION}$/,/^###\? /{ /^### ${VERSION}$/d; /^###\? /d; p; }" README.md | head -20)

if [ -z "$CHANGELOG" ]; then
    CHANGELOG="No release notes found for ${VERSION}"
fi

# Get gate suite status
GATE_STATUS=""
for suite in chained combat leaping scaling; do
    tag_commit=$(git rev-list -1 "ts/${suite}/pass" 2>/dev/null || echo "")
    head_commit=$(git rev-list -1 HEAD)
    if [ "$tag_commit" = "$head_commit" ]; then
        GATE_STATUS="${GATE_STATUS}✅ ${suite}  "
    elif [ -n "$tag_commit" ]; then
        GATE_STATUS="${GATE_STATUS}⚠️ ${suite} (stale)  "
    else
        tag_fail=$(git rev-list -1 "ts/${suite}/fail" 2>/dev/null || echo "")
        if [ -n "$tag_fail" ]; then
            GATE_STATUS="${GATE_STATUS}❌ ${suite}  "
        else
            GATE_STATUS="${GATE_STATUS}⬜ ${suite} (untested)  "
        fi
    fi
done

if [ -n "$FORCE" ]; then
    GATE_STATUS="⚠️ FORCED — gate checks skipped"
fi

# Escape for JSON
json_escape() {
    python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$1"
}

CHANGELOG_ESCAPED=$(json_escape "$CHANGELOG")
GATE_ESCAPED=$(json_escape "$GATE_STATUS")

# Build Discord embed
PAYLOAD=$(cat <<ENDJSON
{
  "embeds": [
    {
      "title": "🧁 DAX ${VERSION} Released",
      "color": 16750848,
      "fields": [
        {
          "name": "Changes",
          "value": ${CHANGELOG_ESCAPED},
          "inline": false
        },
        {
          "name": "Gate Suites",
          "value": ${GATE_ESCAPED},
          "inline": false
        },
        {
          "name": "Commit",
          "value": "\`${COMMIT_HASH}\`",
          "inline": true
        },
        {
          "name": "Date",
          "value": "${COMMIT_DATE}",
          "inline": true
        }
      ],
      "footer": {
        "text": "The Ultimate Muffin"
      }
    }
  ]
}
ENDJSON
)

# Post to Discord
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$DISCORD_WEBHOOK_URL")

if [ "$RESPONSE" = "204" ] || [ "$RESPONSE" = "200" ]; then
    echo "Posted release ${VERSION} to Discord"
else
    echo "Discord webhook failed with HTTP ${RESPONSE}" >&2
    echo "Payload:" >&2
    echo "$PAYLOAD" | python3 -m json.tool >&2
    exit 1
fi
