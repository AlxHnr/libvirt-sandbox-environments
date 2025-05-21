#!/bin/sh -e

sync-guest-with-host.sh &
(
  sleep 2.5
  kscreen-doctor output.Virtual-1.mode.1 output.Virtual-1.scale.1.2
) &
wbg /usr/local/share/wallpapers/generated.svg &
xargs -I {} < /tmp/host-serial-output sh -c 'exec {} >/dev/null 2>&1 &' &
