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

(
  sleep 5
  for device in Master PCM Capture; do
    amixer sset "$device" 100% unmute
  done
) &

xargs -I {} < /tmp/host-serial-output sh -c 'exec {} >/dev/null 2>&1 &' &
