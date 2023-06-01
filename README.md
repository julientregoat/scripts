# scripts

- `concat_audio.sh` - given a directory containing audio files **_of a single format_**, concatenates the audio to a single file using the same input format. **NB:** files are sorted by however bash defaults; generally the standard bash directory sorting, i.e. symbols > numerical > alphabetical. this was intended to combine dj mixes that have been split into files by track, and relies on track numbers in the file name to order correctly. uses `ffmpeg`
- `extract_video_audio.sh` - extracts audio from a video file using `ffmpeg`. outputs audio as a WAV file to the same dir as the source file using the same name
