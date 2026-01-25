#!/usr/bin/env bash
# Download audio from URLs at highest quality via yt-dlp.
# Docs & format selection: https://github.com/yt-dlp/yt-dlp

set -e

if [ -z "$(command -v yt-dlp)" ]; then
    echo "error: yt-dlp must be installed."
    exit 1
fi

if [ -z "$(command -v ffmpeg)" ]; then
    echo "error: ffmpeg must be installed (required by yt-dlp for audio extraction)."
    exit 1
fi

URL=$1
if [ -z "$URL" ]; then
    echo "usage: $0 <url>"
    echo ""
    echo "Download audio from a URL at the highest quality using yt-dlp."
    echo "Uses best available audio format (no conversion) and prefers"
    echo "audio-only streams when available."
    exit 1
fi

# -P: save to ~/Downloads (home path).
# -x: extract audio only (needs ffmpeg/ffprobe).
# --audio-format best: keep original format, no re-encode (best quality).
# --audio-quality 0: 0=best, 10=worst (VBR when converting; e.g. mp3/aac).
# -f format selector (see FORMAT SELECTION in yt-dlp --help):
#   - Slash "/" = fallback order: left preferred, then right if unavailable.
#     e.g. "bestaudio/best" = use best audio-only, else best combined.
#   - "bestaudio" / "ba": best audio-only. "best" / "b": best video+audio.
#   - Comma "," = download multiple formats. "best.2" = 2nd best.
#   - Filters: "best[height=720]", "bv*[ext=mp4]+ba[ext=m4a]".
#   - Merge: "bestvideo+bestaudio" (needs ffmpeg). Presets: -t mp3, -t aac.
yt-dlp -P ~/Downloads \
    -x \
    --audio-format best \
    --audio-quality 0 \
    -f 'bestaudio/best' \
    "$URL"
