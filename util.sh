#!/bin/sh -e

# Provides high-level functions for writing external scripts, such as fzf launchers.

die()
{
  printf '%s: error: %s\n' "${0##*/}" "$*" >&2
  exit 1
}

assertIsValidVM()
(
  vm_name="$1"

  test -n "$1" || die "no vm name specified"
  test -e "$1" || die "unknown vm: '$vm_name'"
)

sanitizeFind0Output()
(
  tr -d '\n' | tr '\0' '\n' | ansifilter
)

dumpFile()
(
  filepath="$1"

  test ! -e "$filepath" || cat "$filepath"
)

cmd="$1"
vm_name="$2" # only mandatory for some commands

cd "$(dirname "$0")/vm-configs/"
vm_data_mountpoint="/vm-data"
case "$cmd" in
  listConfiguredVMs) printf '%s\n' *;;
  listRunnableCommands)
    assertIsValidVM "$vm_name"
    dumpFile "$vm_name/packages"
    if test -e "$vm_data_mountpoint/$vm_name/home/.local/bin"; then
      find "$vm_data_mountpoint/$vm_name/home/.local/bin" -type f -print0 |
        sanitizeFind0Output | grep -oE '[^/]+$' || true
    fi
    # List default apps
    printf '%s\n' xterm
    ;;
  listFlatpaks)
    assertIsValidVM "$vm_name"
    dumpFile "$vm_name/flatpaks"
    ;;
  getHomedir)
    assertIsValidVM "$vm_name"
    printf '%s/%s/home\n' "$vm_data_mountpoint" "$vm_name"
    ;;
  *) die "invalid command provided: '$cmd'";;
esac
