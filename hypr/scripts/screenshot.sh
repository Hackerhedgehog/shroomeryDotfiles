sh -c 'file=~/Pictures/Screenshots/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png && grimblast save area "$file" && wl-copy -t image/png < "$file"'
