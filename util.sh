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

dumpFile()
(
  filepath="$1"

  test ! -e "$filepath" || cat "$filepath"
)

path_to_vm_configs="$1"
cmd="$2"
vm_name="$3" # only mandatory for some commands

cd "$path_to_vm_configs"
vm_data_mountpoint="/vm-data"
case "$cmd" in
  listConfiguredVMs) printf '%s\n' *;;
  listRunnableCommands)
    assertIsValidVM "$vm_name"
    dumpFile "$vm_name/packages" | sed -r 's/@[^ \t\r\n\v\f]+$//'
    dumpFile "$vm_name/custom-commands"
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
