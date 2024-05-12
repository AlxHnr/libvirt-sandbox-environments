#!/bin/sh -e

SETUP_VM_TMPDIR=$(mktemp -dt 'setup-vm-tmpdir-XXXXXXXX')
trap 'rm -rf "$SETUP_VM_TMPDIR"' EXIT

die()
{
  printf "%s: error: %s\n" "${0##*/}" "$*" >&2
  exit 1
}

runInPTYRaw()
(
  command="$1"

  trap 'rm "$SETUP_VM_TMPDIR/serial-out.txt"' EXIT
  # The cat is required to make this function wrappable
  cat | script -q -f -c "$command" "$SETUP_VM_TMPDIR/serial-out.txt" | ansifilter

  exit_code=$(ansifilter "$SETUP_VM_TMPDIR/serial-out.txt" |
    grep -oE '^COMMAND_EXIT_STATUS=([^;]+); ' |
    tail -n 1 |
    grep -oE '[0-9]+' || echo 0)
  return "$exit_code"
)

runInPTY()
(
  command="$1"

  {
    while ! grep -qE "^Connected to domain '" "$SETUP_VM_TMPDIR/serial-out.txt" 2>/dev/null; do
      sleep 0.1
    done
    cat
    printf '\035'
  } | runInPTYRaw "$command"
)

waitFor()
(
  regex="$1"

  # This supports matching partial/incomplete lines
  while ! tail -n 1 "$SETUP_VM_TMPDIR/serial-out.txt" 2>/dev/null |
    ansifilter | grep -qE "$regex"; do
    sleep 0.1
  done
)

sendCommand()
(
  command="$*"

  printf '%s\n' "$command"
  waitFor '^localhost:~[$#] $'

  printf 'printf "COMMAND_EXIT_STATUS=$?; "\n' # No nested newline
  waitFor '^COMMAND_EXIT_STATUS=[0-9]+; localhost:~[$#] $'

  exit_code=$(tail -n 1 "$SETUP_VM_TMPDIR/serial-out.txt" | ansifilter |
    sed -r 's,^COMMAND_EXIT_STATUS=([^;]+); .*$,\1,')
  return "$exit_code"
)

waitAndLogin()
(
  printf '\n'
  waitFor '^localhost'

  tail -n 1 "$SETUP_VM_TMPDIR/serial-out.txt" |
    ansifilter |
    grep -qvE '^localhost login: $' ||
    sendCommand 'root'
)

writeFile()
(
  filename="$1"

  /usr/bin/printf "{ base64 -d | gzip -d;} > %q <<'EOF_SETUP_SCRIPT'\n" "$filename"
  waitFor '^> $'
  gzip -9 | base64
  sendCommand 'EOF_SETUP_SCRIPT'
)

vmExists()
(
  vm_name="$1"

  virsh list --all --name | grep -qxF "$vm_name"
)

escapeAndJoin()
(
  xargs -d '\n' -r printf '%q '
  printf '\n'
)

parseLine()
(
  line="$1"
  validation_regex="$2"
  config_path="$3"

  printf '%s\n' "$line" |
    grep -qE "$validation_regex" ||
    die "invalid value in $config_path: \"$line\""

  printf '%s\n' "${line#*=}"
)

assertConfigFlagSet()
(
  flag="$1"
  value="$2"
  config_path="$3"

  test -n "$value" || die "flag missing in $config_path: \"$flag\""
)

getUsbClassCodes()
(
  device_type="$1"

  case "$device_type" in
    android) printf '0x06\n0xFF\n';; # Devices don't work yet.
    printer) printf '0x07\n0xFF\n';;
    webcam) printf '0x0E\n0x01\n';; # Most webcams are coupled to a microphone.
    HID) printf '0x03\n';; # Human interface devices e.g. drawing tablets.
    *) die "unknown usb device in config: \"$device_type\"";;
  esac
)
getUsbDeviceType()
(
  class_code="$1"

  case "$class_code" in
    0x06) printf 'android\n';;
    0x07) printf 'printer\n';;
    0x0E) printf 'webcam\n';;
    0x03) printf 'HID\n';;
    0xFF|0x01);; # Supplemental class codes used together with others.
    *) die "unknown redirfilter usbdev class code: \"$class_code\"";;
  esac
)

# Parse the config file of the specified vm and populate variables in the callers environment.
# Variables starting with `cfg_` reflect the state of the config file, while variables starting
# with `vm_` represent the current vm state.
#
# A special variable called `vm_cfg_deviations` is populated with all flags which deviate from
# their configured values. E.g. "cores memory clipboard".
populateVMVariables()
{
  # Don't pollute callers env too much
  # vm_name="$1"
  # config_path="$2"

  unset cfg_color cfg_memory cfg_cores cfg_disksize
  cfg_expose_homedir='false'
  cfg_clipboard='false'
  cfg_sound='false'
  cfg_microphone='false'
  cfg_gpu='false'
  cfg_internet='false'
  cfg_root_tty2='false'
  cfg_kiosk='false'
  cfg_autostart='false'
  cfg_printer='false'
  cfg_usb=''

  # shellcheck disable=SC2094
  while read -r line; do
    case "$line" in
      color=*) cfg_color=$(parseLine "$line" '^color=[A-Fa-f0-9]{6}$' "$2");;
      memory=*) cfg_memory=$(parseLine "$line" '^memory=[1-9]+[0-9]*$' "$2");;
      cores=*)
        cfg_cores=$(parseLine "$line" '^cores=([1-9]+[0-9]*|ALL)$' "$2" |
          sed -r "s,ALL,$(nproc)," | grep .)
        ;;
      disksize=*) cfg_disksize=$(parseLine "$line" '^disksize=[1-9]+[0-9]*$' "$2");;
      expose_homedir) cfg_expose_homedir='true';;
      clipboard) cfg_clipboard='true';;
      sound) cfg_sound='true';;
      sound+microphone) cfg_sound='true' cfg_microphone='true';;
      gpu) cfg_gpu='true';;
      internet) cfg_internet='true';;
      root_tty2) cfg_root_tty2='true';;
      kiosk) cfg_kiosk='true';;
      autostart) cfg_autostart='true';;
      printer) cfg_printer='true';;
      usb=*)
        test -z "$cfg_usb" || die "redefinition of usb device list in $2: \"$line\""
        value=$(parseLine "$line" '^usb=(,?[[:alnum:]]+)+$' "$2")
        devices=$(printf '%s\n' "$value" | tr ',' '\n' | sort -u)
        for device in $devices; do
          getUsbClassCodes "$device" >/dev/null
          cfg_usb="$cfg_usb $device"
        done;;
      *) die "invalid line in $2: \"$line\"";;
    esac
  done < "$2"

  assertConfigFlagSet color "$cfg_color" "$2"
  assertConfigFlagSet memory "$cfg_memory" "$2"
  assertConfigFlagSet cores "$cfg_cores" "$2"
  assertConfigFlagSet disksize "$cfg_disksize" "$2"

  xml=$(virsh dumpxml --inactive "$1" 2>/dev/null || printf '')

  if test -z "$xml"; then
    vm_color='NULL'
    vm_cores='NULL'
    vm_memory='NULL'
    vm_disksize='NULL'
    vm_expose_homedir='NULL'
    vm_clipboard='NULL'
    vm_sound='NULL'
    vm_microphone='NULL'
    vm_gpu='NULL'
    vm_internet='NULL'
    vm_root_tty2='NULL'
    vm_kiosk='NULL'
    vm_autostart='NULL'
    vm_printer='NULL'
    vm_usb='NULL'
  else
    # Values too expensive to retrieve
    # shellcheck disable=SC2034
    {
      vm_color='??????'
      vm_root_tty2='??????'
      vm_kiosk='??????'
      vm_printer='??????'
    }

    vm_cores=$(printf '%s\n' "$xml" | grep -m1 '<vcpu placement\>' | grep -oE '[0-9]+')
    vm_memory=$(printf '%s\n' "$xml" | grep -m1 '<currentMemory\>' | grep -oE '[0-9]+' |
      xargs printf '%s / 1024\n' | bc)
    vm_disksize=$(virsh domblkinfo --human "$1" vda 2>&1 | grep '^Capacity' | grep -oE ' [0-9]+' |
      grep -oE '\S+' || printf '??????\n')
    printf '%s\n' "$xml" | grep -q 'homedir_mount_tag' &&
      vm_expose_homedir='true' || vm_expose_homedir='false'
    printf '%s\n' "$xml" | grep -qE '<clipboard copypaste=.\<no\>' &&
      vm_clipboard='false' || vm_clipboard='true'
    if printf '%s\n' "$xml" | grep -qE '<sound model\>'; then
      vm_sound='true'
      printf '%s\n' "$xml" | grep -qE '<codec type=.\<output\>' &&
        vm_microphone='false' || vm_microphone='true'
    else
      vm_sound='false'
      vm_microphone='false'
    fi
    printf '%s\n' "$xml" | grep -qE '<gl enable=.\<yes\>' &&
      vm_gpu='true' || vm_gpu='false'
    printf '%s\n' "$xml" | grep -qE '<interface\>' &&
      vm_internet='true' || vm_internet='false'
    virsh list --all --autostart --name | grep -qxF "$1" &&
      vm_autostart='true' || vm_autostart='false'

    usb_classes=$(printf '%s\n' "$xml" | grep -E '<usbdev\>.*\<allow=.\<yes\>' |
      sed -r 's,^.*class=.(0x..).*$,\1,')
    device_types=''
    for class in $usb_classes; do
      device_types="$device_types $(getUsbDeviceType "$class")"
    done
    device_types=$(for device in $device_types; do printf '%s\n' "$device"; done | sort -u)
    for device_type in $device_types; do
      vm_usb="$vm_usb $device_type"
    done
  fi
  unset xml

  unset deviations
  test "$vm_cores" = "$cfg_cores" || deviations='cores'
  test "$vm_memory" = "$cfg_memory" || deviations="$deviations memory"
  if test "$vm_disksize" != "$cfg_disksize" && test "$vm_disksize" != '??????'; then
    deviations="$deviations disksize"
  fi
  test "$vm_expose_homedir" = "$cfg_expose_homedir" || deviations="$deviations expose_homedir"
  test "$vm_clipboard" = "$cfg_clipboard" || deviations="$deviations clipboard"
  # Microphone must come after sound
  test "$vm_sound" = "$cfg_sound" || deviations="$deviations sound"
  test "$vm_microphone" = "$cfg_microphone" || deviations="$deviations microphone"
  test "$vm_gpu" = "$cfg_gpu" || deviations="$deviations gpu"
  test "$vm_internet" = "$cfg_internet" || deviations="$deviations internet"
  test "$vm_autostart" = "$cfg_autostart" || deviations="$deviations autostart"
  test "$vm_usb" = "$cfg_usb" || deviations="$deviations usb"
  vm_cfg_deviations="$deviations"
  unset deviations
}

reapplyConfigFlags()
(
  vm_name="$1"
  vm_config_path="$2"

  populateVMVariables "$vm_name" "$vm_config_path"

  for flag in $vm_cfg_deviations; do
    printf 'updating vm %s: flag \"%s\" has changed\n' "$vm_name" "$flag"
    case "$flag" in
      cores) virt-xml "$vm_name" --edit --vcpus "$cfg_cores";;
      memory) virt-xml "$vm_name" --edit --memory "memory=$cfg_memory,maxmemory=$cfg_memory";;
      disksize)
        printf 'ignoring changed config flag \"disksize\" in %s\n' "$vm_config_path" >&2
        ;;
      expose_homedir)
        printf 'ignoring changed config flag \"expose_homedir\" in %s\n' "$vm_config_path" >&2
        ;;
      clipboard)
        test "$cfg_clipboard" = 'true' && clipboard_arg='yes' || clipboard_arg='no'
        virt-xml "$vm_name" --edit --graphics "clipboard.copypaste=$clipboard_arg"
        ;;
      sound)
        if test "$cfg_sound" = 'true'; then
          virt-xml "$vm_name" --add-device --sound 'model=ich9,codec.type=output'
        else
          virt-xml "$vm_name" --remove-device --sound all
        fi
        ;;
      microphone)
        if test "$cfg_microphone" = 'true'; then
          codec='duplex'
          backend='type=pulseaudio,xpath.set=./@serverName=unix:/tmp/qemu-pulse-native'
        else
          codec='output'
          backend='type=spice'
        fi
        test "$cfg_sound" != 'true' || virt-xml "$vm_name" --edit --sound "codec.type=$codec"
        virt-xml "$vm_name" --edit --audio "clearxml=yes,id=1,$backend"
        ;;
      gpu)
        if test "$cfg_gpu" = 'true'; then
          virt-xml "$vm_name" --edit --video \
            'clearxml=yes,model.type=virtio,model.acceleration.accel3d=yes'
          virt-xml "$vm_name" --edit --graphics 'gl.enable=yes'
        else
          virt-xml "$vm_name" --edit --graphics 'gl.enable=no'
          # The following constants are duplicated in `makeVirtInstallCommand()`.
          virt-xml "$vm_name" --edit --video \
            'clearxml=yes,model.type=qxl,model.ram=262144,model.vram=262144,model.vgamem=32768'
        fi
        ;;
      internet)
        if test "$cfg_internet" = 'true'; then
          virt-xml "$vm_name" --add-device --network 'network=default,model.type=virtio'
        else
          virt-xml "$vm_name" --remove-device --network all
        fi
        ;;
      autostart)
        if test "$cfg_autostart" = 'true'; then
          virsh autostart "$vm_name"
        else
          virsh autostart --disable "$vm_name"
        fi
        ;;
      usb)
        # There is no high-level virt-xml equivalent at the time of writing.
        EDITOR='sed -ri "/<\/?(redirfilter|usbdev)\>/d"' virsh edit "$vm_name"
        virt-xml "$vm_name" --remove-device --redirdev all

        if test -n "$cfg_usb"; then
          for _ in $(seq 4); do
            virt-xml "$vm_name" --add-device --redirdev 'bus=usb,type=spicevmc'
          done
          class_codes=$(for device in $cfg_usb; do getUsbClassCodes "$device"; done | sort -u)
          allow_rules=$(for class_code in $class_codes; do
              printf '<usbdev class="%s" allow="yes"/>' "$class_code"
            done)
          redirfilter="<redirfilter>$allow_rules<usbdev allow=\"no\"/></redirfilter>"
          EDITOR="sed -ri 's|(</devices>)|$redirfilter\1|'" virsh edit "$vm_name"
        fi
        ;;
      *) die "unable to handle change of config flag \"$flag\" in $vm_config_path";;
    esac
  done
)

ensureIsoExists()
(
  alpine_version="$1"
  path_to_iso="$2"

  path_to_iso_signature="$path_to_iso.asc"
  for file in "$path_to_iso" "$path_to_iso_signature"; do
    url="https://dl-cdn.alpinelinux.org/alpine/v${alpine_version%.*}/releases/x86_64/$(basename "$file")"
    test -f "$file" || {
      printf 'Downloading %s...\n' "$file"
      curl -fsS "$url" -o "$file"
    }
  done

  gpg --homedir ./gnupg/ --no-permission-warning --verify "$path_to_iso_signature" "$path_to_iso"
)

setupUserHomedir()
(
  path_to_homedir="$1"
  config_color="$2"
  config_kiosk="$3"

  writeFile "$path_to_homedir/.profile" < ./files/profile
  writeFile "$path_to_homedir/.xinitrc" < ./files/xinitrc
  writeFile "$path_to_homedir/.Xresources" < ./files/Xresources

  sendCommand "mkdir -p '$path_to_homedir/.config/openbox/'"
  {
    cat ./files/openbox-autostart.sh
    printf '\n'
    printf 'xsetroot -solid "#%s"\n' "$config_color"
  } | writeFile "$path_to_homedir/.config/openbox/autostart.sh"
  sendCommand "chmod +x '$path_to_homedir/.config/openbox/autostart.sh'"

  {
    cat ./files/openbox-rc.xml

    test "$config_kiosk" != true || cat <<'EOF'

  <application type="normal">
    <decor>no</decor>
    <maximized>true</maximized>
  </application>
EOF

    cat <<'EOF'

</applications>
</openbox_config>
EOF
  } | writeFile "$path_to_homedir/.config/openbox/rc.xml"

  sendCommand "mkdir -p '$path_to_homedir/.config/tint2/'"
  writeFile "$path_to_homedir/.config/tint2/tint2rc" < ./files/tint2rc
)

setupExposedUserHomedir()
(
  homedir="$1"
  config_color="$2"
  config_kiosk="$3"

  {
    printf 'export HISTFILE=/dev/null PS1="localhost:~$ "\n'
    setupUserHomedir "$homedir" "$config_color" "$config_kiosk"
  } | runInPTYRaw 'sh'
)

makeVirtInstallCommand()
(
  vm_name="$1"
  vm_image="$2"
  disksize="$3"

  /usr/bin/printf 'virt-install \
    --name %q \
    --vcpus 4 \
    --memory 512 \
    --osinfo alpinelinux3.18 \
    --disk size=%s,path=%q,driver.discard=unmap \
    --xml ./devices/graphics/clipboard/@copypaste=no \
    --xml ./devices/graphics/filetransfer/@enable=no \
    --xml ./devices/graphics/listen/@type=none \
    --xml ./devices/graphics/gl/@enable=no \
    --xml ./devices/video/model/@ram=262144 \
    --xml ./devices/video/model/@vram=262144 \
    --xml ./devices/video/model/@vgamem=32768 \
    --xml xpath.delete=./devices/channel/@name=org.qemu.guest_agent.0 \
    --xml xpath.delete=./devices/redirdev \
    --xml xpath.delete=./devices/redirdev \
    --xml xpath.delete=./devices/sound \
    --autoconsole text \
    --noreboot\n' "$vm_name" "$disksize" "$vm_image"
)

setupPrinter()
(
  sendCommand 'apk add cups cups-filters system-config-printer'
  sendCommand 'rc-update add cupsd afterlogin'
  sendCommand 'adduser user lpadmin'
)

setupFlatpak()
(
  flatpack_app_file="$1"

  sendCommand 'apk add --no-progress flatpak pulseaudio'

  # This workaround is needed because some apps have /var/lib/flatpak hard-coded in their code.
  sendCommand 'rm -rf /var/lib/flatpak'
  sendCommand 'ln -s /var/lib/user/flatpak /var/lib/flatpak'

  {
    cat <<'EOF'
export FLATPAK_USER_DIR=/var/lib/user/flatpak
mkdir "$FLATPAK_USER_DIR"
flatpak --user remote-add flathub https://flathub.org/repo/flathub.flatpakrepo
EOF
    xargs -r < "$flatpack_app_file" -d '\n' -n 1 \
      printf 'flatpak --user install -y --noninteractive %q\n'
  } | writeFile /tmp/setup-flatpak.sh

  sendCommand 'runuser --login user -P -c "/bin/sh -e /tmp/setup-flatpak.sh"'
)

setupPip()
(
  pip_package_file="$1"

  sendCommand 'apk add --no-progress py3-pip'
  # shellcheck disable=SC2016
  {
    printf 'mkdir -p "$HOME/.cache/pip3-tmpdir"\n'

    printf 'TMPDIR="$HOME/.cache/pip3-tmpdir" pip3 install'
    printf ' --no-input --no-color --progress-bar off'
    printf ' --cache-dir "$HOME/.cache/pip3-tmpdir"'
    printf ' --target /var/lib/user/pip3-target '
    escapeAndJoin < "$pip_package_file"
    printf 'rm -rf "$HOME/.cache"\n'
  } | writeFile /tmp/setup-pip.sh

  sendCommand 'runuser --login user -P -c "/bin/sh -e /tmp/setup-pip.sh"'
)

setupVM()
(
  vm_name="$1"
  alpine_version="$2"
  alpine_iso="$3"
  vm_data_mountpoint="$4"

  vm_dir="$vm_data_mountpoint/$vm_name"
  vm_image="$vm_dir/image.qcow2"
  vm_config_dir="vm-configs/$vm_name"
  populateVMVariables "$vm_name" "$vm_config_dir/config"

  if vmExists "$vm_name"; then
    die "vm already exists: \"$vm_name\""
  fi
  mkdir -p "$vm_dir"
  rm -vf "$vm_image"

  ensureIsoExists "$alpine_version" "$alpine_iso"
  {
    waitAndLogin

    {
      cat ./files/setup-alpine.cfg
      printf 'APKREPOSOPTS="https://dl-cdn.alpinelinux.org/alpine/v%s/main"\n' \
        "${alpine_version%.*}"
    } | writeFile setup-alpine.cfg

    printf 'setup-alpine -e -f setup-alpine.cfg\n'
    waitFor 'WARNING: Erase the above disk\(s\) and continue\?'
    sendCommand 'y'
    printf 'poweroff\n'
    waitFor '^Script done'
  } | runInPTY "$(makeVirtInstallCommand "$vm_name" "$vm_image" "$cfg_disksize") \
    --location '$alpine_iso' --extra-args 'console=tty0 console=ttyS0,115200'"
  virt-xml "$vm_name" --remove-device --disk device=cdrom

  {
    waitAndLogin

    sendCommand 'setup-xorg-base && echo'
    sendCommand 'echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories'
    sendCommand "apk add --no-progress $(escapeAndJoin < ./files/packages)"
    test ! -e "$vm_config_dir/packages" ||
      sendCommand "apk add --no-progress $(escapeAndJoin < "$vm_config_dir/packages")"

    sendCommand 'rc-update del crond default'
    sendCommand 'rc-update del udev-settle sysinit'
    sendCommand 'mkdir /etc/runlevels/afterlogin'
    sendCommand 'rc-update add -s default afterlogin'
    sendCommand 'rc-update del networking boot'
    sendCommand 'rc-update add networking afterlogin'
    sendCommand 'rc-update add spice-vdagentd afterlogin'
    sendCommand 'echo "rc_parallel=\"YES\"" >> /etc/rc.conf'
    sendCommand 'sed -ri "s,^overwrite=.*$,overwrite=0," /etc/update-extlinux.conf'
    sendCommand 'sed -ri "s,^TIMEOUT .*$,TIMEOUT 1," /boot/extlinux.conf'
    sendCommand 'sed -ri "s,^(user:.*)/ash,\1/bash," /etc/passwd'
    sendCommand 'passwd -l root'
    writeFile /etc/doas.d/doas.conf < ./files/doas.conf
    {
      cat ./files/inittab
      test "$cfg_root_tty2" != 'true' || printf 'tty2::respawn:/bin/login -f root\n'
    } | writeFile /etc/inittab

    writeFile /etc/bash/custom-aliases.sh < ./files/custom-aliases.sh
    writeFile /usr/local/bin/update-system.sh < ./files/update-system.sh
    sendCommand 'chmod +x /usr/local/bin/update-system.sh'

    test "$cfg_printer" != 'true' || setupPrinter

    sendCommand 'mkdir -m 700 /var/lib/user/'
    sendCommand 'chown user:user /var/lib/user/'
    test ! -e "$vm_config_dir/flatpaks" || setupFlatpak "$vm_config_dir/flatpaks"
    test ! -e "$vm_config_dir/pip" || setupPip "$vm_config_dir/pip"

    if test "$cfg_expose_homedir" = 'true'; then
      sendCommand 'echo "homedir_mount_tag /home/user virtiofs rw,relatime 0 0" >> /etc/fstab'
    else
      setupUserHomedir '/home/user' "$cfg_color" "$cfg_kiosk"
      sendCommand 'chown -R user:user /home/user'
    fi
    printf 'rm /root/.ash_history && poweroff\n'
    waitFor '^Script done'
  } | runInPTY "virsh start --console '$vm_name'"
  virt-xml "$vm_name" --remove-device --network all
  virt-xml "$vm_name" --edit --metadata description="SETUP_SUCCEEDED=TRUE"

  test "$cfg_expose_homedir" = 'true' || return 0
  printf 'Attaching "%s/home/" to %s\n' "$vm_dir" "$vm_name"
  virt-xml "$vm_name" --edit --memorybacking 'clearxml=yes,access.mode=shared,source.type=memfd'
  virt-xml "$vm_name" --add-device --filesystem \
    "type=mount,source.dir=$vm_dir/home,target.dir=homedir_mount_tag,driver.type=virtiofs"

  printf 'Initializing "%s/home/"...\n' "$vm_dir"
  mkdir -p "$vm_dir/home"
  setupExposedUserHomedir "$vm_dir/home" "$cfg_color" "$cfg_kiosk"
)

test -z "$SETUP_VMS_SH_DONT_RUN" || return 0

cd "$(dirname "$0")"

alpine_version="3.19.1"
vm_data_mountpoint="/vm-data"
alpine_iso="$vm_data_mountpoint/alpine-standard-$alpine_version-x86_64.iso"
export LIBVIRT_DEFAULT_URI='qemu:///system'

test "$(stat -c %U:%G "$vm_data_mountpoint")" = 'user:qemu' ||
  die "invalid directory owners, expected user:qemu: \"$vm_data_mountpoint\""
test "$(stat -c %a "$vm_data_mountpoint")" = '770' ||
  die "invalid directory permissions, expected 770: \"$vm_data_mountpoint\""
test -e /tmp/qemu-pulse-native ||
  die 'socket does not exist: "/tmp/qemu-pulse-native", see ./host-configs/ for more informations'

(cd ./vm-configs/ && printf '%s\n' *) |
while read -r vm_name; do
  vmExists "$vm_name" || setupVM "$vm_name" "$alpine_version" "$alpine_iso" "$vm_data_mountpoint"
  reapplyConfigFlags "$vm_name" "vm-configs/$vm_name/config"

  test "$1" != 'regenerate-exposed-homedirs' || (
    homedir="$vm_data_mountpoint/$vm_name/home"
    if test -e "$homedir"; then
      populateVMVariables "$vm_name" "vm-configs/$vm_name/config"
      setupExposedUserHomedir "$homedir" "$cfg_color" "$cfg_kiosk"
    fi
  )
done
