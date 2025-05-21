#!/bin/sh -e
# This script wraps `spice-vdagent` and additionally forwards the Xwayland clipboard to wayland.
# Spice-vdagent is also required to forward the hosts VM window size to the guest.

syncClipboards()
(
  source_command="$1"
  target_command="$2"

  last_content=''
  while read -r _; do
    content=$($source_command || continue)
    test "$content" != "$last_content" || continue
    last_content="$content"
    $source_command | $target_command
  done
)

trap exit INT TERM
trap 'kill 0' EXIT
wl-paste    --watch echo | syncClipboards 'wl-paste -n'  'xsel -ib' &
wl-paste -p --watch echo | syncClipboards 'wl-paste -np' 'xsel -ip' &
spice-vdagent -d -x 2>&1 | stdbuf -o0 grep 'received clipboard grab, arg1: 1' |
  syncClipboards 'xsel -op' 'wl-copy -p' &
wait
