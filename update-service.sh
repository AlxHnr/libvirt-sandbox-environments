#!/bin/sh -e

# Service which updates every running vm exactly once. VMs which are not running are updated later
# when they start. Metered connections are respected.

die()
{
  printf '%s: error: %s\n' "${0##*/}" "$*" >&2
  exit 1
}

getDbusNetworkProperty()
(
  property_name="$1"

  busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager \
    org.freedesktop.NetworkManager "$property_name"
)

canDownload()
(
  getDbusNetworkProperty Connectivity | grep -qxF 'u 4' || return 1
  getDbusNetworkProperty Metered | grep -qxE '^u [24]$' || return 1
)

cd "$(dirname "$0")"
export LIBVIRT_DEFAULT_URI='qemu:///system'

state_dir="$XDG_RUNTIME_DIR/vm-update-service"
mkdir -m 700 "$state_dir" || die "already running"
trap 'rm -rf "$state_dir"' EXIT

delay=0
while true; do
  sleep "$delay"
  delay=600

  canDownload || continue

  virsh list --name | grep . |
    while read -r vm_name; do
      grep -qxF 'internet' "./vm-configs/$vm_name/config" || continue
      test ! -e "$state_dir/$vm_name" || continue
      virsh dumpxml --inactive "$vm_name" |
        grep -qF '<description>CUSTOM_AUTOSTART=' || continue

      printf 'Sending update command to vm %s\n' "$vm_name"
      # The following command may get ignored if the target vm is still booting or shutting down.
      # Assuming this script gets used once every day, this is unlikely to become a problem.
      ./run-in-vm.sh "$vm_name" --no-virt-viewer update-system.sh

      touch "$state_dir/$vm_name"
    done
done
