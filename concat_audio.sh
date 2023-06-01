set -e

# escape spaces in dirnames FIXME this may not be needed if we wrap it in quotes
SOURCE_DIR_ABS=$(echo $1 | sed "s/ /\ /g") 
if [ -z $SOURCE_DIR_ABS ]; then
    echo "error: missing source directory argument."
    exit 1
fi

SOURCE_FORMAT=$2
if [ -z $SOURCE_FORMAT ]; then
    echo "error: missing source format argument."
    exit 1
fi

if [ -z $(command -v ffmpeg) ]; then
    echo "error: ffmpeg must be installed."
    exit 1
fi


cd "$SOURCE_DIR_ABS"
SOURCE_DIR_NAME=${PWD##*/} # extract name from current working dir (now source dir)
# replace spaces with underscore to prevent issues
# FIXME may not be needed if we use quotes around $TARGET_FILE later on
TARGET_ROOT=$(echo $SOURCE_DIR_NAME | sed "s/ /_/g")
TARGET_LIST=${TARGET_ROOT}_concat.txt
TARGET_FILE=$TARGET_ROOT.$SOURCE_FORMAT

# echo "debug\n-abs" $SOURCE_DIR_ABS\
# "\n-format" $SOURCE_FORMAT\
# "\n-dir name" $SOURCE_DIR_NAME\
# "\n-output target" $TARGET_FILE\
# "\n-list target" $TARGET_LIST "\n"

if [ -f $TARGET_LIST ]; then
    echo "target concat list file $TARGET_LIST exists; deleting.\n"
    rm $TARGET_LIST
fi

for f in *.$SOURCE_FORMAT; do
    if [[ $f == $TARGET_FILE ]]; then
        # prevents a loop of reading data from source to target, which are the same
        # ffmpeg handles prompting the user if they want to overwrite existing target
        echo "target audio file detected while composing concat list; skipping.\n"
    else
        # NB: for the ffmpeg concat source list, filenames are single quoted
        # this causes problems for files with apostrophes in them etc
        # to use single quote in filenames with ffmpeg, need to escape them like so:
        echo "file '$(echo $f | sed "s/'/'\\\''/g")'" >> $TARGET_LIST;

        # for some reason, printf seems to ruin the special escape sequence
        # printf "file '$(echo %s | sed "s/'/'\\\''/g")'\n" *.$SOURCE_FORMAT > $TARGET_LIST
    fi
done


if [ ! -s $TARGET_LIST ]; then
    echo "error: source directory has no files with source format to combine"
    exit 1
fi

ffmpeg -f concat -safe 0 -i $TARGET_LIST -c copy $TARGET_FILE

echo "concatenated audio to $TARGET_FILE\n"

rm "$TARGET_LIST"
