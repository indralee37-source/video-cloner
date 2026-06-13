---
name: clone-ad
description: >
  Clone an existing video ad for a different product. Analyze the source video's style,
  pacing, camera work, dialogue, and tone, then adapt and GENERATE a new video for the
  user's product through the configured backend (adapters/active.md). Backend-agnostic.
  Use for "clone this ad", "make this ad but for my product", "recreate this video for my brand".
---

# Clone ad — analyze → adapt → generate

Input: a source video ad + the user's product (image and/or description).
Output: a **new generated video** that reuses the source's style for the user's product.

Sibling skill: [analyze-video](../analyze-video/SKILL.md) produces a reusable `.md`
template instead of a finished video. Use that if the user wants the recipe, not one video.

All API calls go through the active backend — read **`adapters/active.md`** first and
resolve `upload`/`submit`/`poll`/`capabilities` against it. If no `active.md` exists, stop
and ask the user to configure a backend (see the hub [SKILL.md](../../SKILL.md)).

## Prerequisites

```bash
command -v ffmpeg  >/dev/null || echo "MISSING — run: brew install ffmpeg"
command -v yt-dlp  >/dev/null || echo "MISSING — run: brew install yt-dlp  (required for URL inputs)"
python3 -c "import whisper" 2>/dev/null || echo "whisper MISSING (optional) — pip3 install openai-whisper"
```

## Step 0 — Gather inputs

| Input | Required | Notes |
|-------|----------|-------|
| Source video | yes | local path (`.mp4`/`.mov`/`.webm`) **or** a URL (YouTube, Instagram, TikTok, …) |
| Product image | recommended | becomes the i2v reference; without it the model invents the product |
| Product/offer description | if no image | used to rewrite dialogue + product references |
| Brand voice | optional | from `MASTER_CONTEXT.md` or ask |

If the user provides a URL, yt-dlp will download it automatically in Step 1 — no manual
download needed. If they only give a video, ask for at least a product image or description first.

## Step 1 — Extract frames + audio

Reuse the shared script (don't duplicate it). It accepts a **local path or a URL** — if a
URL is given, yt-dlp downloads the video to `<output_dir>/_source.mp4` first.

```bash
bash "<skill-path>/prompting/analyze-video/scripts/extract-frames.sh" \
  "<source_video_or_url>" "/tmp/clone-ad-analysis" <num_frames>
```

Frame count: <10s→8, 10–20s→12, 20–30s→16, >30s→20. Read `metadata.txt` for duration.

## Step 2 — Transcribe dialogue

```bash
whisper /tmp/clone-ad-analysis/audio.wav --model base --output_format txt --output_dir /tmp/clone-ad-analysis
```

Record full transcript, per-segment timestamps, total word count. If silent, note it and
skip dialogue adaptation (visual-style clone only).

## Step 3 — Analyze (internal, not saved)

Read **all** frames + the transcript. Capture:
- **Structure & pacing:** beat count, narrative arc, beat lengths.
- **Camera & framing:** POV (selfie/tripod/over-shoulder), framing per beat, movement.
- **Edit style:** cut type, rhythm, recurring motifs.
- **Dialogue:** hook format, speech pattern (filler words, trailing thoughts), line count, CTA style.
- **Tone & energy:** 3–4 emotion words, energy arc, speaker↔viewer relationship.
- **Lighting & technical:** light source, camera quality, intentional flaws.
- **Product depiction:** how shown, claims called out, on-screen text.
- **2–3 defining traits** — the must-transfer essence.

## Step 4 — Present analysis & get the go-ahead

```
📋 Source analysis
Duration: Xs | Beats: N | Dialogue: Y words | Style: <name>

Beat map:
  [00:00–00:03] HOOK — close-up, "opening line"
  [00:03–00:07] SHOW — tilts product to camera, "feature call-out"
  [00:07–00:10] DEMO — (silent) uses product, macro
  [00:10–00:15] VERDICT — back to camera, "closing line + CTA"

Defining traits: 1) … 2) … 3) …
Transfers: beats, pacing, camera, edit, tone, dialogue pattern.
Swaps: product references → your product; claims → your features.

Proceed? (yes / adjust)
```

## Step 5 — Decide generation mode

Resolve against `capabilities` in `adapters/active.md`:

```
Source ≤ backend max clip length?
  YES → single clip
  NO  → split at beat boundaries; each clip ≤ max; chain for continuity (Step 5a)

Product image provided?
  YES → image-to-video (reference image)
  NO  → text-to-video (describe product in prompt), or v2v if source has no faces and
        the backend supports it

Source has a speaker?
  YES → enable audio (if backend supports); dialogue gate required (Step 7)
  NO  → silent; skip dialogue gate
```

Honor the backend's mutual exclusions (e.g. reference-image vs reference-video).

### Step 5a — Chained multi-clip (if source > max clip length)

If the backend supports v2v: clip 1 uses i2v (product still); each later clip uses v2v
with the **most recent** previous clip as reference. Generate **sequentially** (each clip
needs the prior one done). Re-upload each clip output fresh (handles may be one-time-use).
Stitch with ffmpeg using absolute paths. If the backend has no v2v, generate independent
clips with consistent prompt anchors instead.

## Step 6 — Adapt for the user's product

**Dialogue (if any speech):** keep the same conversational pattern, line count, silent-beat
placement, and energy arc; swap product references; match each line's word count (±3) to
preserve pacing.

**Visual:** keep camera/framing/edit/setting/lighting/technical-flaw cues; swap the product
description; keep or adapt the persona.

**Prompt composition:** read the closest [prompt-library](../prompt-library/) style file and
follow the backend's prompting rules in `adapters/active.md` (prompt-length window, forbidden
words, motion specificity, reference-consistency anchors). Use timestamps `[00:00]`, `[00:04]`
for multi-beat sequences. Pick `duration` from word count (~2.5 w/s) clamped to the backend.

## Step 7 — Dialogue confirmation gate (MANDATORY if speech)

```
📝 Dialogue script (confirm before generating)
  1. [HOOK]    "adapted line"
  2. [SHOW]    "adapted feature call-out"
  3. [DEMO]    (silent beat)
  4. [VERDICT] "adapted CTA"
Total spoken words: ~N | Target: Xs | Fits: ✅/❌
Approve? (yes / edit / rewrite)
```

Separate from cost confirmation. Never assume approval from earlier steps. Skip only if silent.

## Step 8 — Cost estimate & confirm

Source: `logs/video-clone.jsonl` → adapter pricing table → ask user. Show per-clip and
total, cite the source, label as estimate, wait for `yes`. For multi-clip, sum all clips.

## Step 9 — Session, upload, generate

1. Create/reuse the session container if the backend has one.
2. `upload(...)` product image (auto-upscale if longest side < 1024px). For v2v, upload
   the source/previous clip.
3. Compose payload per `adapters/active.md`. `submit(...)` (parallel for variations,
   **sequential** for chained clips).
4. **Log immediately** to `logs/video-clone.jsonl` (jobId, model, params, ref counts).
5. `poll(...)` until done/failed; **update** the log entry with status, cost, URL.

## Step 10 — Deliver

Save to `outputs/clone-ad/<descriptive>/`, open the folder, present watch/download URLs.
For multi-clip, present each clip + the stitched result. Show total cost charged.

## Error recovery

| Error | Recovery |
|-------|----------|
| Moderation/validation reject | Don't resubmit identical payload — remove flagged language, tighten motion, check forbidden words. |
| Prompt too long | Trim tone/setting detail; keep beat structure + dialogue. |
| Source > max clip | Split at beats; chain or independent clips; offer stitch. |
| `failed` status | Read the backend error; rewrite if content-related, retry once if server-side. |
| Backend bills before validation | Treat credits as spent; fix the prompt before retrying. |
