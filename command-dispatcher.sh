#!/bin/sh -e

# Low-level server and client for dispatching commands to vms.
#   ./command-dispatcher.sh server
#   ./command-dispatcher.sh run MY_VM firefox --some-argument
#
# See run-in-vm.sh for a high-level wrapper.

die()
{
  printf "%s: error: %s\n" "${0##*/}" "$*" >&2
  exit 1
}

announce()
(
  printf '\033[1;35m%s\033[0m\n' "$*"
)

cleanupVmConnection()
(
  vm_name="$1"
  state_dir="$2"

  announce "Disconnecting from vm $vm_name..."
  xargs -n 1 pidwait -s < "$state_dir/$vm_name/pid" &
  xargs -n 1 pkill -s < "$state_dir/$vm_name/pid"
  wait
  announce "Disconnected from vm $vm_name"

  rm -vrf "${state_dir:?}/${vm_name:?}"
)

vmConnection()
(
  vm_name="$1"
  state_dir="$2"

  virsh dumpxml --inactive "$vm_name" |
    grep -qF '<description>CUSTOM_AUTOSTART=' || return 0

  mkdir "$state_dir/$vm_name" || die "vm connection already exists: $vm_name"
  trap 'cleanupVmConnection "$vm_name" "$state_dir"' EXIT

  announce "Connecting to vm $vm_name..."
  setsid sh -e 2>&1 <<EOF
  printf '%s\n' "\$\$" > '$state_dir/$vm_name/pid'
  nc -lkU '$state_dir/$vm_name/socket' </dev/null 2>/dev/null |
    script -f -c "virsh console --force '$vm_name' >/dev/null" /dev/null 2>&1 |
    ansifilter
EOF
)

cleanupServer()
(
  state_dir="$1"

  announce 'Stopping all dispatched connections...'
  find "$state_dir" -type f -name 'pid' -print0 | xargs -0 -r cat | xargs -r kill

  announce 'Waiting for connections to terminate...'
  while find "$state_dir" -type f -name 'pid' | grep -q .; do
    sleep 0.1
  done
  announce 'All connections terminated'

  rm -vrf "${state_dir:?}"
)

server()
(
  state_dir="$1"

  mkdir -m 700 "$state_dir" || die "already running"
  trap 'cleanupServer "$state_dir"' EXIT

  virsh list --name |
    grep . |
    while read -r vm_name; do
      vmConnection "$vm_name" "$state_dir" &
    done

  announce 'Watching for vm lifecycle events...'
  virsh event --event lifecycle --loop |
    stdbuf -o 0 grep -E '(Started Booted|Stopped (Shutdown|Destroyed))' |
    stdbuf -o 0 sed -r "s,^.* for domain '([^']+)': ([^\s]+) .*$,\2 \1," |
    while read -r event vm_name; do
      case "$event" in
        Started) vmConnection "$vm_name" "$state_dir" &;;
        Stopped)
          test ! -e "$state_dir/$vm_name/pid" ||
            xargs kill < "$state_dir/$vm_name/pid"
          ;;
        *) die "unknown vm lifecycle event: $event";;
      esac
    done
)

client()
(
  state_dir="$1"
  vm_name="$2"
  shift 2

  test -n "$vm_name" || die 'no vm name specified'
  test -n "$*" || die 'no command specified'
  test -e "$state_dir/$vm_name/socket" || die "dispatcher is not connected to vm $vm_name"

  escaped_command=$(/usr/bin/printf '%q ' "$@")
  printf '%s >/dev/null 2>&1 &\n' "$escaped_command" |
    nc -NU "$state_dir/$vm_name/socket" >/dev/null

  # Check is done after command to improve latency.
  virsh list --name | grep -qxF "$vm_name" || {
    printf 'error: vm "%s" not reachable, cleaning up server state...\n' "$vm_name"
    xargs -n 1 pidwait -s < "$state_dir/$vm_name/pid" &
    xargs kill < "$state_dir/$vm_name/pid"
    wait
    exit 1
  } >&2
)

export LIBVIRT_DEFAULT_URI='qemu:///system'
state_dir="$XDG_RUNTIME_DIR/vm-command-dispatcher"

case "$1" in
  server) server "$state_dir";;
  isServerRunning) test -e "$state_dir";;
  run)
    shift
    client "$state_dir" "$@";;
  *)
    {
      self_name="${0##*/}"
      printf "%s: error: %s\n" "$self_name" "invalid command line arguments provided"
      printf '\n'
      printf 'Example usage:\n'
      printf '  %s server\n' "$self_name"
      printf '  %s run MY_VM firefox --some-argument\n' "$self_name"
      exit 1
    } >&2;;
esac
