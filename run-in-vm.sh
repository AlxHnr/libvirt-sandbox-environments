#!/bin/sh -e

# High-level script which combines `virsh start`, virt-viewer and command-dispatcher.sh.
#   ./run-in-vm.sh MY_VM firefox --some-argument
#   ./run-in-vm.sh MY_VM --no-virt-viewer firefox --some-argument

die()
{
  printf '%s: error: %s\n' "${0##*/}" "$*" >&2
  exit 1
}

cd "$(dirname "$0")"
export LIBVIRT_DEFAULT_URI='qemu:///system'

vm_name="$1"
test -n "$vm_name" || die 'no vm name specified'
shift
test "$1" = '--no-virt-viewer' && virt_viewer='false' && shift || virt_viewer='true'
test -n "$*" || die 'no command specified'

hotkeys='toggle-fullscreen=,release-cursor=,zoom-in=,zoom-out=,zoom-reset=,secure-attention='
hotkeys="$hotkeys,usb-device-reset=,smartcard-insert=,smartcard-remove="
virt_viewer_cmd=$(/usr/bin/printf 'virt-viewer --attach %q --wait -H %s\n' "$vm_name" "$hotkeys")
test "$virt_viewer" = 'false' || pgrep -fx "$virt_viewer_cmd" >/dev/null || {
  $virt_viewer_cmd || true
  ./command-dispatcher.sh run "$vm_name" \
    sh -c 'wmctrl -l | grep -oE "^[[:alnum:]]+" | xargs -n 1 wmctrl -i -c'
} >/dev/null 2>&1 &

if ./command-dispatcher.sh run "$vm_name" "$@" >/dev/null 2>&1; then
  exit
fi

# Ensure vm + dispatch server are running and try again
if ! ./command-dispatcher.sh isServerRunning; then
  dispatcher_logfile="$HOME/.local/state/vm-command-dispatcher/$(date +'%Y-%m-%d-%H:%M:%S').log"
  mkdir -p "$(dirname "$dispatcher_logfile")"
  printf 'launching server, see %s\n' "$dispatcher_logfile"
  ./command-dispatcher.sh server > "$dispatcher_logfile" 2>&1 &
  sleep 0.5
fi

if ! virsh domstate "$vm_name" | grep -qxF 'running'; then
  printf 'starting vm %s..\n' "$vm_name"
  virsh start "$vm_name"
  sleep 5
fi

./command-dispatcher.sh run "$vm_name" "$@"
