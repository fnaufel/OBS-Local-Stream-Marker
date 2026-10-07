# Local Stream Marker

This project records user-labelled positions in OBS streams and recordings.

## Language

**Point marker**: A user-labelled position in a stream or recording. A workflow may treat successive point markers as boundaries between intervals.

**Marker end**: An optional ending position associated with an earlier point marker. It is separate from placing another point marker.

**Recording timestamp**: The position in a recording's media timeline measured from the beginning of that recording. It does not advance while recording is paused.

**Recording timestamp on file**: The position in the current recording file's media timeline, measured from the beginning of that file.

**Recording pause interval**: One continuous period from pausing a recording until resuming or stopping it, during which its media position remains fixed.
