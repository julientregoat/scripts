# TODO checks:
# 1. source dir and format provided
# 2. source dir exists?
# 3. only run ffmpeg if there are files to combine; otherwise inform user
# 4. ffmpeg exists

SOURCE_DIR_ABS=$1
SOURCE_FORMAT=$2
SOURCE_DIR_NAME=$( echo ${SOURCE_DIR_ABS##*/} )

TARGET_LIST=$SOURCE_DIR_NAME.txt
TARGET_FILE=$SOURCE_DIR_NAME.$SOURCE_FORMAT

echo "\n" $SOURCE_DIR_ABS "\n" $SOURCE_FORMAT "\n" $SOURCE_DIR_NAME "\n" $TARGET_FILE "\n" $TARGET_LIST "\n"
cd "$SOURCE_DIR_ABS"

# FIXME support files with single quotes - need to escape them to not interfere
printf "file '%s'\n" *.$SOURCE_FORMAT > $TARGET_LIST
# printf "file '$(echo %s | tr "'" "\\'")'\n" *.$SOURCE_FORMAT > $TARGET_LIST
# cat $TARGET_LIST | tr "'" "\\'" # this works but affects main list

ffmpeg -f concat -safe 0 -i $TARGET_LIST -c copy $TARGET_FILE

echo "concatenated audio to $TARGET_FILE\n"

rm "$TARGET_LIST"
