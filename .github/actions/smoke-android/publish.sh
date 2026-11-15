#!/usr/bin/env bash
# Publishes smoke-test evidence (Android or iOS): screenshots on the orphan branch `jaglosky-artifacts`
# (artifact zips don't render), then a PR comment — or, without a PR (release-check), the run summary —
# plus a commit status.
# Usage: publish.sh <pr|""> <out-dir> <pass|fail|inconclusive> "<label, e.g. Android 36 (emulator)>" <status context>
set -euo pipefail
PR="$1"
OUT="$2"
RESULT="$3"
LABEL="$4"
CONTEXT="${5:-jaglosky/smoke-android}"
REPO="$GITHUB_REPOSITORY"
BRANCH=jaglosky-artifacts
SLUG="$(echo "$CONTEXT" | sed 's|.*/||')"
if [ -n "$PR" ]; then
  DIR="runs/pr-${PR}-${SLUG}-$(date -u +%Y%m%d-%H%M%S)"
  SHA="$(gh pr view "$PR" --json headRefOid --jq .headRefOid)"
  WHAT="PR #$PR"
else
  REF_SLUG="$(echo "${GITHUB_REF_NAME:-run}" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-*$//')"
  DIR="runs/${REF_SLUG}-${SLUG}-$(date -u +%Y%m%d-%H%M%S)"
  SHA="$GITHUB_SHA"
  WHAT="${GITHUB_REF_NAME:-run}"
fi
# Screenshot caption from its file name (`02-after-back` → "after back").
caption() {
  echo "$1" | sed -E 's/^[0-9]+[a-z]?-//; s/-/ /g'
}

WT="$(mktemp -d)"
if git ls-remote --exit-code --heads origin "$BRANCH" > /dev/null 2>&1; then
  git fetch -q origin "$BRANCH"
  git worktree add -q "$WT" "origin/$BRANCH"
  git -C "$WT" checkout -q -B "$BRANCH"
else
  git worktree add -q --detach "$WT"
  git -C "$WT" checkout -q --orphan "$BRANCH"
  git -C "$WT" rm -rqf . > /dev/null 2>&1 || true
  echo "Jaglosky evidence (emulator/simulator screenshots) — technical branch, do not merge." > "$WT/README.md"
fi
mkdir -p "$WT/$DIR"
cp "$OUT"/*.png "$OUT"/*.gif "$OUT"/*.mp4 "$WT/$DIR/" 2>/dev/null || true
cp "$OUT"/notes.txt "$OUT"/device.txt "$WT/$DIR/" 2>/dev/null || true
git -C "$WT" add -A
git -C "$WT" -c user.name=Jaglosky -c user.email=jaglosky@localhost commit -qm "smoke: $WHAT $SLUG ($RESULT)"
for i in 1 2 3; do git -C "$WT" push -q origin "$BRANCH" && break || { git -C "$WT" pull -q --rebase origin "$BRANCH"; }; done

ICON=$([ "$RESULT" = "pass" ] && echo "✅" || { [ "$RESULT" = "inconclusive" ] && echo "⚠️" || echo "❌"; })
HEAD_ROW="|"; SEP_ROW="|"; IMG_ROW="|"
for f in $(ls "$OUT"/*.png 2>/dev/null | sort); do
  name="$(basename "$f" .png)"
  cap="$(caption "$name")"
  HEAD_ROW="$HEAD_ROW $cap |"; SEP_ROW="$SEP_ROW---|"
  IMG_ROW="$IMG_ROW <img src=\"https://github.com/$REPO/blob/$BRANCH/$DIR/$name.png?raw=true\" width=\"240\" alt=\"$cap\"> |"
done
{
  echo "## $ICON Jaglosky smoke test — $LABEL"
  echo
  echo "$(cat "$OUT/device.txt" 2>/dev/null)"
  echo
  if [ "$HEAD_ROW" != "|" ]; then echo "$HEAD_ROW"; echo "$SEP_ROW"; echo "$IMG_ROW"; echo; fi
  if [ -f "$OUT/launch.gif" ]; then
    echo "<details><summary>▶️ Launch recording (30 s)</summary>"; echo
    echo "<img src=\"https://github.com/$REPO/blob/$BRANCH/$DIR/launch.gif?raw=true\" width=\"270\" alt=\"launch recording\">"; echo
    echo "</details>"; echo
  elif [ -f "$OUT/launch.mp4" ]; then
    echo "▶️ [Launch recording (30 s)](https://github.com/$REPO/blob/$BRANCH/$DIR/launch.mp4?raw=true)"; echo
  fi
  echo "**Observations**"
  sed 's/^/- /' "$OUT/notes.txt" 2>/dev/null || true
  echo
  echo "<sub>Run: $GITHUB_SERVER_URL/$REPO/actions/runs/$GITHUB_RUN_ID · full logs in the run artifacts</sub>"
} > "$OUT/comment.md"
echo "$GITHUB_SERVER_URL/$REPO/tree/$BRANCH/$DIR" > "$OUT/evidence-url.txt"
if [ -n "$PR" ]; then
  gh pr comment "$PR" --body-file "$OUT/comment.md" | tail -1 > "$OUT/comment-url.txt"
else
  # No PR (release-check on a branch/tag): the screenshots go to the run's summary page.
  cat "$OUT/comment.md" >> "$GITHUB_STEP_SUMMARY"
fi

# inconclusive (app config missing in CI) = not verified: neither green nor red.
STATE=$([ "$RESULT" = "pass" ] && echo success || { [ "$RESULT" = "inconclusive" ] && echo pending || echo failure; })
gh api -X POST "repos/$REPO/statuses/$SHA" \
  -f state="$STATE" \
  -f context="$CONTEXT" \
  -f description="$LABEL: $RESULT" \
  -f target_url="$GITHUB_SERVER_URL/$REPO/actions/runs/$GITHUB_RUN_ID" > /dev/null
git worktree remove --force "$WT"
