#!/usr/bin/env bash
# Render small JPEG previews of every image and video (first frame) in a wallpaper folder for the WallpaperApp grid.
# Layout: $WALLPAPER_THUMBNAILS/md5(FOLDER)/md5("<file name>:<size in bytes>").jpg. FOLDER is hashed
# exactly as given, so the panel (which passes its folder string) can compute the same path.
# Existing previews are skipped; previews of images that were edited, replaced or removed are
# deleted. Usage: wallpaper-thumbnails.sh [FOLDER]
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

folder="${1:-$(wallpaper_folder)}"
if [[ ! -d "$folder" ]]; then
    error "Directory does not exist -> $folder"; exit 1
fi
out_dir="$WALLPAPER_THUMBNAILS/$(printf '%s' "$folder" | md5sum | cut -d' ' -f1)"
mkdir -p "$out_dir"

key() {
    printf '%s:%s' "$(basename "$1")" "$(stat -c %s "$1")" | md5sum | cut -d' ' -f1
}

render() {
    local image="$1" out="$2" tmp ok
    # Written next to the target and renamed, so the panel never reads a half-written file.
    tmp="$(dirname "$out")/.$$.$(basename "$out")"
    case "${image,,}" in
        # Videos and GIFs: their first frame.
        *.mp4 | *.webm | *.mkv | *.mov | *.m4v | *.avi | *.gif)
            ffmpeg -v error -y -i "$image" -frames:v 1 \
                -vf "scale=560:560:force_original_aspect_ratio=increase" -q:v 4 -f mjpeg "$tmp" </dev/null
            ;;
        *)
            magick -define jpeg:size=1120x1120 "$image" -auto-orient -thumbnail '560x560^' \
                -quality 85 "$tmp"
            ;;
    esac
    ok=$?
    if [ "$ok" -eq 0 ] && [ -s "$tmp" ]; then
        mv -f "$tmp" "$out"
    else
        rm -f "$tmp"
        warn "Could not render a thumbnail for $image"
    fi
}
export -f render warn
export YELLOW NC

declare -A wanted=()
todo=()
while IFS= read -r -d '' image; do
    k=$(key "$image")
    wanted["$k.jpg"]=1
    [[ -f "$out_dir/$k.jpg" ]] || todo+=("$image" "$out_dir/$k.jpg")
done < <(find "$folder" -maxdepth 1 -type f \( "${IMAGE_FIND_ARGS[@]}" -o "${ANIMATED_FIND_ARGS[@]}" \) -print0)

if (( ${#todo[@]} > 0 )); then
    printf '%s\0' "${todo[@]}" | xargs -0 -n 2 -P "$(nproc)" bash -c 'render "$1" "$2"' _
fi

# Drop previews no image maps to any more, and leftovers of interrupted renders.
for thumb in "$out_dir"/* "$out_dir"/.*.jpg; do
    [[ -f "$thumb" ]] || continue
    name=$(basename "$thumb")
    [[ -n "${wanted[$name]:-}" ]] || rm -f "$thumb"
done
