# TODO checks:
# 1. source dir and format provided
# 2. source dir exists?
# 3. only run ffmpeg if there are files to combine; otherwise inform user
# 4. ffmpeg exists

set -e

SOURCE_DIR_ABS=$(printf '%q\n' "$1")
SOURCE_FORMAT=$2
# echo $SOURCE_DIR_ABS
cd $SOURCE_DIR_ABS # FIXME fails with spaces in the name

SOURCE_DIR_NAME=${PWD##*/}
TARGET_LIST=$SOURCE_DIR_NAME.txt
TARGET_FILE=$SOURCE_DIR_NAME.$SOURCE_FORMAT

echo "\n-abs" $SOURCE_DIR_ABS "\n-format" $SOURCE_FORMAT "\n-dir name" $SOURCE_DIR_NAME "\n-output target" $TARGET_FILE "\n-list target" $TARGET_LIST "\n"

# NB: to use single quote in filenames with ffmpeg, need to escape them as '\''
# for some reason, the for loop works and printf doesn't
for f in *.mp3; do echo "file '$(echo $f | sed "s/'/'\\\''/g")" >> $TARGET_LIST; done
# printf "file '$(echo %s | sed "s/'/'\\\''/g")'\n" *.$SOURCE_FORMAT > $TARGET_LIST

ffmpeg -f concat -safe 0 -i $TARGET_LIST -c copy $TARGET_FILE

echo "concatenated audio to $TARGET_FILE\n"

rm "$TARGET_LIST"
