#!/bin/sh

# setxkbmap YOUR_LAYOUT_HERE
spice-vdagent
if command -v pulseaudio >/dev/null; then
  pulseaudio --start --exit-idle-time=-1 &
fi
tint2 &

udevadm monitor -u -s drm |
stdbuf -o 0 grep -o change |
xargs -n 1 -I {} xrandr --output Virtual-1 --auto &
