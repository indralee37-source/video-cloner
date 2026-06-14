# Adapter: fal.ai (queue API)

> Active backend for the video-clone skill. All API specifics live here.
> Verified against https://fal.ai/docs/model-endpoints/queue on 2026-06-13.
> Re-validate pricing and per-model fields before trusting them — fal.ai adds/renames
> models frequently.

## Identity

- **Backend:** fal.ai
- **Base URL / SDK:** `https://queue.fal.run` (REST queue API). Optional SDK: `npm i @fal-ai/client` / `pip install fal-client`.
- **Docs:** https://fal.ai/docs/model-endpoints/queue · model catalog: https://fal.ai/models
- **Models:** (pick per job; the `model` value is the path used in the queue URL)

| Model | `model` value | Speaks? | Notes |
|-------|---------------|:------:|-------|
| Seedance 1.0 Pro (i2v) | `fal-ai/bytedance/seedance/v1/pro/image-to-video` | no (silent) | ✅ verified 2026-06-13. UGC sweet spot, i2v. 2–12s, up to 1080p. |
| Seedance 1.0 Pro (t2v) | `fal-ai/bytedance/seedance/v1/pro/text-to-video` | no | ⚠️ confirm id/fields on fal.ai/models before first use. |
| Kling (i2v) | `fal-ai/kling-video/v2/master/image-to-video` | no | ⚠️ confirm id/fields on fal.ai/models before first use. |
| Veo 3 | `fal-ai/veo3` | yes (native audio) | ⚠️ confirm id/fields + pricing on fal.ai/models before first use. |

> Only Seedance i2v fields below are doc-verified. For any other model, open its
> `/api` page on fal.ai/models and confirm the input field names first.

## Auth

- **Scheme:** API key in header — `Authorization: Key <FAL_KEY>`.
- **Secret env var:** `FAL_KEY` (load from `.env`; never commit; never print).
  - ➕ **TODO (user): add your key** — get it from https://fal.ai/dashboard/keys, then put
    `FAL_KEY=fal-...` in a `.env` file in the repo root.
- **Probe (is auth working?):** submit a tiny job and confirm you get a `request_id` (no
  dedicated "list models" REST endpoint). A 401 means the key is missing/wrong.
  ```bash
  curl -sS -X POST "https://queue.fal.run/fal-ai/bytedance/seedance/v1/pro/image-to-video" \
    -H "Authorization: Key $FAL_KEY" -H "Content-Type: application/json" \
    -d '{"prompt":"probe","image_url":"https://fal.media/files/penguin/example.jpg"}'
  ```
- **On 401/403:** key missing/wrong — re-check `FAL_KEY` in `.env`.

## upload(file) → handle

fal.ai accepts three ways to pass a reference image/video; **no separate upload step is
required** for the first two:

1. **Public URL** (simplest) — pass any reachable `https://` URL directly as the handle.
2. **Data URI** — base64-encode a local file and pass `data:<mime>;base64,<...>` as the handle.
   ```bash
   HANDLE="data:image/jpeg;base64,$(base64 -w0 frame.jpg)"   # use base64 -i on macOS
   ```
3. **fal storage** (for large files) — upload via the SDK `fal.storage.upload(file)` →
   returns a `https://fal.media/...` URL. ⚠️ REST upload endpoint not documented here;
   prefer (1) or (2) for curl-only flows.

- **Returns:** a string URL or data URI → goes into the model's `image_url` (i2v) field.
- **Accepted types:** image/jpeg|png|webp, video/mp4 (model-dependent).
- **Handle reuse:** public URLs / data URIs are reusable (stateless).

## submit(prompt, params, refs) → jobId

- **Endpoint:** `POST https://queue.fal.run/{model}` (model = the path from the table above).
- **Request shape (Seedance i2v, doc-verified):**
  ```json
  {
    "prompt": "<text>",
    "image_url": "<handle: public URL or data URI>",
    "aspect_ratio": "9:16",
    "resolution": "720p",
    "duration": 10
  }
  ```
- **Required:** `prompt`, `image_url` (for i2v).
  **Optional:** `aspect_ratio` (`21:9,16:9,4:3,1:1,3:4,9:16,auto`; default `auto`),
  `resolution` (`480p,720p,1080p`; default `1080p`), `duration` (2–12s; default `5`).
- **Input modes & mutual exclusions:** i2v needs `image_url`; t2v models omit it (use the
  `text-to-video` model id instead). Field names differ per model — verify on the model page.
- **Response:** jobId is `request_id`. Also returns `status_url` and `response_url` — capture
  both; they encode the model path and id for you.
  ```bash
  curl -sS -X POST "https://queue.fal.run/$MODEL" \
    -H "Authorization: Key $FAL_KEY" -H "Content-Type: application/json" \
    -d "$PAYLOAD"
  # → { "request_id": "...", "status_url": "...", "response_url": "...", "queue_position": 0 }
  ```

## poll(jobId) → {status, outputUrl}

- **Endpoint:** `GET {status_url}` (or `https://queue.fal.run/{model}/requests/{request_id}/status?logs=1`).
- **Status field:** `status` — terminal values: done=`COMPLETED`, failed=`COMPLETED` with an
  `error`/`error_type` field present (or a non-2xx). In-flight: `IN_QUEUE`, `IN_PROGRESS`.
- **Output URL location:** once `COMPLETED`, `GET {response_url}` → output JSON;
  the video is at `video.url` (Seedance). Field name is model-specific.
- **Cadence:** poll every 3–5s; back off on 429.
- **⚠️ Poll-path differs from submit-path?** No — `status_url`/`response_url` are returned by
  submit; just call them. Always include the `Authorization: Key $FAL_KEY` header.
  ```bash
  curl -sS "$STATUS_URL" -H "Authorization: Key $FAL_KEY"          # → {"status":"COMPLETED",...}
  curl -sS "$RESPONSE_URL" -H "Authorization: Key $FAL_KEY"        # → {"video":{"url":"..."},...}
  ```

## capabilities

| Model | duration | aspectRatio | resolution | input modes | ref caps | audio | price | gen speed |
|-------|----------|-------------|------------|-------------|----------|:-----:|-------|-----------|
| `fal-ai/bytedance/seedance/v1/pro/image-to-video` | 2–12s (default 5) | 21:9,16:9,4:3,1:1,3:4,9:16,auto | 480p,720p,1080p | i2v | 1 image (`image_url`) | no | see pricing | ~1–5 min |
| other models | varies | varies | varies | t2v/i2v | varies | varies | varies | varies |

## pricing (for estimates)

- **TODO (verify):** fal.ai bills per-second or per-megapixel-second depending on the model;
  exact rate is on each model's page (https://fal.ai/models/<id>) and your dashboard.
  Treat all cost numbers as estimates until confirmed in https://fal.ai/dashboard.

## gotchas (date every entry)

- `2026-06-13` — every request to `queue.fal.run` (submit, status, response) needs the
  `Authorization: Key $FAL_KEY` header, including the status/response polls.
- `2026-06-13` — `image_url` accepts a public URL or a `data:...;base64,...` URI directly;
  no separate upload call is needed for curl flows.
- `2026-06-13` — input field names are **per-model**; only Seedance i2v is verified here.
  Check the model's `/api` page before using a different model id.

## error codes

| Code | Meaning | Recovery |
|------|---------|----------|
| 401/403 | auth | re-check `FAL_KEY` in `.env` |
| 422/400 | validation/moderation | check enums (aspect_ratio, resolution, duration), tighten prompt |
| 429 | rate limit | back off and retry |
| 5xx | server | retry once, then stop |
