# Apple Music Lossless Downloader

Scripts for downloading lossless ALAC audio from Apple Music using a paid subscription.

## Quick Start

1. **Run setup:** `./setup.sh`
2. **Configure credentials:** `cp .env.template .env` and edit `.env`
3. **Start wrapper:** `./wrapper.sh start` (first run requires 2FA - see [First-time 2FA](#first-time-2fa))
4. **Download:** `./download_apple_music.sh https://music.apple.com/us/album/...`

## Components

- **[wrapper](https://github.com/WorldObservationLog/wrapper)** - Decryption server (Docker). Requires credentials.
- **[apple-music-downloader](https://github.com/zhaarey/apple-music-downloader)** - Go-based downloader (Docker).

## Scripts

### `wrapper.sh` - Manage decryption server

```bash
./wrapper.sh start    # Start (uses cached session if available)
./wrapper.sh stop     # Stop
./wrapper.sh restart  # Restart
./wrapper.sh login    # Force re-authentication
./wrapper.sh status   # Check status
```

Ports: 10020 (decrypt), 20020 (m3u8), 30020 (account)

### `download_apple_music.sh` - Download music

```bash
./download_apple_music.sh [options] <url> [url2] ...
```

| Option | Description |
|--------|-------------|
| `--output-dir DIR` | Output directory (default: `~/Downloads`) |
| `--max-sample-rate RATE` | Max sample rate: 44100, 48000, 96000, 192000 (default: auto) |
| `--help` | Show help |

Output goes to `OUTPUT_DIR/Apple Music Downloads/[Artist] - [Release]/`

### `check_format.sh` - Check available formats

```bash
./check_format.sh <url> [url2] ...
```

Shows available formats without downloading. Validates ALAC meets minimum quality (16-bit, 44.1 kHz).

### `setup.sh` - Initial setup

Installs MP4Box, clones wrapper repo, downloads prebuilt binary, builds Docker images.

### `utils.sh` - Shared utilities (internal)

Architecture detection and helper functions. Sourced by other scripts.

## Configuration

Create `.env` from template:

```bash
cp .env.template .env
```

| Variable | Required | Description |
|----------|----------|-------------|
| `APPLE_MUSIC_USERNAME` | Yes | Apple ID email |
| `APPLE_MUSIC_PASSWORD` | Yes | Apple ID password |
| `APPLE_MUSIC_WRAPPER_HOST` | No | Wrapper host (default: 127.0.0.1) |
| `APPLE_MUSIC_WRAPPER_PORT` | No | Wrapper port (default: 10020) |
| `APPLE_MUSIC_MEDIA_USER_TOKEN` | No | See below |

**About `APPLE_MUSIC_MEDIA_USER_TOKEN`:** Not needed for basic ALAC downloads. Only required for:
- Lyrics (LRC, word-by-word, translations)
- aac-lc format (lossy - not recommended)
- Music video downloads

To extract: Browser → Developer Tools → Application → Cookies → `https://music.apple.com` → `media-user-token`

## Quality

Downloads ALAC (lossless) only. The script errors if ALAC is unavailable.

| Setting | Value |
|---------|-------|
| Format | ALAC (Apple Lossless) |
| Minimum bit depth | 16-bit |
| Minimum sample rate | 44.1 kHz |
| Default max (16-bit) | 44.1 kHz |
| Default max (24-bit) | 48 kHz |

Override max sample rate with `--max-sample-rate`.

### Why ALAC Only

| Format | Type | Notes |
|--------|------|-------|
| **ALAC** | Lossless | Highest quality, no compression artifacts. This is what we download. |
| Dolby Atmos (EC3) | Lossy | Spatial audio delivered as lossy EC3, not lossless TrueHD. |
| AAC / aac-lc | Lossy | Compressed, lower quality. Requires `media-user-token`. |
| Music Videos | Video | Large files, requires `media-user-token` + `mp4decrypt`. |

Most Apple Music tracks have ALAC available. Use `./check_format.sh` to verify before downloading (download script does this already.).

## Prerequisites

- **Docker** - Install from [docker.com](https://www.docker.com/products/docker-desktop)
- **Apple Music subscription** - Required for decryption

All other dependencies installed by `./setup.sh`.

## Troubleshooting

### First-time 2FA

1. Start wrapper: `./wrapper.sh start`
2. When prompted, enter your 2FA code (60 second timeout)
3. Session is cached in `data/` for future use

### Wrapper not starting

```bash
docker images | grep apple-music-wrapper  # Check image exists
docker logs apple-music-wrapper           # View logs
./setup.sh                                # Rebuild if needed
```

### Downloads failing

```bash
./wrapper.sh status              # Check wrapper running
nc -z 127.0.0.1 10020           # Test port accessibility
```

### Apple Silicon (arm64)

The arm64 wrapper binary can crash during decryption, especially with albums or multiple tracks. Single-track downloads usually work.

**Workarounds:**
- Retry - wrapper auto-restarts and retries often succeed
- Download individual songs instead of full albums
- Use x86_64 Linux for reliable batch downloads

See [wrapper issue #8](https://github.com/WorldObservationLog/wrapper/issues/8).

### Device limit reached

If you see "You've reached your device limit":
1. Stop wrapper: `./wrapper.sh stop`
2. Sign out of Apple Music on unused devices
3. Remove old devices at [appleid.apple.com](https://appleid.apple.com)
4. Restart with cached session: `./wrapper.sh start` (not `login`)

### MP4Box not found

```bash
brew reinstall gpac  # macOS
sudo apt install gpac  # Linux
```

## References

### Primary
- [apple-music-downloader](https://github.com/zhaarey/apple-music-downloader) - Full docs, all options
- [wrapper](https://github.com/WorldObservationLog/wrapper) - Docker setup, detailed options

### Alternative Tools

**[AppleMusicDecrypt](https://github.com/WorldObservationLog/AppleMusicDecrypt)** - Python-based all-in-one downloader. Consider if:
- You want a simpler single-app setup (no separate wrapper)
- You need remote decryption via `wrapper-manager` (bypasses local wrapper issues)
- You're on Apple Silicon and local wrapper keeps crashing
- Runs natively on Python (no Docker/Rosetta needed for the client)

**[wrapper-manager](https://github.com/WorldObservationLog/wrapper-manager)** - Multi-instance wrapper orchestration. Consider if:
- You need to manage multiple Apple accounts
- You want parallel decryption for faster downloads
- You're setting up a shared decryption service

### Other Streaming Services

The [rentry.org guide](https://rentry.org/firehawk52/#apple-music_1) covers downloading from other platforms (Deezer, Qobuz, Tidal, Spotify, etc.) and has historical context on Apple Music tools.

## Legal

For use with a legitimate, paid Apple Music subscription only. Comply with Apple's terms of service and local copyright laws.
