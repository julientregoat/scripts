# Apple Music Lossless Downloader

**Documentation created:** January 25, 2026

Scripts for downloading lossless ALAC audio from Apple Music using a paid subscription. This setup uses Docker for both the downloader and wrapper (decryption server), as recommended by the wrapper documentation.

## Quick Start

1. **Run setup script:**
   ```bash
   ./setup.sh
   ```
   This will automatically:
   - Install MP4Box
   - Clone/update the wrapper repository
   - Download the latest prebuilt binary for your architecture
   - Build the wrapper Docker image
   - Pull the downloader Docker image

2. **Configure (optional):**
   ```bash
   cp .env.template .env
   # Edit .env if you want to customize settings
   ```
   
   **Note:** The `.env` file is **optional**. The script works with defaults:
   - Wrapper host: 127.0.0.1, port: 10020
   - Output directory: ~/Downloads
   - No credentials needed (wrapper can work without them)
   
   Only create `.env` if you want to customize these settings or add credentials.

3. **Start wrapper (or use --auto-wrapper):**
   ```bash
   ./wrapper.sh start
   # Or use --auto-wrapper flag when downloading
   ```

4. **Download:**
   ```bash
   ./download_apple_music.sh https://music.apple.com/us/album/...
   ```

## Components

This setup uses two components:

1. **wrapper** ([WorldObservationLog/wrapper](https://github.com/WorldObservationLog/wrapper)) - Decryption server running in Docker (recommended method). Requires building a Docker image from a prebuilt binary (no pre-built Docker image available). See [wrapper README](https://github.com/WorldObservationLog/wrapper#readme) for Docker setup and detailed options.

2. **apple-music-downloader** ([zhaarey/apple-music-downloader](https://github.com/zhaarey/apple-music-downloader)) - Go-based downloader running in Docker. See [apple-music-downloader README](https://github.com/zhaarey/apple-music-downloader#readme) for all available options and features.

**What we use from each:**
- **wrapper:** Docker container (recommended method per wrapper docs), basic decryption functionality. Login credentials optional (can work without).
- **apple-music-downloader:** Docker image, default ALAC format (lossless), basic download functionality.

## Scripts

### `detect_wrapper_architecture.sh` - Architecture detection (internal)

Shared script used by `setup.sh` and `wrapper.sh` to detect system architecture and set platform-specific variables. Not typically run directly by users.

### `wrapper.sh` - Manage the decryption server

```bash
./wrapper.sh start    # Start wrapper
./wrapper.sh stop     # Stop wrapper
./wrapper.sh restart  # Restart wrapper
./wrapper.sh status   # Check status
```

The wrapper runs as a **Docker container** (long-lived service) that should run in the background. It listens on:
- Port 10020 (decrypt)
- Port 20020 (m3u8)
- Port 30020 (account)

**Recommended usage:** Start it once, use it for multiple downloads, stop when done with your session.

**Note:** The wrapper uses Docker, not a local binary. The Docker image is built automatically by `./setup.sh`.

### `download_apple_music.sh` - Download tracks/albums/playlists

```bash
./download_apple_music.sh [options] <apple-music-url> [url2] [url3] ...
```

**Options:**
- `--auto-wrapper` - Automatically start wrapper if not running, and stop it if this script started it (after download completes)
- `--output-dir DIR` - Output directory for downloads (default: `~/Downloads`)
- `--max-sample-rate RATE` - Maximum sample rate in Hz (default: auto-detect based on bit depth)
  - Auto-detection: Default max 44.1 kHz for 16-bit, 48 kHz for 24-bit
  - Override values: `44100`, `48000`, `96000`, `192000`
- `--help` - Show detailed help

**Examples:**
- Single album (wrapper must be running): `./download_apple_music.sh https://music.apple.com/us/album/...`
- Single track with auto-wrapper: `./download_apple_music.sh --auto-wrapper https://music.apple.com/us/song/...`
- Custom output directory: `./download_apple_music.sh --output-dir ~/Music https://music.apple.com/us/album/...`
- Limit sample rate: `./download_apple_music.sh --max-sample-rate 44100 https://music.apple.com/us/album/...`
- Multiple URLs (more efficient - single docker run): `./download_apple_music.sh https://music.apple.com/us/album/album1/123 https://music.apple.com/us/album/album2/456`

**Output:** Downloads to `~/Downloads/Apple Music Downloads` by default (use `--output-dir` to customize)
- Files are organized as: `[Artist] - [Release Name]/[tracks]`
- The script automatically reorganizes from the downloader's default structure (`ALAC/[Artist]/[Release Name]`) to the flattened structure

**Performance:** When downloading multiple URLs, the script checks all URLs in a single docker run, then downloads all URLs in another single docker run. This is much more efficient than running the script multiple times.

**Note on long downloads:** The download process blocks until completion. For very large albums/playlists, this may take several minutes. If the script is interrupted (e.g., by tool timeouts), files will be in `OUTPUT_DIR/ALAC/`. The script will automatically reorganize any existing ALAC files on the next run, or you can re-run the script to complete the reorganization.

**Wrapper management:**
- By default, the script requires the wrapper to be running (error if not running)
- Start manually: `./wrapper.sh start` (recommended for multiple downloads)
- Use `--auto-wrapper` for convenience: starts wrapper if needed, stops it if the script started it
- For multiple downloads, start wrapper once and leave it running (don't use `--auto-wrapper`)

### `setup.sh` - Initial setup and dependency installation

Automatically installs and updates dependencies:
- Checks for Docker (must be installed manually)
- Installs MP4Box (via Homebrew on macOS, apt/yum/pacman on Linux)
- Clones/updates wrapper repository
- Downloads latest prebuilt binary from releases (detects architecture automatically)
  - Handles zip file downloads and extraction automatically
  - On Apple Silicon (arm64), uses native arm64 binary (from `Wrapper.arm64.latest` release)
  - On x86_64, uses x86_64 binary (from `Wrapper.x86_64.*` releases)
- Builds/rebuilds wrapper Docker image with platform-specific naming (e.g., `apple-music-wrapper-arm64`, `apple-music-wrapper-x86_64`)
  - Automatically cleans up old wrapper images before building
  - Rebuilds if binary is newer
- Attempts to pull the downloader Docker image

**Note:** The wrapper Docker image is built automatically from the latest prebuilt binary. The setup script ensures you have the latest code and binary before building.

**Note:** The wrapper runs in a Docker container (not a local binary), as recommended by the wrapper documentation.

**Note:** On Apple Silicon (arm64), the wrapper uses native arm64 binaries and Docker images (no emulation needed). The downloader still uses `--platform linux/amd64` to run x86_64 images via Rosetta 2, as the downloader image doesn't have native arm64 builds yet.

Run this once to set up everything needed.

### `check_format.sh` - Check available formats

```bash
./check_format.sh <apple-music-url> [url2] [url3] ...
```

Shows what audio formats are available for URLs without downloading. Validates that ALAC formats meet minimum quality requirements:
- **Minimum bit depth:** 16-bit
- **Minimum sample rate:** 44.1 kHz (44100 Hz) for all formats

The script displays:
- Bit depth and sample rate for each format found
- Maximum sample rate available
- Validation errors if any formats don't meet minimum requirements

This script is also used internally by `download_apple_music.sh` for format validation.

## Configuration

### Environment Variables (`.env` file)

**The `.env` file is optional!** The script works with sensible defaults:
- Wrapper host: `127.0.0.1`, port: `10020`
- Output directory: `~/Downloads`
- No credentials needed (wrapper can decrypt without them)

Only create `.env` if you want to customize these settings.

To create and configure:

```bash
cp .env.template .env
# Edit .env if you want to customize settings
```

**Optional settings:**
- `APPLE_MUSIC_USERNAME` / `APPLE_MUSIC_PASSWORD` - Login credentials for wrapper. **Not required** - wrapper can decrypt without them. Only needed for certain authentication scenarios. Basic ALAC downloads work without credentials.
- `APPLE_MUSIC_WRAPPER_HOST` - Wrapper host (default: 127.0.0.1)
- `APPLE_MUSIC_WRAPPER_PORT` - Wrapper port (default: 10020)
- `APPLE_MUSIC_AUTO_WRAPPER` - Auto-wrapper behavior (equivalent to `--auto-wrapper` flag, default: false)
- `APPLE_MUSIC_MEDIA_USER_TOKEN` - **Not required for basic ALAC downloads**, but required for:
  - Lyrics (LRC, word-by-word, translations)
  - aac-lc format (lossy, lower quality - avoid if you want lossless)
  - MV downloads (music videos - not needed for audio-only)
  
  Extract from browser cookies: `Application -> Storage -> Cookies -> https://music.apple.com`, find cookie named `media-user-token`. See [Format Explanations](#format-explanations) section for details.

The `.env` file is gitignored for security.

## Quality

**ALAC (lossless) is the default and highest quality format.** The downloader automatically selects ALAC if available, falling back to other formats only if ALAC is not available for a specific track.

**Sample Rate Auto-Detection and Validation:**
- The script automatically detects bit depth and sample rate from available formats
- **Minimum requirements (applies to all formats):**
  - Minimum bit depth: 16-bit
  - Minimum sample rate: 44.1 kHz (44100 Hz)
- **Default maximum sample rates:**
  - **16-bit audio:** Maximum set to 44.1 kHz (CD quality)
  - **24-bit audio:** Maximum set to 48 kHz (high-res)
- Override maximum with `--max-sample-rate` flag if needed (supports 44100, 48000, 96000, 192000 Hz)
- The script validates that all formats meet minimum quality requirements before downloading

**Note:** Bit depth is determined by what Apple Music provides - it's not configurable. The script sets default maximum sample rates based on detected bit depth to ensure compatibility and reasonable file sizes, while enforcing minimum quality standards (16-bit minimum, 44.1 kHz minimum).

### Checking Available Formats

To see what formats are available for a track before downloading, use the `--debug` flag:

```bash
docker run --rm --network host \
    -v ~/Downloads:/downloads \
    ghcr.io/zhaarey/apple-music-downloader \
    --debug <apple-music-url>
```

This will show you all available formats (ALAC, Dolby Atmos, AAC, etc.) without downloading. If ALAC is not listed, the track doesn't have a lossless version available.

### Format Explanations

**ALAC (Apple Lossless Audio Codec)** - ⭐ **This is what you want**
- Lossless audio format (no quality loss)
- Highest quality available
- Default format used by this script
- No credentials needed

**aac-lc (AAC Low Complexity)** - ❌ **Avoid this**
- Lossy audio format (quality loss from compression)
- Lower quality than ALAC
- Requires `media-user-token` to download
- Only use if ALAC is not available (rare)

**MV (Music Video)** - ❌ **Not for audio-only downloads**
- Downloads the music video file (video + audio)
- Much larger file sizes
- Requires `media-user-token` and `mp4decrypt` to download
- Not needed if you only want lossless audio

**Dolby Atmos (EC3)** - ❌ **Lossy format**
- Lossy audio format (uses EC3/Dolby Digital Plus codec, which is compressed)
- Lower quality than ALAC despite being "high quality"
- Spatial audio format (surround sound/3D audio)
- On Apple Music, Dolby Atmos is delivered as lossy EC3, not lossless TrueHD
- Only used as fallback if ALAC unavailable
- Not recommended for lossless audio collection

**Other formats (AAC, etc.)**
- Lossy formats, lower quality than ALAC
- Only used as fallback if ALAC unavailable
- Not recommended for lossless audio collection

## Prerequisites

1. **Docker** - Must be installed and running (install manually from [Docker Desktop](https://www.docker.com/products/docker-desktop))
2. **Active Apple Music subscription** - Required for decryption

**Note:** All dependencies except Docker are automatically installed/updated by `./setup.sh`. You only need to install Docker manually.

**Platform Compatibility:**
- **Apple Silicon (arm64):** Fully tested and working. Uses native arm64 wrapper binaries and Docker images (no emulation). The downloader uses `--platform linux/amd64` to run x86_64 images via Rosetta 2.
- **x86_64 (Intel Mac/Linux):** Should work but needs testing. Uses native x86_64 wrapper binaries and Docker images. The downloader uses `--platform linux/amd64` flag.

## Troubleshooting

### Wrapper not starting
- Ensure Docker image is built: `docker images | grep apple-music-wrapper` (should show platform-specific image like `apple-music-wrapper-arm64` or `apple-music-wrapper-x86_64`)
- Check logs: `docker logs apple-music-wrapper`
- Verify Docker is running: `docker ps`
- Rebuild image if needed: `./setup.sh`

### Downloads failing
- Ensure wrapper is running: `./wrapper.sh status`
- Check wrapper is accessible: `nc -z 127.0.0.1 10020`
- Verify Apple Music subscription is active
- Check Docker is running: `docker ps`

### MP4Box not found
```bash
which MP4Box || which mp4box
brew reinstall gpac  # macOS
```

### Apple Silicon (arm64) / Architecture Issues
- **Wrapper binary:** Uses native arm64 binaries from the `Wrapper.arm64.latest` release. No emulation needed - runs natively on Apple Silicon.
- **Wrapper Docker image:** Built with `--platform linux/arm64` and named `apple-music-wrapper-arm64` for clarity.
- **Downloader image:** The downloader image doesn't have native arm64 builds yet. The scripts automatically use `--platform linux/amd64` to run x86_64 images via Rosetta 2. This works transparently.
- **Performance:** The wrapper runs natively on Apple Silicon (no performance penalty). The downloader runs via Rosetta 2, which may be slightly slower than native but works correctly.
- **Note:** The arm64 wrapper binary may be slightly older than the x86_64 version (check release dates), but core functionality is the same.

## Checking if Lossless is Available

Before downloading, you can check what formats are available for a track:

**Easy way (using helper script):**
```bash
./check_format.sh <apple-music-url> [url2] [url3] ...
```

**Or directly with Docker:**
```bash
# On Apple Silicon (arm64), add --platform linux/amd64
docker run --rm --platform linux/amd64 --network host \
    ghcr.io/zhaarey/apple-music-downloader \
    --debug <apple-music-url>
```

This shows all available formats without downloading. Look for `alac` or `audio-alac-stereo` in the output. If it's not listed, the track doesn't have a lossless version available.

**Note:** Most tracks on Apple Music have ALAC available. The download script will check for ALAC availability before downloading and error if it's not available (to prevent downloading lossy formats). If you need to download non-ALAC formats, use the downloader directly with Docker.

## Advanced Usage

For advanced features (Dolby Atmos, AAC, interactive selection, search, lyrics), see the [apple-music-downloader README](https://github.com/zhaarey/apple-music-downloader#readme) for Docker command examples. The basic script downloads ALAC by default.

## References

### Primary Resources
- **apple-music-downloader:** [https://github.com/zhaarey/apple-music-downloader](https://github.com/zhaarey/apple-music-downloader) - Full documentation, all options, advanced features
- **wrapper:** [https://github.com/WorldObservationLog/wrapper](https://github.com/WorldObservationLog/wrapper) - Docker setup (recommended), source build instructions, detailed options

### Historical Reference
The [rentry.org guide](https://rentry.org/firehawk52/#apple-music_1) contains historical information about various Apple Music download methods (some deprecated) and references to other music downloading utilities (Deezer, Qobuz, Tidal, Spotify, etc.). Useful for understanding tool evolution and finding alternatives.

## Legal Notice

This tool is intended for use with a **legitimate, paid Apple Music subscription**. It allows you to download music you have access to through your subscription for personal use. Ensure you comply with Apple Music's terms of service and local copyright laws.

## Version Information

- **Documentation created:** January 25, 2026
- **apple-music-downloader:** Latest from main branch (check [releases](https://github.com/zhaarey/apple-music-downloader/releases))
- **wrapper:** Latest from main branch (check [releases](https://github.com/WorldObservationLog/wrapper/releases))

When referring to this documentation, note the creation date to understand which versions of the upstream READMEs were referenced.
