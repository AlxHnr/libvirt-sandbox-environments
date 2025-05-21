#!/bin/sh -e

sync-guest-with-host.sh &

udevadm monitor -u -s drm |
stdbuf -o 0 grep -m 1 change |
xargs -I {} kscreen-doctor output.Virtual-1.mode.1 output.Virtual-1.scale.1.2 &

wbg /usr/local/share/wallpapers/generated.svg &
xargs -I {} < /tmp/host-serial-output sh -c 'exec {} >/dev/null 2>&1 &' &
