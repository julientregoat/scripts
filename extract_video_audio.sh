set -e

if [ -z $(command -v ffmpeg) ]; then
    echo "error: ffmpeg must be installed."
    exit 1
fi

SOURCE_VIDEO=$1
SOURCE_VIDEO_DIR=$(dirname "$SOURCE_VIDEO")
SOURCE_VIDEO_FILENAME=$(basename "$SOURCE_VIDEO") # test --
SOURCE_VIDEO_NAME="${SOURCE_VIDEO_FILENAME%.*}"

cd "$SOURCE_VIDEO_DIR"

ffmpeg -i "$SOURCE_VIDEO" "$SOURCE_VIDEO_NAME.wav"
