if [ -z "$1" ]; then
  echo "Error: No YouTube URL provided. Usage: $0 <youtube_url>" >&2
  exit 1
fi

~/Applications/yt-dlp_macos -x --audio-quality 10 --audio-format wav "$1"