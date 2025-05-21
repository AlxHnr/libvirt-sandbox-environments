#!/bin/sh -e

sync-guest-with-host.sh &
wbg /usr/local/share/wallpapers/generated.svg &

udevadm monitor -u -s drm |
stdbuf -o 0 grep -m 1 change |
xargs -I {} kscreen-doctor output.Virtual-1.mode.1 output.Virtual-1.scale.1.2 &

test ! -e /usr/libexec/pipewire-launcher || /usr/libexec/pipewire-launcher
(
  sleep 5
  for device in Master PCM Capture; do
    amixer sset "$device" 100% unmute
  done
) &

xargs -I {} < /tmp/host-serial-output sh -c 'exec {} >/dev/null 2>&1 &' &
