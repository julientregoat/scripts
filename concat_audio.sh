# TODO checks:
# 3. only run ffmpeg if there are files to combine; otherwise inform user

set -e

SOURCE_DIR_ABS=$(echo $1 | sed "s/ /\ /g")
if [ -z $SOURCE_DIR_ABS ]; then
    echo "Missing source directory argument."
    exit 1
fi

SOURCE_FORMAT=$2
if [ -z $SOURCE_FORMAT ]; then
    echo "Missing source format argument."
    exit 1
fi

if [ -z $(command -v ffmpeg) ]; then
    echo "ffmpeg must be installed."
    exit 1
fi


cd "$SOURCE_DIR_ABS"

SOURCE_DIR_NAME=${PWD##*/}
TARGET_ROOT=$(echo $SOURCE_DIR_NAME | sed "s/ /_/g")
TARGET_LIST=${TARGET_ROOT}_concat.txt
TARGET_FILE=$TARGET_ROOT.$SOURCE_FORMAT

echo "\n-abs" $SOURCE_DIR_ABS\
"\n-format" $SOURCE_FORMAT\
"\n-dir name" $SOURCE_DIR_NAME\
"\n-output target" $TARGET_FILE\
"\n-list target" $TARGET_LIST "\n"

if test -f $TARGET_LIST; then
    echo "target concat list file $TARGET_LIST exists; deleting.\n"
    rm $TARGET_LIST
fi

# NB: to use single quote in filenames with ffmpeg, need to escape them as '\''
for f in *.mp3; do
    if [[ $f == $TARGET_FILE ]]; then
        # prevents a loop of reading data from source to target, which are the same
        # ffmpeg handles prompting the user if they want to overwrite existing target
        echo "target audio file detected while composing concat list; skipping.\n"
    else
        echo "file '$(echo $f | sed "s/'/'\\\''/g")" >> $TARGET_LIST;
    fi
done
# for some reason, printf seems to ruin the special escape sequence
# printf "file '$(echo %s | sed "s/'/'\\\''/g")'\n" *.$SOURCE_FORMAT > $TARGET_LIST

# FIXME check if list has files here

ffmpeg -f concat -safe 0 -i $TARGET_LIST -c copy $TARGET_FILE

echo "concatenated audio to $TARGET_FILE\n"

rm "$TARGET_LIST"
