# scripts

Assorted utility scripts.

## Audio

- `concat_audio.sh` - given a directory containing audio files **_of a single format_**, concatenates the audio to a single file using the same input format. intended to combine dj mixes split into files by track; relies on track numbers in the file name for ordering. uses `ffmpeg`
- `download_audio.sh` - downloads audio from a URL (YouTube, etc.) using `yt-dlp`. extracts at highest quality, keeps best available format (no conversion), and prefers audio-only streams. requires `yt-dlp` and `ffmpeg`. usage: `./download_audio.sh <url>`
- `extract_video_audio.sh` - extracts audio from a video file using `ffmpeg`. outputs audio as a WAV file to the same dir as the source file using the same name

## Apple Music

- [`apple-music-downloader/`](./apple-music-downloader/) - downloads lossless ALAC audio from Apple Music URLs (tracks, albums, playlists). requires Docker, MP4Box, and an active Apple Music subscription. see [`apple-music-downloader/README.md`](./apple-music-downloader/README.md) for setup and usage

## macOS

- `kill_mac_notifications.sh` / `kill_notifications.applescript` - kills macOS Notification Center. useful for clearing system notification spam (e.g. "disk not ejected properly")
