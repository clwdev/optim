#!/usr/bin/env bash

_help(){
  echo "optimize.sh
Recursively optimize a folder for efficient use on the web.
Optimizes images, videos, and PDFs. Remembers (by way of manifest) the optimized
files to prevent degredation when repeatedly ran on a folder, so that it can
be used in a nightly batch job.

Dependencies:
  OSX / GNU
  Ruby - https://www.ruby-lang.org
  Homebrew - http://brew.sh
  pv - http://www.ivarch.com/programs/pv.shtml

Optionals:
  pngout - http://www.jonof.id.au/kenutils

Utilizes:
  Image Optim - https://github.com/toy/image_optim
    (Including packed dependencies)
  Handbrake CLI - https://handbrake.fr/downloads2.php
  Ghostscript - http://www.ghostscript.com

Options:
  --path={directory}        Optionally specify the path to optimize.
                            By default the current directory will be
                            optimized recursively.
  --file={filename.ext}     Optionally optimize a single file instead of an
                            entire folder. Off by default.
  --image=true              Optimize images.
  --image-lossy=true        When optimizing images, allow lossy compression
                            for greatly reduced overhead.
  --image-lossy-quality=85  If lossy compression is enabled, this is the
                            quality used to downsize the image (1 ~ 100).
  --image-max-size=true     If images are likely too large for your server
                            to resize (with ImageMagick or GD library)
                            resize them to a rational scale, preserving the
                            aspect ratio.
  --image-max-width=3840    Set the maximum width of an an image. If
                            downscaling is enabled, an image wider than this
                            will be downscaled.
  --image-max-height=2160   Set the maximum height of an an image. If
                            downscaling is enabled, an image taller than
                            this will be downscaled.
  --image-metadata=true     Optionally preserve metadata on the images.
                            Important if your clients are professional
                            photographers, otherwise not typically needed.
  --video=true              Optimize videos for web.
                            All video compression is lossy.
  --video-quality=20        Specify the minimum video quality (20 is great).
  --video-max-width=1920    Maximum width for optimized videos.
  --video-max-height=1080   Maximum height for optimized videos.
  --doc=true                Optimize PDFs (or similar files) for web.
                            All document compression is lossy.
  --manifest=true           Include a manifest so that this script can be
                            ran repeatedly, skipping files that have already
                            been compressed to prevent degredation. If this
                            is disabled, we do NOT reccomend running this
                            script more than once on a server!
  --manifest-name=.optim    The name of the folder to contain the manifest in
  --silent=false            Optionally run silently.
  --dependency-check=true   When starting, first ensure all dependencies are
                            installed. If they aren't, download them.
  --help                    Output's this screen.
"
  exit 1
}

# Evaluate a string for a boolean value, return 0 (no error) if true, or 1 (error) if false
_bool(){
  if [[ "$1" = "true" || "$1" = "1" ]] ; then
    return 0
  fi
  return 1
}

# Die with an error
_die(){
  echo "ERROR: $1"
  exit 1
}

# Check if a list of params contains a specific param
# usage: if _param_variant "h|?|help p|path f|file long-thing t|test-thing" "file" ; then ...
# the global variable $key is updated to the long notation (last entry in the pipe delineated list, if applicable)
_param_variant() {
  for param in $1 ; do
    local variants=${param//\|/ }
    for variant in $variants ; do
      if [[ "$variant" = "$2" ]] ; then
        # Update the key to match the long version
        local arr=(${param//\|/ })
        let last=${#arr[@]}-1
        key="${arr[$last]}"
        return 0
      fi
    done
  done
  return 1
}

# Get input parameters in short or long notation, with no dependencies beyond bash
# usage:
#     # First, set your defaults
#     param_help=false
#     param_path="."
#     param_file=false
#     param_image=false
#     param_image_lossy=true
#     # Define allowed parameters
#     allowed_params="h|?|help p|path f|file i|image image-lossy"
#     # Get parameters from the arguments provided
#     _get_params $*
#
# Parameters will be converted into safe variable names like:
#     param_help,
#     param_path,
#     param_file,
#     param_image,
#     param_image_lossy
#
# Parameters without a value like "-h" or "--help" will be treated as
# boolean, and will be set as param_help=true
#
# Parameters can accept values in the various typical ways:
#     -i "path/goes/here"
#     --image "path/goes/here"
#     --image="path/goes/here"
#     --image=path/goes/here
# These would all result in effectively the same thing:
#     param_image="path/goes/here"
#
# Concatinated short parameters (boolean) are also supported
#     -vhm is the same as -v -h -m
_get_params(){

  local param_pair
  local key
  local value
  local shift_count

  while : ; do
    # Ensure we have a valid param. Allows this to work even in -u mode.
    if [[ $# == 0 || -z $1 ]] ; then
      break
    fi

    # Split the argument if it contains "="
    param_pair=(${1//=/ })
    # Remove preceeding dashes
    key="${param_pair[0]#--}"

    # Check for concatinated boolean short parameters.
    local nodash="${key#-}"
    local breakout=false
    if [[ "$nodash" != "$key" && ${#nodash} -gt 1 ]]; then
      # Extrapolate multiple boolean keys in single dash notation. ie. "-vmh" should translate to: "-v -m -h"
      local short_param_count=${#nodash}
      let new_arg_count=$#+$short_param_count-1
      local new_args=""
      # $str_pos is the current position in the short param string $nodash
      for (( str_pos=0; str_pos<new_arg_count; str_pos++ )); do
        # The first character becomes the current key
        if [ $str_pos -eq 0 ] ; then
          key="${nodash:$str_pos:1}"
          breakout=true
        fi
        # $arg_pos is the current position in the constructed arguments list
        let arg_pos=$str_pos+1
        if [ $arg_pos -gt $short_param_count ] ; then
          # handle other arguments
          let orignal_arg_number=$arg_pos-$short_param_count+1
          local new_arg="${!orignal_arg_number}"
        else
          # break out our one argument into new ones
          local new_arg="-${nodash:$str_pos:1}"
        fi
        new_args="$new_args \"$new_arg\""
      done
      # remove the preceding space and set the new arguments
      eval set -- "${new_args# }"
    fi
    if ! $breakout ; then
      key="$nodash"
    fi

    # By default we expect to shift one argument at a time
    shift_count=1
    if [ "${#param_pair[@]}" -gt "1" ] ; then
      # This is a param with equals notation
      value="${param_pair[1]}"
    else
      # This is either a boolean param and there is no value,
      # or the value is the next command line argument
      # Assume the value is a boolean true, unless the next argument is found to be a value.
      value=true
      if [[ $# -gt 1 && -n "$2" ]]; then
        local nodash="${2#-}"
        if [ "$nodash" = "$2" ]; then
          # The next argument has NO preceding dash so it is a value
          value="$2"
          shift_count=2
        fi
      fi
    fi

    # Check that the param being passed is one of the allowed params
    if _param_variant "$allowed_params" "$key" ; then
      # --key-name will now become param_key_name
      eval param_${key//-/_}="$value"
      echo "$key = $value"
    else
      printf 'WARNING: Unknown option (ignored): %s\n' "$1" >&2
    fi
    shift $shift_count
  done
}

_find_images(){
  result=`find "$1"                        \
    -type f \(                             \
          -iname "*.png"                   \
      -or -iname "*.bgp"                   \
      -or -iname "*.gif"                   \
      -or -iname "*.hdr"                   \
      -or -iname "*.jpg"                   \
      -or -iname "*.jpeg"                  \
      -or -iname "*.rif"                   \
      -or -iname "*.tif"                   \
      -or -iname "*.tiff"                  \
      -or -iname "*.webp"                  \
    \)                                     \
    -and ! \(                              \
      -path ".*"                           \
      -or -path "*.dropbox.cache*"         \
    \)                                     \
    -size +100c                            \
    -exec stat -qn -f '%N|%z|' {}          \;\
    -exec md5 -qs {}                       \;`
}

_find_videos(){
  result=`find "$1"                        \
    -type f \(                             \
          -iname "*.webm"                  \
      -or -iname "*.3gp"                   \
      -or -iname "*.3g2"                   \
      -or -iname "*.asf"                   \
      -or -iname "*.avi"                   \
      -or -iname "*.drc"                   \
      -or -iname "*.flv"                   \
      -or -iname "*.m2v"                   \
      -or -iname "*.mkv"                   \
      -or -iname "*.m4p"                   \
      -or -iname "*.m4v"                   \
      -or -iname "*.mng"                   \
      -or -iname "*.mp2"                   \
      -or -iname "*.mp4"                   \
      -or -iname "*.mpe"                   \
      -or -iname "*.mpeg"                  \
      -or -iname "*.mpg"                   \
      -or -iname "*.mpv"                   \
      -or -iname "*.mov"                   \
      -or -iname "*.mxf"                   \
      -or -iname "*.nsv"                   \
      -or -iname "*.ogv"                   \
      -or -iname "*.ogg"                   \
      -or -iname "*.qt"                    \
      -or -iname "*.rm"                    \
      -or -iname "*.rmvb"                  \
      -or -iname "*.roq"                   \
      -or -iname "*.svi"                   \
      -or -iname "*.wmv"                   \
      -or -iname "*.yuv"                   \
    \)                                     \
    -and ! \(                              \
      -path ".*"                           \
      -or -path "*.dropbox.cache*"         \
    \)                                     \
    -size +10k                             \
    -exec stat -qn -f '%N|%z|' {}          \;\
    -exec md5 -qs {}                       \;`
}

_find_docs(){
  result=`find "$1"                        \
    -type f \(                             \
      -iname "*.pdf"                       \
    \)                                     \
    -and ! \(                              \
      -path ".*"                           \
      -or -path "*.dropbox.cache*"         \
    \)                                     \
    -size +10k                             \
    -exec stat -qn -f '%N|%z|' {}          \;\
    -exec md5 -qs {}                       \;`
}

# Find all appropriate files in manifest variables.
# They will follow the format:
#   /Absolute/path/here|original size|optimize size, if appropriate|md5 hash
_generate_manifest(){
  # Spool through files to create a complete file list.
  if _bool "$param_image" ; then
    # Find Image files and generate MD5s
    printf "Searching for images..."
    _find_images "$param_path"
    new_image_manifest="$result"
    new_image_file_count=$( echo "$new_image_manifest" | wc -l )
    new_image_file_count=${new_image_file_count// /}
    printf " found $new_image_file_count\n"
  fi
  if _bool "$param_video" ; then
    # Find video files and generate MD5s
    printf "Searching for videos..."
    _find_videos "$param_path"
    new_video_manifest="$result"
    new_video_file_count=$( echo "$new_video_manifest" | wc -l )
    new_video_file_count=${new_video_file_count// /}
    printf " found $new_video_file_count\n"
  fi
  if _bool "$param_doc" ; then
    # Find documents and generate MD5s
    printf "Searching for documents..."
    _find_docs "$param_path"
    new_doc_manifest="$result"
    new_doc_file_count=$( echo "$new_doc_manifest" | wc -l )
    new_doc_file_count=${new_doc_file_count// /}
    printf " found $new_doc_file_count\n"
  fi
  new_total_file_count=$(( $new_image_file_count + $new_video_file_count + $new_doc_file_count ))
}

# Take md5 lists and simplify them to exclude the absolute paths
_flaten_manifest(){
  local input="$1"
  result=$( echo "$input" | sed -e 's/.*\///' )
}

# Load an existing manifest, if present
_load_manifest(){
  if [ -d "$param_path/$param_manifest_name" ] ; then
    if _bool "$param_image" ; then
      if [ -f "$param_path/$param_manifest_name/image.man" ] ; then
        old_image_manifest=$(<"$param_path/$param_manifest_name/image.man")
        old_image_file_count=$( echo "$old_image_manifest" | wc -l )
        old_image_file_count=${old_image_file_count// /}
      fi
    fi
    if _bool "$param_video" ; then
      if [ -f "$param_path/$param_manifest_name/video.man" ] ; then
        old_video_manifest=$(<"$param_path/$param_manifest_name/video.man")
        old_video_file_count=$( echo "$old_video_manifest" | wc -l )
        old_video_file_count=${old_video_file_count// /}
      fi
    fi
    if _bool "$param_doc" ; then
      if [ -f "$param_path/$param_manifest_name/doc.man" ] ; then
        old_doc_manifest=$(<"$param_path/$param_manifest_name/doc.man")
        old_doc_file_count=$( echo "$old_doc_manifest" | wc -l )
        old_doc_file_count=${old_doc_file_count// /}
      fi
    fi
    old_total_file_count=$(( $old_image_file_count + $old_video_file_count + $old_doc_file_count ))
  else
    echo "No manifest found, assuming this is a new folder."
  fi
}

# Append a string to a manifest file
# usage:  _append_manifest <type> "string"
# type: image, video or doc
_append_manifest(){
  local manifest_type="$1"
  local string="$2"

  if _bool "$param_manifest" ; then

    # Ensure the manifest folder exists
    if [ ! -d "$param_path/$param_manifest_name" ] ; then
      mkdir "$param_path/$param_manifest_name"
    fi

    # Append the string to the file
    echo "$string" >> "$param_path/$param_manifest_name/$manifest_type.man"
  fi
}

# Start logging progress
process_running=false
_start_progress_indicator(){
  local manifest_type="$1"
  local progress_name="$2"
  local size="$3"

  if [[ -f "$param_path/$param_manifest_name/$manifest_type.man" ]] ; then
    if ! _bool "$process_running" ; then
      process_running=true
      tail -f "$param_path/$param_manifest_name/$manifest_type.man" | pv --interval 1 --progress --timer --eta --name "$progress_name" --line-mode --size $size >/dev/null &
    fi
  fi
}

# Compare two variables, find lines in $2 that are not in $1
# Excluding path specificity on the file name (which is the hard part)
_line_diff(){
  local a="$1"
  local b="$2"
  local flat_a=$( echo "$a" | sed -e 's/.*\///' )
  local flat_b=$( echo "$b" | sed -e 's/.*\///' )
  result=""
  # Loop through the diff lines, to find the long-version of these lines
  # That will result in a list of absolute paths to files that need to be optimized
  lines=$( comm -13 <(echo "$flat_a") <(echo "$flat_b") )
  tmpdir=$(mktemp -dt "$0")
  tmpfilea="$tmpdir/line_diffa_a.tmp"
  tmpfileb="$tmpdir/line_diff_b.tmp"
  echo "$b" > "$tmpfilea"

  # Batch out the searches to parallel processes in batches of 8
  while chunk=$(_batch 8) ; do
    # For each line in the chunk
    while read line ; do
      if [ ! -z "$line" ] ; then
        LC_ALL=C grep -F "$line" "$tmpfilea" >> "$tmpfileb" &
      fi
    done <<< "$chunk"
    wait
  done <<< "$lines"
  wait
  result=$(<"$tmpfileb")
}

# Compare old and new manifests, return new lines only
_diff_manifest(){
  # Line by line comparison of old to new manifests.
  if [[ $old_total_file_count > 0 ]] ; then
    echo "$old_total_file_count files were previously optimized."
  fi
  if _bool "$param_image" ; then
    printf "Discerning optimizable images..."
    if [[ $old_image_file_count > 0 ]] && _bool "$param_manifest" ; then
      _line_diff "$old_image_manifest" "$new_image_manifest"
      diff_image_manifest="$result"
    else
      diff_image_manifest="$new_image_manifest"
    fi
    todo_image_file_count=$( echo "$diff_image_manifest" | wc -l )
    todo_image_file_count=${todo_image_file_count// /}
    printf " found $todo_image_file_count\n"
  fi
  if _bool "$param_video" ; then
    printf "Discerning optimizable videos..."
    if [[ $old_video_file_count > 0 ]] && _bool "$param_manifest" ; then
      _line_diff "$old_video_manifest" "$new_video_manifest"
      diff_video_manifest="$result"
    else
      diff_video_manifest="$new_video_manifest"
    fi
    todo_video_file_count=$( echo "$diff_video_manifest" | wc -l )
    todo_video_file_count=${todo_video_file_count// /}
    printf " found $todo_video_file_count\n"
  fi
  if _bool "$param_doc" ; then
    printf "Discerning optimizable docs..."
    if [[ $old_doc_file_count > 0 ]] && _bool "$param_manifest" ; then
      _line_diff "$old_doc_manifest" "$new_doc_manifest"
      diff_doc_manifest="$result"
    else
      diff_doc_manifest="$new_doc_manifest"
    fi
    todo_doc_file_count=$( echo "$diff_doc_manifest" | wc -l )
    todo_doc_file_count=${todo_doc_file_count// /}
    printf " found $todo_doc_file_count\n"
  fi
}

# Optimize a list of image files for web
# image_optiom handles multiple files at once, one per processor
# _optimize_image source source source source ...
_optimize_image(){
  cd / >/dev/null 2>&1
  eval "image_optim --skip-missing-workers --allow-lossy --no-svgo --no-progress -- $@" >/dev/null
  cd - >/dev/null 2>&1
}

# Optimize multiple images
_optimize_image_batch(){

  local file_list=""
  local file_processed_count=0
  local clean_name=""

  _start_progress_indicator "image" "Image Processing" "$todo_image_file_count"

  # For each chunk of $file_batch_count lines
  while chunk=$(_batch $file_batch_count) ; do

    # Form a string of safe file names to send to image-optim
    file_list=""
    # For each line in the chunk
    while read line ; do
      # For each variable in the line
      while IFS='|' read -ra var ; do
        # Escape spaces
        clean_name="${var[0]}"
        # clean_name="${var[0]// /\\ }"
        # echo "Optimizing: $clean_name"
        file_list="$file_list \"$clean_name\""
        # file_list="$file_list \"${var[0]//\"/\\\"}\""
      done <<< "$line"
      # We now have a list of $file_batch_count files to optimize
    done <<< "$chunk"

    # Begin optimization of this batch
    # echo "Optimizing... $file_list"
    _optimize_image $file_list

    # Compare the original file size to the new size to update the manifest

    # For each line in the chunk
    while read line ; do
      # For each variable in the line
      while IFS='|' read -ra var ; do
        # Escape spaces so that image_optim can take the file names as they are in bulk
        local original_file="${var[0]}"
        local original_size="${var[1]}"
        let bytes_processed=$bytes_processed+$original_size;
      done <<< "$line"

      # Was there any change or optimization?
      _find_images "$original_file"
      local new_file="$result"
      local reduction=0
      if [[ "$new_file" != "$line" ]] ; then
        # Yes, the file was optimized, but by how much exactly?
        while IFS='|' read -ra var ; do
          # Escape spaces so that image_optim can take the file names as they are in bulk
          local new_size="${var[1]}"
        done <<< "$new_file"
        let reduction=$original_size-$new_size
        let bytes_optimized=$bytes_optimized+$reduction
      fi

      # Flatten this single manifest entry (remove absolute path)
      _flaten_manifest "$new_file"
      local flat_manifest_entry="$result"
      _append_manifest "image" "$flat_manifest_entry"

      # Add the amount of reduction to the file at the end also, and save to the reduction manifest as a log of what was done
      if [[ $reduction > 0 ]] ; then
        _append_manifest "image_reduction" "$flat_manifest_entry|$reduction"
      fi

      # Increase count of processed files
      let file_processed_count=$file_processed_count+$file_batch_count

      _start_progress_indicator "image" "Image Processing" "$todo_image_file_count"
    done <<< "$chunk"
  done <<< "$1"
}

# Given a manifest, total the bytes within it of the actual file-size
_count_manifest_bytes(){
  local lines="$1"
  result=0
  while read line ; do
    # Don't diff empty lines
    if [ ! -z "$line" ] ; then
      while IFS='|' read -ra var ; do
        local size="${var[1]}"
        let result=$result+$size
      done <<< "$line"
    fi
  done <<< "$lines"
}

# Calculate how many bytes of new/changed files need optimization
_estimate_work(){
  printf "Estimating workload..."
  if _bool "$param_image" ; then
    _count_manifest_bytes "$diff_image_manifest"
    let bytes_total=$bytes_total+$result
  fi
  if _bool "$param_video" ; then
    _count_manifest_bytes "$diff_video_manifest"
    let bytes_total=$bytes_total+$result
  fi
  if _bool "$param_doc" ; then
    _count_manifest_bytes "$diff_doc_manifest"
    let bytes_total=$bytes_total+$result
  fi
  printf " $(( ${bytes_total%% *} / 1024)) MB\n"
}

# Optimize a single video file for web
# _optimize_video source destination
_optimize_video(){
  source="$1"
  dest="$2"
  HandBrakeCLI --pfr 30 --optimize --encoder x264 --quality 20 --two-pass --turbo --input "$source" --output "$dest" >/dev/null 2>&1
}

# Given a manifest of videos, optimize them all and report progress as each is completed
_optimize_videos(){
  local lines="$1"

  _start_progress_indicator "video" "Video Processing" "$todo_video_file_count"

  while read line ; do
    while IFS='|' read -ra var ; do
      local source="${var[0]}"
      local original_size="${var[1]}"
      # @todo - Support backups... currently overwriting the orginal
      local dest="$source"
      _optimize_video "$source" "$dest"

      _find_videos "$dest"
      local new_file="$result"
      local reduction=0
      if [[ "$new_file" != "$line" ]] ; then
        # Yes, the file was optimized, but by how much exactly?
        while IFS='|' read -ra var ; do
          # Escape spaces so that image_optim can take the file names as they are in bulk
          local new_size="${var[1]}"
        done <<< "$new_file"
        let reduction=$original_size-$new_size
        let bytes_optimized=$bytes_optimized+$reduction
      fi

      # Flatten this single manifest entry (remove absolute path)
      _flaten_manifest "$new_file"
      local flat_manifest_entry="$result"
      _append_manifest "video" "$flat_manifest_entry"

      # Add the amount of reduction to the file at the end also, and save to the reduction manifest as a log of what was done
      if [[ $reduction > 0 ]] ; then
        _append_manifest "video_reduction" "$flat_manifest_entry|$reduction"
      fi

    done <<< "$line"

    _start_progress_indicator "video" "Video Processing" "$todo_doc_file_count"
  done <<< "$lines"
}

# Optimize a single document file for web
# _optimize_doc source destination
_optimize_doc(){
  local source="$1"
  local dest="$2"
#  result=`gs                      \
#    -f "$source"                  \
#    -o "$dest"                    \
#    -dPDFSETTINGS=/screen         \
#    -dDownsampleColorImages=true  \
#    -dDownsampleGrayImages=true   \
#    -dDownsampleMonoImages=true   \
#    -dColorImageResolution=72     \
#    -dGrayImageResolution=72      \
#    -dMonoImageResolution=72      \
#    -dConvertCMYKImagesToRGB=true \
#    -dDetectDuplicateImages=true  \
#    -dEmbedAllFonts=false         \
#    -dSubsetFonts=true            \
#    -dCompressFonts=true          \
#    -c ".setpdfwrite <</AlwaysEmbed [ ]>> setdistillerparams" \
#    -c ".setpdfwrite <</NeverEmbed [/Courier /Courier-Bold /Courier-Oblique /Courier-BoldOblique /Helvetica /Helvetica-Bold /Helvetica-Oblique /Helvetica-BoldOblique /Times-Roman /Times-Bold /Times-Italic /Times-BoldItalic /Symbol /ZapfDingbats /Arial]>> setdistillerparams"`

  eval "gs                        \
    -f \"$source\"                \
    -o \"$dest\"                  \
    -dPDFSETTINGS=/screen         \
    -dDownsampleColorImages=true  \
    -dDownsampleGrayImages=true   \
    -dDownsampleMonoImages=true   \
    -dColorImageResolution=72     \
    -dGrayImageResolution=72      \
    -dMonoImageResolution=72      \
    -dConvertCMYKImagesToRGB=true \
    -dDetectDuplicateImages=true  \
    -dEmbedAllFonts=false         \
    -dSubsetFonts=true            \
    -dCompressFonts=true          \
    -c \".setpdfwrite <</AlwaysEmbed [ ]>> setdistillerparams\" \
    -c \".setpdfwrite <</NeverEmbed [/Courier /Courier-Bold /Courier-Oblique /Courier-BoldOblique /Helvetica /Helvetica-Bold /Helvetica-Oblique /Helvetica-BoldOblique /Times-Roman /Times-Bold /Times-Italic /Times-BoldItalic /Symbol /ZapfDingbats /Arial]>> setdistillerparams\"" >/dev/null

}

# Given a manifest of docs, optimize them all and report progress as each is completed
_optimize_docs(){
  local lines="$1"

  _start_progress_indicator "doc" "Document Processing" "$todo_doc_file_count"

  while read line ; do
    while IFS='|' read -ra var ; do
      local source="${var[0]}"
      local original_size="${var[1]}"
      # @todo - Support backups... currently overwriting the orginal
      local dest="$source"
      _optimize_doc "$source" "$dest"

      _find_docs "$dest"
      local new_file="$result"
      local reduction=0
      if [[ "$new_file" != "$line" ]] ; then
        # Yes, the file was optimized, but by how much exactly?
        while IFS='|' read -ra var ; do
          # Escape spaces so that image_optim can take the file names as they are in bulk
          local new_size="${var[1]}"
        done <<< "$new_file"
        let reduction=$original_size-$new_size
        let bytes_optimized=$bytes_optimized+$reduction
      fi

      # Flatten this single manifest entry (remove absolute path)
      _flaten_manifest "$new_file"
      local flat_manifest_entry="$result"
      _append_manifest "doc" "$flat_manifest_entry"

      # Add the amount of reduction to the file at the end also, and save to the reduction manifest as a log of what was done
      if [[ $reduction > 0 ]] ; then
        _append_manifest "doc_reduction" "$flat_manifest_entry|$reduction"
      fi

    done <<< "$line"

    _start_progress_indicator "doc" "Document Processing" "$todo_doc_file_count"
  done <<< "$lines"
}

# Reads N lines from input, keeping further lines in the input.
#
# Arguments:
#   $1: number N of lines to read.
#
# Return code:
#   0 if at least one line was read.
#   1 if input is empty.
#
_batch() {
  local chunk_size="$1"
  local result="1"
  local line

  # Read at most N lines
  for i in $(seq 1 $chunk_size) ; do
    # Try reading a single line
    read line
    if [ $? -eq 0 ] ; then
      # Output line
      echo $line
      result="0"
    else
      break
    fi
  done

  # Return 1 if no lines where read
  return $result
}


################################################################################
# Initializing the script
################################################################################

# Global settings
set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace

# Define constants
BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Assign defaults for parameters
param_help=false
param_path=$(pwd)
param_file=false
param_image=true
param_image_lossy=true
param_image_lossy_quality=85
param_image_max_size=true
param_image_max_width=3840
param_image_max_height=2160
param_image_metadata=false
param_video=true
param_video_quality=20
param_video_max_width=1920
param_video_max_height=1080
param_doc=true
param_manifest=true
param_manifest_name=.optim
param_silent=false
param_dependency_check=true

# Define the params we will allow
allowed_params="h|?|help p|path f|file i|image image-lossy image-lossy-quality image-max-size image-max-width image-max-height image-metadata v|video video-quality video-max-width video-max-height p|doc m|manifest s|silent d|dependency-check"

# Get the params from arguments provided
_get_params $*

################################################################################
# Internal globals
################################################################################

# Number of bytes processed (not necessarily reduced)
bytes_processed=0

# Total reduction in this session in bytes
bytes_optimized=0

# Total number of bytes in the workload
bytes_total=0

# Will optimize multiple images at a time, to take advantage of multiple processors.
file_batch_count=8

################################################################################
# Optional actions
################################################################################

# Open help if desired
if _bool "$param_help" ; then
  _help
fi

# Check dependencies if desired
if _bool "$param_dependency_check" ; then

  # Ruby
  if [ -z "$(which ruby)" ] ; then
    if [ -z "$(which brew)" ] ; then
      _die "Ruby is needed, but so is Homebrew. Please install one of them manually."
    else
      echo "Ruby is needed. Installing..."
      brew install ruby
    fi
  fi

  # Homebrew
  if [ -z "$(which brew)" ] ; then
    if [ -z "$(which ruby)" ] ; then
      _die "Homebrew is needed, but so is Ruby. Please install one of them manually."
    else
      echo "Homebrew is needed. Installing..."
      ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi
  fi

  # Image Optim
  if [ -z "$(which image_optim)" ] ; then
    echo "Image Optim is needed. Installing..."
    gem install image_optim image_optim_pack
  fi

  # svgo
  # if [ -z "$(which svgo)" ] ; then
  #   echo "SVGO is needed. Installing..."
  #   echo "Your password may be required to install svgo."
  #   sudo npm install -g svgo
  # fi

  if [ -z "$(which pngout)" ] ; then
    echo "PNGout is needed. Installing..."
    cd /tmp
    curl -O -s http://static.jonof.id.au/dl/kenutils/pngout-20150319-darwin.tar.gz
    tar zxf pngout-20150319-darwin.tar.gz
    cd pngout-20150319-darwin
    echo "Your password may be required to install pngout."
    sudo cp pngout /usr/bin/
    sudo chmod +x /usr/bin/pngout
    sudo rm -Rf /tmp/pngout-*
  fi

  # Handbrake CLI
  if [ -z "$(which handbrakecli)" ] ; then
    echo "Handbrake CLI is needed. Installing..."
    brew install caskroom/cask/brew-cask
    brew cask install handbrakecli
  fi

  # Ghostscript
  if [ -z "$(which gs)" ] ; then
    echo "Ghostscript is needed. Installing..."
    brew install ghostscript
  fi

  # PV
  if [ -z "$(which pv)" ] ; then
    echo "Pipe Viewer (pv) is needed. Installing..."
    brew install pv
  fi
else
  echo "Skipping dependency checks"
fi

################################################################################
# Loading manifests
################################################################################

# Globals for manifest counts
old_image_file_count=0
old_video_file_count=0
old_doc_file_count=0
old_total_file_count=0
new_image_file_count=0
new_video_file_count=0
new_doc_file_count=0
new_total_file_count=0

# Load manifests (if able)
if _bool "$param_manifest" ; then
  _load_manifest
fi

# Generate new manifests (file lists and counts)
# This is needed even if we are not saving the manifest
_generate_manifest

# Find differences (new/altered files)
# This is needed even if we are not using existing manifests
_diff_manifest

# Estimate work (new/altered files) @todo - use stats for end-result screen
# _estimate_work

################################################################################
# Begin optimizations
################################################################################

# @todo - Downscale excessively large images based on $param_image_max_size, param_image_max_width and param_image_max_height

# Optimize Images
if _bool "$param_image" ; then
  # Batch throught a group of no more than 8 images simultaniously
  _optimize_image_batch "$diff_image_manifest"
fi

# Optimize Videos
if _bool "$param_video" ; then
  # Optimize videos one at a time (handbrake uses available processors)
  _optimize_videos "$diff_video_manifest"
fi

# Optimize Documents
if _bool "$param_doc" ; then
  # Optimize docs one at a time (not currently parallelizable)
  _optimize_docs "$diff_doc_manifest"
fi

echo "Complete."
