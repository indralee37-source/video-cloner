---
name: run-video-clone
description: >
  Build, smoke-test, and drive the video-clone skill on this machine. Use when
  asked to run, start, set up, smoke-test, or verify video-clone — or to extract
  frames from a reference video, check the fal.ai backend wiring, or fire a real
  test generation. Confirms ffmpeg/yt-dlp tooling, the adapter contract, the
  frame-extraction path, and the backend submit/poll before any credits are spent.
---

# run-video-clone

`video-clone` is **not a GUI or a server** — it is a markdown *skill package* an
agent reads to clone/generate video ads. There are only two things that actually
execute:

1. **Analysis path** — `prompting/analyze-video/scripts/extract-frames.sh`
   (ffmpeg/ffprobe + optional yt-dlp): a reference video → evenly-spaced frames,
   `audio.wav`, and `metadata.txt`.
2. **Backend path** — the active adapter's `submit`/`poll`. The live adapter is
   **fal.ai** ([adapters/active.md](adapters/active.md)): a `curl` POST to
   `https://queue.fal.run/{model}`, then poll `status_url`/`response_url`.

The driver below exercises both so you can confirm the skill is wired up **before**
spending credits. It is committed at
`.claude/skills/run-video-clone/smoke.sh`.

> All paths in this file are relative to the repo root
> (`C:\Users\User\OneDrive\Desktop\CLODE-PROJECT\video clone`). Run everything in
> **Git Bash** (the `Bash` tool), not PowerShell — the driver and
> `extract-frames.sh` are bash.

## Prerequisites

Already present in this environment (Git Bash / MINGW64 on Windows):
`ffmpeg`, `ffprobe`, `yt-dlp`, `curl`, `python3`, `node`, `base64`. `whisper`
(optional dialogue transcription) and `jq` are **not** installed — the driver uses
`python3` for JSON instead of `jq`, so jq is not needed.

If `ffmpeg`/`yt-dlp` were missing they were installed via WinGet:
```bash
winget install yt-dlp.FFmpeg
winget install yt-dlp.yt-dlp
```

No build step — this project is markdown + scripts; nothing compiles.

## Run (agent path) — FIRST

Run the driver from the repo root (it also works from any cwd — it locates the
repo from its own path):

```bash
bash .claude/skills/run-video-clone/smoke.sh
```

What it does and the expected tail of a healthy run:

```
== 1. Prerequisites ==        # ffmpeg/ffprobe/curl/python3 required; yt-dlp/whisper/jq optional
== 2. Adapter contract ==     # adapters/active.md exists + has Auth/submit/poll/capabilities
== 3. Analysis path ==        # synthesizes a 5s clip, runs extract-frames.sh, checks 6 frames + audio + metadata
== 4. Backend wiring ==       # POST to fal.ai; no key -> expects HTTP 401 (= correct wiring, key absent)

== Summary ==
  15 passed, 0 failed
  smoke OK
```

Scratch output lands in `./.vc-smoke/` (gitignored). To eyeball a frame after a
run, open `./.vc-smoke/out/frame_003.jpg`.

### Check the live key (no generation, no charge)

```bash
FAL_KEY=fal-... bash .claude/skills/run-video-clone/smoke.sh
```
The backend step then expects a `request_id` instead of a 401. Get a key from
https://fal.ai/dashboard/keys.

### Fire ONE real, BILLED generation (off by default)

```bash
FAL_KEY=fal-... RUN_LIVE=1 bash .claude/skills/run-video-clone/smoke.sh
```
Submits a 2s / 480p Seedance i2v job, polls `status_url` to `COMPLETED`, and prints
the output video URL. **This spends credits.** Leave `RUN_LIVE` unset for routine
checks.

## Drive the analysis path directly

To actually analyze a reference video (local file or any yt-dlp URL — YouTube,
TikTok, Instagram, …):

```bash
bash prompting/analyze-video/scripts/extract-frames.sh <video-or-url> .vc-smoke/out 12
ls .vc-smoke/out          # frame_001.jpg … frame_012.jpg, audio.wav, metadata.txt
```
Then read the frames + `metadata.txt` to deconstruct the style, per
[prompting/analyze-video/SKILL.md](prompting/analyze-video/SKILL.md).

## Drive the backend directly

The full submit/poll contract (request shape, status fields, error codes) is in
[adapters/active.md](adapters/active.md). Minimal probe (what the driver runs):

```bash
curl -sS -X POST "https://queue.fal.run/fal-ai/bytedance/seedance/v1/pro/image-to-video" \
  -H "Authorization: Key ${FAL_KEY:-MISSING}" -H "Content-Type: application/json" \
  -d '{"prompt":"probe","image_url":"https://fal.media/files/penguin/example.jpg"}'
# no/invalid key -> {"detail":"... Authentication is required ..."} with HTTP 401
```

## Human path

There is no app to launch. A human "runs" video-clone by pointing an agent at
[SKILL.md](SKILL.md) and asking it to clone/analyze/generate a video ad; the agent
reads the router, resolves [adapters/active.md](adapters/active.md), and drives the
two paths above. The smoke driver is the only way to *mechanically* verify the
plumbing.

## Gotchas

- **MINGW `/tmp` is invisible to native-Windows executables.** `curl`/`cat`/`bash`
  are MINGW and see `/tmp`, but `python3` and `node` here are the Windows-Store
  builds and cannot open MINGW paths like `/tmp/foo.json` — they fail with
  `FileNotFoundError`. The driver therefore writes all scratch to a **repo-relative**
  `./.vc-smoke/`. Keep this rule for any file handed between MINGW and Windows tools.
- **A 401 from the backend probe is a PASS, not a failure** — it means the endpoint
  is reachable and the curl flow is correct; only `FAL_KEY` is missing. The driver
  treats 401/403 as success when no key is set.
- **No `jq`.** Use `python3 -c "import json; ..."` for JSON (as the driver does).
  Don't add a jq dependency.
- **`whisper` is not installed.** Dialogue transcription (used by analyze-video) is
  optional; the frame/audio extraction works without it. `audio.wav` is still
  produced for later transcription if whisper is added (`pip install openai-whisper`).
- **fal.ai bills per generation and model ids/fields drift.** Only Seedance i2v is
  doc-verified in [adapters/active.md](adapters/active.md); confirm any other model's
  input fields on its fal.ai `/api` page before `RUN_LIVE`.
- **Run in Git Bash, not PowerShell.** The scripts use bash syntax (`set -uo
  pipefail`, `[[ ]]`, here-strings).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ffmpeg/ffprobe not found on PATH` (from extract-frames.sh) | `winget install yt-dlp.FFmpeg`, reopen the shell so PATH refreshes. |
| Backend step shows HTTP `000` | No network / TLS blocked. The probe needs outbound HTTPS to `queue.fal.run`. |
| `FileNotFoundError` when a python/node step reads a file | You passed a MINGW path (e.g. `/tmp/...`) to a Windows tool. Use a repo-relative path. |
| Backend step fails with a non-401 code and no key | Read `.vc-smoke/probe.json` and `.vc-smoke/curl.err`; the endpoint or model path in `adapters/active.md` may have changed. |
| `RUN_LIVE` poll never reaches `COMPLETED` | fal.ai queue is slow/backed up; increase the poll count in `smoke.sh` step 5, or check https://fal.ai/dashboard. |
