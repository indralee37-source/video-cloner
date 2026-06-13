#!/bin/bash
# Extract evenly-spaced frames + audio from a video for analysis.
# Usage: extract-frames.sh <video_path_or_url> <output_dir> [num_frames]
#
# Accepts a local file path OR any URL supported by yt-dlp
# (YouTube, Instagram, TikTok, Twitter/X, Facebook, Vimeo, …).
#
# Outputs:
#   <output_dir>/frame_001.jpg ... frame_NNN.jpg
#   <output_dir>/audio.wav        (16 kHz mono, for transcription)
#   <output_dir>/metadata.txt     (duration, resolution, fps)
#
# Portable: resolves ffmpeg/ffprobe/yt-dlp from PATH
# (override with FFMPEG / FFPROBE / YTDLP env vars).

set -euo pipefail

FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
FFPROBE="${FFPROBE:-$(command -v ffprobe || true)}"
YTDLP="${YTDLP:-$(command -v yt-dlp || true)}"

if [ -z "$FFMPEG" ] || [ -z "$FFPROBE" ]; then
  echo "Error: ffmpeg/ffprobe not found on PATH. Install with: brew install ffmpeg" >&2
  exit 1
fi

VIDEO="${1:?usage: extract-frames.sh <video_path_or_url> <output_dir> [num_frames]}"
OUT_DIR="${2:?usage: extract-frames.sh <video_path_or_url> <output_dir> [num_frames]}"
NUM_FRAMES="${3:-12}"

# --- URL download via yt-dlp ---
if [[ "$VIDEO" =~ ^https?:// ]]; then
  if [ -z "$YTDLP" ]; then
    echo "Error: yt-dlp not found on PATH. Install with: brew install yt-dlp" >&2
    exit 1
  fi
  mkdir -p "$OUT_DIR"
  TMP_VIDEO="$OUT_DIR/_source.mp4"
  echo "Downloading video from URL..."
  "$YTDLP" \
    -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
    --merge-output-format mp4 \
    --no-playlist \
    -o "$TMP_VIDEO" \
    "$VIDEO"
  VIDEO="$TMP_VIDEO"
fi

if [ ! -f "$VIDEO" ]; then
  echo "Error: video not found: $VIDEO" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

DURATION=$("$FFPROBE" -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null)
RESOLUTION=$("$FFPROBE" -v error -select_streams v:0 \
  -show_entries stream=width,height -of csv=s=x:p=0 "$VIDEO" 2>/dev/null)
FPS=$("$FFPROBE" -v error -select_streams v:0 \
  -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null)

{
  echo "duration_seconds=$DURATION"
  echo "resolution=$RESOLUTION"
  echo "fps=$FPS"
  echo "num_frames_extracted=$NUM_FRAMES"
} > "$OUT_DIR/metadata.txt"

echo "Video: $(basename "$VIDEO")"
echo "Duration: ${DURATION}s | Resolution: $RESOLUTION | FPS: $FPS"

# Evenly-spaced frames: fps filter = num_frames / duration
FPS_FILTER=$(awk "BEGIN { printf \"%.6f\", $NUM_FRAMES / $DURATION }")
echo "Extracting $NUM_FRAMES frames..."
"$FFMPEG" -v warning -i "$VIDEO" -vf "fps=$FPS_FILTER" -q:v 2 "$OUT_DIR/frame_%03d.jpg" 2>&1

FRAME_COUNT=$(find "$OUT_DIR" -name 'frame_*.jpg' | wc -l | tr -d ' ')
echo "Extracted $FRAME_COUNT frames"

echo "Extracting audio..."
"$FFMPEG" -v warning -i "$VIDEO" -vn -acodec pcm_s16le -ar 16000 -ac 1 \
  "$OUT_DIR/audio.wav" 2>&1 || echo "No audio stream found (silent video)"

echo "Done. Output in: $OUT_DIR"
