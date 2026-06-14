#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Driver / smoke test for the `video-clone` skill.
#
# video-clone is a *markdown skill package*, not a GUI/server. Its two
# runnable surfaces are:
#   1. ANALYSIS  — prompting/analyze-video/scripts/extract-frames.sh
#                  (ffmpeg/ffprobe + optional yt-dlp): video -> frames+audio.
#   2. BACKEND   — the active adapter's submit/poll. The live adapter is
#                  fal.ai (adapters/active.md): a curl POST to the queue API.
#
# This script drives both so a future agent can confirm the skill is wired
# up on a clean machine BEFORE spending credits on a real generation.
#
# Usage (run from anywhere; the script finds the repo root itself):
#   bash .claude/skills/run-video-clone/smoke.sh
#       -> offline smoke. No API key needed. The backend step expects a 401,
#          which proves the endpoint + curl flow are correct and only the key
#          is missing.
#
#   FAL_KEY=fal-... bash .claude/skills/run-video-clone/smoke.sh
#       -> additionally confirms the live key authenticates (expects a
#          request_id from a probe submit).
#
#   FAL_KEY=fal-... RUN_LIVE=1 bash .claude/skills/run-video-clone/smoke.sh
#       -> additionally fires ONE real, BILLED Seedance i2v generation and
#          polls it to completion. Costs credits. Off by default.
#
# Scratch output lands in ./.vc-smoke at the repo root (gitignored).
# ---------------------------------------------------------------------------
set -uo pipefail

# --- locate repo root from this script's path (works when called from anywhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO"

SCRATCH=".vc-smoke"        # keep RELATIVE: native-Windows python/node cannot
                            # see MINGW /tmp paths (see SKILL.md Gotchas).
PASS=0 ; FAIL=0
ok()   { echo "  PASS  $*" ; PASS=$((PASS+1)) ; }
bad()  { echo "  FAIL  $*" ; FAIL=$((FAIL+1)) ; }
note() { echo "  ....  $*" ; }
hdr()  { echo ; echo "== $* =="; }

MODEL="fal-ai/bytedance/seedance/v1/pro/image-to-video"   # from adapters/active.md

# ---------------------------------------------------------------------------
hdr "1. Prerequisites"
for t in ffmpeg ffprobe curl python3; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t present"; else bad "$t MISSING (required)"; fi
done
for t in yt-dlp whisper jq; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t present (optional)"; else note "$t absent (optional)"; fi
done

# ---------------------------------------------------------------------------
hdr "2. Adapter contract (adapters/active.md)"
ADAPTER="adapters/active.md"
if [ -f "$ADAPTER" ]; then
  ok "$ADAPTER exists"
  for section in "## Auth" "## submit" "## poll" "## capabilities"; do
    if grep -qiF "$section" "$ADAPTER"; then ok "section present: $section"
    else bad "section missing: $section"; fi
  done
else
  bad "$ADAPTER missing — copy adapters/_ADAPTER.template.md to adapters/active.md"
fi

# ---------------------------------------------------------------------------
hdr "3. Analysis path (extract-frames.sh)"
EXTRACT="prompting/analyze-video/scripts/extract-frames.sh"
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
if [ ! -f "$EXTRACT" ]; then
  bad "$EXTRACT missing"
else
  # synthesize a 5s clip with a video pattern + an audio tone
  if ffmpeg -v error -y \
      -f lavfi -i testsrc=duration=5:size=320x240:rate=15 \
      -f lavfi -i sine=frequency=440:duration=5 \
      -c:v libx264 -c:a aac -shortest "$SCRATCH/sample.mp4" 2>"$SCRATCH/ffmpeg.err"; then
    ok "synthesized test video"
  else
    bad "could not synthesize test video (see $SCRATCH/ffmpeg.err)"
  fi
  if bash "$EXTRACT" "$SCRATCH/sample.mp4" "$SCRATCH/out" 6 >"$SCRATCH/extract.log" 2>&1; then
    nframes=$(find "$SCRATCH/out" -name 'frame_*.jpg' 2>/dev/null | wc -l | tr -d ' ')
    [ "$nframes" = "6" ] && ok "extracted $nframes frames" || bad "expected 6 frames, got $nframes"
    [ -f "$SCRATCH/out/audio.wav" ]    && ok "audio.wav extracted"    || bad "audio.wav missing"
    [ -f "$SCRATCH/out/metadata.txt" ] && ok "metadata.txt written"   || bad "metadata.txt missing"
    note "look at $SCRATCH/out/frame_003.jpg to eyeball a frame"
  else
    bad "extract-frames.sh failed (see $SCRATCH/extract.log)"
  fi
fi

# ---------------------------------------------------------------------------
hdr "4. Backend wiring (fal.ai submit probe)"
PROBE="$SCRATCH/probe.json"
HTTP=$(curl -sS -o "$PROBE" -w "%{http_code}" -X POST "https://queue.fal.run/$MODEL" \
  -H "Authorization: Key ${FAL_KEY:-MISSING}" -H "Content-Type: application/json" \
  -d '{"prompt":"probe","image_url":"https://fal.media/files/penguin/example.jpg"}' 2>"$SCRATCH/curl.err" || echo "000")
note "POST queue.fal.run/$MODEL -> HTTP $HTTP"
if [ -z "${FAL_KEY:-}" ]; then
  if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
    ok "endpoint reachable, auth required as expected (set FAL_KEY to go further)"
  else
    bad "expected 401/403 without a key, got $HTTP (body: $(head -c 200 "$PROBE" 2>/dev/null))"
  fi
else
  RID=$(python3 -c "import json;print(json.load(open('$PROBE')).get('request_id',''))" 2>/dev/null)
  if [ -n "$RID" ]; then ok "FAL_KEY authenticated, got request_id=$RID"
  else bad "FAL_KEY set but no request_id (HTTP $HTTP, body: $(head -c 200 "$PROBE"))"; fi
fi

# ---------------------------------------------------------------------------
if [ "${RUN_LIVE:-0}" = "1" ] && [ -n "${FAL_KEY:-}" ]; then
  hdr "5. LIVE generation (BILLED)"
  SUB="$SCRATCH/submit.json"
  curl -sS -o "$SUB" -X POST "https://queue.fal.run/$MODEL" \
    -H "Authorization: Key $FAL_KEY" -H "Content-Type: application/json" \
    -d '{"prompt":"a calm product on a table, slow push-in","image_url":"https://fal.media/files/penguin/example.jpg","duration":2,"resolution":"480p","aspect_ratio":"9:16"}' >/dev/null
  STATUS_URL=$(python3 -c "import json;print(json.load(open('$SUB')).get('status_url',''))")
  RESP_URL=$(python3   -c "import json;print(json.load(open('$SUB')).get('response_url',''))")
  if [ -z "$STATUS_URL" ]; then bad "live submit returned no status_url ($(head -c 200 "$SUB"))";
  else
    ok "submitted; polling $STATUS_URL"
    for i in $(seq 1 40); do
      S=$(curl -sS "$STATUS_URL" -H "Authorization: Key $FAL_KEY")
      ST=$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('status',''))" "$S" 2>/dev/null)
      note "poll $i: $ST"
      [ "$ST" = "COMPLETED" ] && break
      sleep 4
    done
    OUT=$(curl -sS "$RESP_URL" -H "Authorization: Key $FAL_KEY")
    URL=$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('video',{}).get('url',''))" "$OUT" 2>/dev/null)
    [ -n "$URL" ] && ok "video ready: $URL" || bad "no video url in response ($(echo "$OUT" | head -c 200))"
  fi
fi

# ---------------------------------------------------------------------------
hdr "Summary"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && { echo "  smoke OK"; exit 0; } || { echo "  smoke had failures"; exit 1; }
