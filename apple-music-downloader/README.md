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

2. **Configure credentials:**
   ```bash
   cp .env.template .env
   # Edit .env and set your Apple Music credentials
   ```
   
   **Note:** Credentials are **required**. The wrapper requires login credentials to function.
   
   First-time setup requires 2FA - see [First-time setup with 2FA](#first-time-setup-with-2fa) for details.

3. **Start wrapper:**
   ```bash
   ./wrapper.sh start
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
- **wrapper:** Docker container (recommended method per wrapper docs), basic decryption functionality. Login credentials required.
- **apple-music-downloader:** Docker image, default ALAC format (lossless), basic download functionality.

## Scripts

### `utils.sh` - Shared utilities (internal)

Shared script used by `setup.sh`, `wrapper.sh`, and other scripts. Provides:
- Generic system architecture detection (`SYSTEM_ARCH`)

Not typically run directly by users.

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
- `--output-dir DIR` - Output directory for downloads (default: `~/Downloads`)
- `--max-sample-rate RATE` - Maximum sample rate in Hz (default: auto-detect based on bit depth)
  - Auto-detection: Default max 44.1 kHz for 16-bit, 48 kHz for 24-bit
  - Override values: `44100`, `48000`, `96000`, `192000`
- `--help` - Show detailed help

**Examples:**
- Single album (wrapper must be running): `./download_apple_music.sh https://music.apple.com/us/album/...`
- Custom output directory: `./download_apple_music.sh --output-dir ~/Music https://music.apple.com/us/album/...`
- Limit sample rate: `./download_apple_music.sh --max-sample-rate 44100 https://music.apple.com/us/album/...`
- Multiple URLs (more efficient - single docker run): `./download_apple_music.sh https://music.apple.com/us/album/album1/123 https://music.apple.com/us/album/album2/456`

**Output:** Downloads to `~/Downloads/Apple Music Downloads` by default (use `--output-dir` to customize)
- Files are organized as: `[Artist] - [Release Name]/[tracks]`
- The script automatically reorganizes from the downloader's default structure (`ALAC/[Artist]/[Release Name]`) to the flattened structure

**Performance:** When downloading multiple URLs, the script checks all URLs in a single docker run, then downloads all URLs in another single docker run. This is much more efficient than running the script multiple times.

**Note on long downloads:** The download process blocks until completion. For very large albums/playlists, this may take several minutes. If the script is interrupted (e.g., by tool timeouts), files will be in `OUTPUT_DIR/ALAC/`. The script will automatically reorganize any existing ALAC files on the next run, or you can re-run the script to complete the reorganization.

**Wrapper management:**
- The script requires the wrapper to be running (error if not running)
- Start manually: `./wrapper.sh start`
- For multiple downloads, start wrapper once and leave it running

### `setup.sh` - Initial setup and dependency installation

Automatically installs and updates dependencies:
- Checks for Docker (must be installed manually)
- Installs MP4Box (via Homebrew on macOS, apt/yum/pacman on Linux)
- Clones/updates wrapper repository
- Downloads latest prebuilt binary from releases (detects architecture automatically)
  - Handles zip file downloads and extraction automatically
  - On Apple Silicon (arm64), uses native arm64 binary (required - x86_64 crashes with QEMU)
  - On x86_64, uses x86_64 binary
- Builds/rebuilds wrapper Docker image with platform-specific naming (e.g., `apple-music-wrapper-arm64`, `apple-music-wrapper-x86_64`)
  - Automatically cleans up old wrapper images before building
  - Rebuilds if binary is newer
- Attempts to pull the downloader Docker image

**Note:** The wrapper Docker image is built automatically from the latest prebuilt binary. The setup script ensures you have the latest code and binary before building.

**Note:** The wrapper runs in a Docker container (not a local binary), as recommended by the wrapper documentation.

**Note:** On Apple Silicon (arm64), the wrapper uses native arm64 binaries and Docker images by default (no emulation needed). The downloader still uses `--platform linux/amd64` to run x86_64 images via Rosetta 2, as the downloader image doesn't have native arm64 builds yet.

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

**The `.env` file is required for credentials!** The script works with sensible defaults for other settings:
- Wrapper host: `127.0.0.1`, port: `10020`
- Output directory: `~/Downloads`

You must create `.env` and configure credentials for the wrapper to function.

To create and configure:

```bash
cp .env.template .env
# Edit .env if you want to customize settings
```

**Settings:**
- `APPLE_MUSIC_USERNAME` / `APPLE_MUSIC_PASSWORD` - Login credentials for wrapper. **Required** - wrapper requires credentials to function.
- `APPLE_MUSIC_WRAPPER_HOST` - Wrapper host (default: 127.0.0.1)
- `APPLE_MUSIC_WRAPPER_PORT` - Wrapper port (default: 10020)
- `APPLE_MUSIC_MEDIA_USER_TOKEN` - **Not required for basic ALAC downloads**, but required for:
  - Lyrics (LRC, word-by-word, translations)
  - aac-lc format (lossy, lower quality - avoid if you want lossless)
  - MV downloads (music videos - not needed for audio-only)
  
  Extract from browser cookies: `Application -> Storage -> Cookies -> https://music.apple.com`, find cookie named `media-user-token`. See [Format Explanations](#format-explanations) section for details.

The `.env` file is gitignored for security.

## Quality

**ALAC (lossless) is the default and highest quality format.** The script requires ALAC to be available and will error out if ALAC is not available for any track.

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
- Not used by this script (script errors if ALAC unavailable)

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
- Not used by this script (script errors if ALAC unavailable)
- Not recommended for lossless audio collection

**Other formats (AAC, etc.)**
- Lossy formats, lower quality than ALAC
- Not used by this script (script errors if ALAC unavailable)
- Not recommended for lossless audio collection

## Prerequisites

1. **Docker** - Must be installed and running (install manually from [Docker Desktop](https://www.docker.com/products/docker-desktop))
2. **Active Apple Music subscription** - Required for decryption

**Note:** All dependencies except Docker are automatically installed/updated by `./setup.sh`. You only need to install Docker manually.

**Platform Compatibility:**
- **Apple Silicon (arm64):** Uses native arm64 wrapper binaries. Downloader uses Rosetta 2. **Local Apple Silicon works with single-track downloads** but the wrapper can crash with albums or too many tracks; see [Decryption fails](#decryption-fails-on-apple-silicon-connection-reset-by-peer).
- **x86_64 (Intel Mac/Linux):** Uses native x86_64 wrapper binaries and Docker images.
- **Credentials:** Required on all platforms - wrapper requires login credentials to function.

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

### Decryption fails on Apple Silicon (connection reset by peer)

The arm64 wrapper can **crash during decryption** while the downloader is running. You’ll see errors like:

- `decryptFragment: read tcp ... 127.0.0.1:10020: read: connection reset by peer`
- `dial tcp 127.0.0.1:10020: connect: connection refused` (wrapper down, restarting)

This is a known limitation of the prebuilt arm64 wrapper binary ([wrapper issue #8](https://github.com/WorldObservationLog/wrapper/issues/8)). The wrapper exits during decryption, Docker restarts it with the cached session, but the current download fails.

**Workarounds:**

1. **Retry** – The downloader retries on error. Run the download again; it may succeed after the wrapper has restarted.
2. **Download one track at a time** – Use **song URLs** instead of album URLs. Single-track downloads often succeed when album downloads crash; sustained decrypt load across many tracks appears to trigger the failure.
3. **Use remote decryption** – [AppleMusicDecrypt](https://github.com/WorldObservationLog/AppleMusicDecrypt) can use a remote `wrapper-manager` (e.g. `wm.wol.moe`) instead of a local wrapper, avoiding the arm64 decrypt crash.
4. **Use x86_64 Linux** – The x86_64 wrapper is more stable; use a Linux x86_64 machine or VM if you need reliable decryption.

### "You've reached your device limit" (Apple Music)

If the wrapper shows:

```
dialogHandler: {title: You've Reached Your Device Limit, message: You have reached the limit on the maximum number of concurrent playing devices.}
```

Apple Music limits how many devices can use your subscription at once. Too many logins (e.g. repeated `./wrapper.sh login` or 2FA retries) can hit this.

**What to do:**

1. **Stop creating new sessions** – `./wrapper.sh stop` and avoid `./wrapper.sh login` until you’ve freed devices.
2. **Sign out of Apple Music** on devices you’re not using (other computers, old phones, tablets).
3. **Remove old devices** – [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → Devices → remove unused devices.
4. **Wait** – Limits sometimes reset after a short cooldown.
5. **Use cached session** – When you retry, use `./wrapper.sh start` only (no `login`). The wrapper reuses the cached session and doesn’t create a new device each time.

### MP4Box not found
```bash
which MP4Box || which mp4box
brew reinstall gpac  # macOS
```

### First-time setup with 2FA

**Credentials are REQUIRED** - the wrapper requires login credentials to function on all platforms.

1. **Configure credentials:**
   ```bash
   cp .env.template .env
   # Edit .env and set APPLE_MUSIC_USERNAME and APPLE_MUSIC_PASSWORD
   ```

2. **Start the wrapper:**
   ```bash
   ./wrapper.sh start
   ```

3. **Enter 2FA code (60 second timeout):**
   When the wrapper prompts for 2FA, write the code to the data directory:
   ```bash
   echo -n 123456 > data/data/com.apple.android.music/files/2fa.txt
   ```
   (Replace `123456` with your actual 2FA code)

4. **Verify it's running:**
   ```bash
   docker logs apple-music-wrapper
   # Should show: [!] listening 0.0.0.0:10020
   ```

**Session caching:** Once authenticated, the session is cached in `data/`. The wrapper will automatically use the cached session on subsequent starts - no 2FA needed unless the cache is cleared.

**Re-authentication:** If you need to re-authenticate (session expired, credentials changed), use:
```bash
./wrapper.sh login
```

### Apple Silicon (arm64) - IMPORTANT

**Single-track vs albums:** Local Apple Silicon **works with single-track (song) downloads** but the wrapper can **crash with albums or too many tracks** during decryption. See [Decryption fails](#decryption-fails-on-apple-silicon-connection-reset-by-peer) for workarounds.

**Technical details:**
- **Wrapper binary:** Uses native arm64 binary compiled with Android NDK, linking against Android Apple Music app libraries
- **Wrapper Docker image:** Named `apple-music-wrapper-arm64`
- **Downloader image:** Uses `--platform linux/amd64` to run x86_64 images via Rosetta 2 (no native arm64 build available)
- **x86_64 wrapper on Apple Silicon:** Not supported - QEMU emulation crashes with segmentation faults

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

## Remote wrapper (x86_64)

If the local arm64 wrapper crashes during decryption (e.g. "connection reset by peer"), you can run the **wrapper** remotely on x86_64 and keep the **downloader** local. The downloader works fine; the issue is the arm64 wrapper. You do **not** need AppleMusicDecrypt or wrapper-manager for this.

### Why decrypt can fail even with a single download

Even one downloader still uses **streaming decrypt**: it sends encrypted chunks to the wrapper and receives decrypted chunks back. Requests can overlap (e.g. next chunk while the previous decrypt is in flight), or the arm64 wrapper can crash on that code path regardless. So it’s not necessarily concurrency across tracks; it can be arm64 wrapper instability under decrypt load.

### Best approach: remote wrapper + same downloader

- **Downloader:** Keep using the current one (zhaarey) locally.
- **Wrapper:** Run it remotely on **x86_64** (e.g. ECS, EC2, or any Linux x86_64 host).
- **No** AppleMusicDecrypt, **no** wrapper-manager for single-user, single-download use.

### Running the wrapper on ECS (or similar)

1. **Build the wrapper for x86_64**  
   Use the existing setup (main-branch Dockerfile + prebuilt binary), but build for `linux/amd64`, e.g. `docker build --platform linux/amd64 -t wrapper .`, or run `./setup.sh` on an x86_64 machine/runner.

2. **Run the wrapper on ECS**  
   - One task/service: wrapper container.
   - Expose **10020** (decrypt), **20020** (m3u8), **30020** (account).
   - Use `-H 0.0.0.0` (already the default).
   - Mount a volume (or EFS) for `data/` so the session persists across restarts.
   - Do **one-time login + 2FA** on that remote instance; after that it uses the cached session.

3. **Start the wrapper**  
   The wrapper can be **started remotely** (e.g. via ECS task definition, systemd, or your orchestrator). You can also trigger a remote run from your machine (e.g. SSH + `docker run`, or ECS RunTask) if you prefer; the important part is that it runs on x86_64 with persistent `data/`.

4. **Point the downloader at the remote wrapper**  
   The downloader reads **config.yaml** (`decrypt-m3u8-port`, `get-m3u8-port`), not env vars. To use a remote wrapper you must **mount a config** that sets those to your remote host:port, for example:

   ```yaml
   decrypt-m3u8-port: "your-ecs-host-or-alb:10020"
   get-m3u8-port: "your-ecs-host-or-alb:20020"
   ```

   The current scripts use `APPLE_MUSIC_WRAPPER_HOST` / `APPLE_MUSIC_WRAPPER_PORT` only for **checking** reachability and for **wrapper.sh**; they do **not** pass wrapper URL into the downloader container. Support for a remote wrapper would require generating or using a config that points at the remote host when using a non-local wrapper.

### Do you need wrapper-manager?

**No**, for single-user, single-download use. wrapper-manager is for multi-instance, load balancing, and higher throughput. A **single** wrapper on ECS (or similar) is enough. Add wrapper-manager only if you later need multiple wrappers or scaling.

### Summary

- **Best bet:** Run the **wrapper** on **ECS (or any x86_64 host)** using the existing build/Docker setup; run the **downloader** locally.
- **Gap today:** The downloader gets the wrapper URL from **config**, not from our env. We’d need to add logic (e.g. when using a remote host) to create or mount a `config.yaml` with `decrypt-m3u8-port` / `get-m3u8-port` pointing at the remote wrapper.
- **Keep the local flow** for others who run wrapper + downloader locally (e.g. on x86_64 Linux or when arm64 works for them).

## References

### Primary Resources
- **apple-music-downloader:** [https://github.com/zhaarey/apple-music-downloader](https://github.com/zhaarey/apple-music-downloader) - Full documentation, all options, advanced features
- **wrapper:** [https://github.com/WorldObservationLog/wrapper](https://github.com/WorldObservationLog/wrapper) - Docker setup (recommended), source build instructions, detailed options

### Related Projects from Wrapper Maintainer
The maintainer of the wrapper project (WorldObservationLog) has created additional projects that build on the wrapper ecosystem:

- **AppleMusicDecrypt** ([https://github.com/WorldObservationLog/AppleMusicDecrypt](https://github.com/WorldObservationLog/AppleMusicDecrypt)) - A Python-based all-in-one downloader that combines downloading and decryption in a single application. Key features:
  - Alternative to `zhaarey/apple-music-downloader` with built-in Python downloader
  - **V2 supports remote decryption** via `wrapper-manager` instances (can work without local wrapper or even Apple Music subscription)
  - Can use public wrapper-manager instances (e.g., `wm.wol.moe`) for decryption
  - Simpler setup: single Python application with poetry
  - Supports same codecs (ALAC, EC3, AC3, AAC variants) and link types (songs, albums, artists, playlists)
  - **Apple Silicon compatible** (Python runs natively)

- **wrapper-manager** ([https://github.com/WorldObservationLog/wrapper-manager](https://github.com/WorldObservationLog/wrapper-manager)) - A Go-based tool for managing multiple wrapper instances simultaneously. Key features:
  - Multi-instance management (orchestrates multiple wrappers behind one endpoint)
  - Multi-connection decryption (parallel decryption, up to 40MB/s per instance)
  - Add accounts at runtime (including 2FA support)
  - gRPC API for programmatic control
  - Get lyrics without an account
  - Automatic region detection
  - **Platform support:** Linux x86_64 and arm64 (can run in Docker on macOS)

**Relationship to current setup:**
- Your current setup uses `zhaarey/apple-music-downloader` + local `wrapper` (single instance)
- `AppleMusicDecrypt` is an alternative downloader that can use remote `wrapper-manager` instances
- `wrapper-manager` is useful if you want to run a local decryption service with multiple accounts or need faster parallel decryption
- These projects don't solve wrapper issues directly (they depend on wrapper/wrapper-manager), but `AppleMusicDecrypt` with remote decryption could bypass local wrapper problems entirely

**When to explore:**
- **AppleMusicDecrypt:** If you want to test remote decryption (bypassing local wrapper), need a simpler single-app solution, or want an alternative client
- **wrapper-manager:** If you want to run a local decryption service for multiple accounts, need faster parallel decryption, or are setting up infrastructure for others

### Historical Reference
The [rentry.org guide](https://rentry.org/firehawk52/#apple-music_1) contains historical information about various Apple Music download methods (some deprecated) and references to other music downloading utilities (Deezer, Qobuz, Tidal, Spotify, etc.). Useful for understanding tool evolution and finding alternatives.

## Legal Notice

This tool is intended for use with a **legitimate, paid Apple Music subscription**. It allows you to download music you have access to through your subscription for personal use. Ensure you comply with Apple Music's terms of service and local copyright laws.

## Version Information

- **Documentation created:** January 25, 2026
- **apple-music-downloader:** Latest from main branch (check [releases](https://github.com/zhaarey/apple-music-downloader/releases))
- **wrapper:** Latest from main branch (check [releases](https://github.com/WorldObservationLog/wrapper/releases))

When referring to this documentation, note the creation date to understand which versions of the upstream READMEs were referenced.
