#!/bin/sh -e

logfile="$HOME/.local/state/update-logs/$(date +'%Y-%m-%d-%H:%M:%S').log"
mkdir -p "$(dirname "$logfile")"
trap 'test $? = 0 || \
  notify-send -u critical -t 0 "System update failed" "More details can be found in $logfile"' EXIT

{
  doas /sbin/apk upgrade -U
  if command -v flatpak >/dev/null; then
    flatpak --user update -y --noninteractive
  fi
} > "$logfile" 2>&1
