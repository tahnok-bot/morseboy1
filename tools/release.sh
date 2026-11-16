#!/bin/sh
# release.sh — create a Gitea release of the ROM built from the current SHA.
#
# Usage: tools/release.sh [tag] [release name]
#
#   tag           tag for the release; default g<short-sha> (e.g. g0a98d63)
#   release name  display name; default "morseboy1 <tag>"
#
# Env:
#   GITEA_URL     Gitea base URL   (default http://10.66.0.1:3000)
#   GITEA_REPO    owner/repo       (default opencode-bot/morseboy1)
#   GITEA_TOKEN   access token with write access to the repo.
#                 If unset, the default login's token from the tea CLI
#                 config (/data/config/tea.yml) is used.
#
# What it does:
#   1. builds the ROM with `make` (so the artifact matches this tree)
#   2. POSTs a release tagged at HEAD to the Gitea API
#      (if a release with that tag already exists, it is reused)
#   3. uploads build/morseboy1.gb as the asset morseboy1-<short>.gb

set -eu

GITEA_URL=${GITEA_URL:-http://10.66.0.1:3000}
GITEA_REPO=${GITEA_REPO:-opencode-bot/morseboy1}
API="$GITEA_URL/api/v1/repos/$GITEA_REPO"
# Token: $GITEA_TOKEN, else the (default) login from the tea CLI config.
if [ -z "${GITEA_TOKEN:-}" ]; then
    GITEA_TOKEN=$(python3 -c "
import yaml
d = yaml.safe_load(open('/data/config/tea.yml'))
l = next((x for x in d.get('logins', []) if x.get('default')), d['logins'][0])
print(l['token'])" 2>/dev/null) || true
fi
if [ -z "$GITEA_TOKEN" ]; then
    echo "error: no Gitea token: set GITEA_TOKEN or fix /data/config/tea.yml" >&2
    exit 1
fi

AUTH="Authorization: token $GITEA_TOKEN"
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }

# --- 1. build the ROM for this tree -----------------------------------------
cd "$(dirname "$0")/.."
make rom >/dev/null
ROM=build/morseboy1.gb
[ -f "$ROM" ] || { echo "error: $ROM not found after make" >&2; exit 1; }

SHA=$(git rev-parse HEAD)
SHORT=$(git rev-parse --short HEAD)
TAG=${1:-g$SHORT}
NAME=${2:-morseboy1 $TAG}
BODY="morseboy1 ROM for ${SHA} (DMG-only, 32 KB).

Built from \`src/main.asm\` with RGBDS; smoke-tested with mGBA headless.
Run \`make check\` before building your own copy."

if [ -n "$(git status --porcelain)" ]; then
    echo "warning: working tree is dirty; ROM reflects uncommitted changes" >&2
fi

# --- 2. create the release (idempotent: reuse if the tag exists) ------------
# NB: this Gitea (28.x) ignores ?tag_name= on the list endpoint, so filter here.
resp=$(mktemp)
trap 'rm -f "$resp"' EXIT

code=$(curl -s -o "$resp" -w '%{http_code}' -H "$AUTH" "$API/releases")
ID=$(jq -r --arg t "$TAG" '[.[] | select(.tag_name == $t)][0].id // empty' "$resp")

if [ -n "$ID" ]; then
    echo "release $TAG already exists (id $ID), reusing"
else
    code=$(curl -s -o "$resp" -w '%{http_code}' -X POST -H "$AUTH" \
        -H "Content-Type: application/json" \
        --data "$(jq -n --arg tag "$TAG" --arg name "$NAME" \
                   --arg sha "$SHA" --arg body "$BODY" \
                   '{tag_name:$tag, name:$name, target_commitish:$sha, body:$body}')" \
        "$API/releases")
    [ "$code" = 201 ] || { echo "error: create release failed (HTTP $code): $(cat "$resp")" >&2; exit 1; }
    ID=$(jq -r .id "$resp")
    echo "created release $TAG (id $ID) at $SHA"
fi

# --- 3. upload the ROM asset ------------------------------------------------
ASSET="morseboy1-$SHORT.gb"
code=$(curl -s -o "$resp" -w '%{http_code}' -X POST -H "$AUTH" \
    -F "attachment=@$ROM;filename=$ASSET;type=application/octet-stream" \
    "$API/releases/$ID/assets")
if [ "$code" = 201 ]; then
    echo "uploaded $ASSET"
else
    echo "error: asset upload failed (HTTP $code): $(cat "$resp")" >&2
    exit 1
fi

echo "done: $GITEA_URL/$GITEA_REPO/releases/tag/$TAG"
