#!/bin/sh -e

# Tests either fail with an error code or by hanging forever. A successful testrun should complete
# in a few seconds. The user running this script needs permissions to define and undefine vms.

cd "$(dirname "$0")"
export SETUP_VMS_SH_DONT_RUN='true'
# shellcheck disable=SC1091
. ./setup-vms.sh

export LIBVIRT_DEFAULT_URI='qemu:///system'

assert()
{
  "$@" || {
    printf '\033[1;31massert failed:\033[0m %s\n' "$*"
    exit 1
  } >&2
}

testName()
(
  printf '\033[1;34mRunning Test: \033[0;35m%s\033[0m\n' "$*"
)

testRunInPTY()
(
  serial_console_script="$*"

  trap 'rm "$SETUP_VM_TMPDIR/test-script.sh"' EXIT
  cat > "$SETUP_VM_TMPDIR/test-script.sh" <<EOF
printf "Connected to domain 'debug'\n"
$serial_console_script
EOF

  runInPTY "sh -e '$SETUP_VM_TMPDIR/test-script.sh'"
)

setupShell()
(
  printf 'export HISTFILE=/dev/null PS1="localhost:~$ "\n'
)

testName 'runInPTY - strip ANSI escape codes from output'
testRunInPTY < /dev/null "
printf '\033[1;31mstring containing ANSI escape codes\033[0m\n'" |
  assert grep -qE '^string containing ANSI escape codes$'

testName 'runInPTY - return exit code from guest to host'
(
  exit_code='0'
  testRunInPTY < /dev/null "printf 'COMMAND_EXIT_STATUS=174; localhost:~$ \n'" || exit_code="$?"
  assert test "$exit_code" = '174'
)

testName 'runInPTY - ANSI escape code filtering'
(
  exit_code='0'
  testRunInPTY < /dev/null "
printf '\033[1;31mCOMMAND_EXIT_STATUS=82; localhost:~$ \033[0m\n'" || exit_code="$?"
  assert test "$exit_code" = '82'
)

testName 'runInPTY - send ^] to virsh when input script completes'
printf '\n' | testRunInPTY 'read' | assert grep -qE '^\^\]$'

testName 'waitFor - basic output matching'
{
  waitFor 'Basic Output'
  printf '\n'
} | testRunInPTY "
printf 'Basic Output\n'
read"

testName 'waitFor - ANSI escape code filtering'
{
  waitFor '^string containing ANSI escape codes$'
  printf '\n'
} | testRunInPTY "
printf '\033[1;31mstring containing ANSI escape codes\033[0m\n'
read"

testName 'sendCommand - return exit code from guest to host'
(
  exit_code='0'
  sendCommand '(exit 24)' || exit_code="$?"
  assert test "$exit_code" = '24'
) | testRunInPTY "
read
printf 'localhost:~$ '
read
printf 'COMMAND_EXIT_STATUS=24; localhost:~$ '" || true

testName 'sendCommand - ANSI escape code filtering'
(
  exit_code='0'
  sendCommand '(exit 97)' || exit_code="$?"
  assert test "$exit_code" = '97'
  printf '\n'
) | testRunInPTY "
read
printf 'localhost:~$ '
read
printf '\033[1;31mCOMMAND_EXIT_STATUS=97; localhost:~$ \033[0m'
read" || true

testName 'sendCommand - communicate with real shell'
(
  setupShell
  sendCommand 'printf "Hello World\n"'

  exit_code='0'
  sendCommand '(exit 44)' || exit_code="$?"
  assert test "$exit_code" = '44'

  printf 'exit\n'
) | testRunInPTY 'sh' || true

testName 'waitAndLogin - initial login'
waitAndLogin | testRunInPTY "
read
printf 'localhost login: '
read
printf 'localhost:~$ '
read
printf 'COMMAND_EXIT_STATUS=0; localhost:~$ '"

testName 'waitAndLogin - user is already logged in'
{
  waitAndLogin
  waitAndLogin
} | testRunInPTY "
read
printf 'localhost:~$ '
read
printf 'localhost:~# '"

testName 'waitAndLogin - ANSI escape sequence filtering'
waitAndLogin | testRunInPTY "
read
printf '\033[1;32mlocalhost login: \033[0m\n'
read
printf 'localhost:~$ '
read
printf 'COMMAND_EXIT_STATUS=0; localhost:~$ '"

testName 'writeFile'
(
  trap 'rm "$SETUP_VM_TMPDIR/output.txt"' EXIT
  {
    setupShell
    printf 'Test content of a file\n' | writeFile "$SETUP_VM_TMPDIR/output.txt"
    printf 'exit\n'
  } | testRunInPTY 'sh' || true
  assert test -e "$SETUP_VM_TMPDIR/output.txt"
  assert test "$(cat "$SETUP_VM_TMPDIR/output.txt")" = "Test content of a file"
)

testName 'ensureIsoExists - gpg signature check: success'
ensureIsoExists '3.18.2' './test-files/alpine-minirootfs-3.18.2-x86_64.tar.gz'

testName 'ensureIsoExists - gpg signature check: tampered image'
(
  trap 'rm \
    "$SETUP_VM_TMPDIR/alpine-minirootfs-3.18.2-x86_64.tar.gz" \
    "$SETUP_VM_TMPDIR/alpine-minirootfs-3.18.2-x86_64.tar.gz.asc"' EXIT
  cp './test-files/alpine-minirootfs-3.18.2-x86_64.tar.gz'* "$SETUP_VM_TMPDIR"
  printf 'EXTRA BYTES' >> "$SETUP_VM_TMPDIR/alpine-minirootfs-3.18.2-x86_64.tar.gz"

  exit_code='0'
  ensureIsoExists '3.18.2' "$SETUP_VM_TMPDIR/alpine-minirootfs-3.18.2-x86_64.tar.gz" || exit_code=$?
  assert test "$exit_code" = '1'
)

(
  non_existing_vm="test-vm-name-which-does-not-exist-2023-07-16"

  testName 'populateVMVariables - config file is missing memory'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/missing-memory.txt 2>&1 |
      assert grep -q 'flag missing in \./test-files/configs/missing-memory\.txt: "memory"$'
  )

  testName 'populateVMVariables - invalid memory amount'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-memory.txt 2>&1 |
      assert grep -q 'invalid value in \./test-files/configs/invalid-memory.txt: "memory=invalid string"$'
  )

  testName 'populateVMVariables - invalid core count'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-core-count.txt 2>&1 |
      assert grep -q 'invalid value in \./test-files/configs/invalid-core-count\.txt: "cores=invalid string"$'
    # Parsing should terminate after first error, without printing further errors.
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-core-count.txt 2>&1 |
      wc -l | assert grep -q '^1$'
  )

  testName 'populateVMVariables - invalid disksize'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-disksize.txt 2>&1 |
      assert grep -q 'invalid value in \./test-files/configs/invalid-disksize.txt: "disksize=invalid string"$'
  )

  testName 'populateVMVariables - invalid line'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-line.txt 2>&1 |
      assert grep -q 'invalid line in \./test-files/configs/invalid-line\.txt: "invalid line"$'
  )

  testName 'populateVMVariables - invalid cpupin'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-cpupin.txt 2>&1 |
      assert grep -q 'invalid value in \./test-files/configs/invalid-cpupin\.txt: "cpupin=invalid"$'
  )

  testName 'populateVMVariables - empty cpupin'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-cpupin-empty.txt 2>&1 |
      assert grep -q 'invalid value in \./test-files/configs/invalid-cpupin-empty\.txt: "cpupin="$'
  )

  testName 'populateVMVariables - duplicate cpupin'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-cpupin-duplicate.txt 2>&1 |
      assert grep -q 'cpu core pinned multiple times in \./test-files/configs/invalid-cpupin-duplicate\.txt: "cpupin='
  )

  testName 'populateVMVariables - redefinition of cpupin'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/invalid-cpupin-redefinition.txt 2>&1 |
      assert grep -q 'redefinition of cpu affinity list in ./test-files/configs/invalid-cpupin-redefinition.txt: "cpupin=4:7"$'
  )

  testName 'populateVMVariables - reject invalid usb device lists'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/usb-device-list-empty.txt 2>&1 |
      assert grep -qF 'invalid value in ./test-files/configs/usb-device-list-empty.txt: "usb="'
    populateVMVariables "$non_existing_vm" ./test-files/configs/usb-device-list-trailing-colon-1.txt 2>&1 |
      assert grep -qF 'invalid value in ./test-files/configs/usb-device-list-trailing-colon-1.txt: "usb=,"'
    populateVMVariables "$non_existing_vm" ./test-files/configs/usb-device-list-trailing-colon-2.txt 2>&1 |
      assert grep -qF 'invalid value in ./test-files/configs/usb-device-list-trailing-colon-2.txt: "usb=webcam,"'
    populateVMVariables "$non_existing_vm" ./test-files/configs/usb-device-list-unknown-device.txt 2>&1 |
      assert grep -qF 'unknown usb device in config: "InvalidString"'
    populateVMVariables "$non_existing_vm" ./test-files/configs/usb-device-list-redefinition.txt 2>&1 |
      assert grep -qE 'redefinition of usb device list in .* "usb=printer"$'
  )

  testName 'populateVMVariables - parse minimal viable config'
  # shellcheck disable=SC2154
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/minimal-viable-config.txt
    assert test "$cfg_color"          = 'bcbcbc'
    assert test "$cfg_cores"          = '4'
    assert test "$cfg_memory"         = '2048'
    assert test "$cfg_disksize"       = '8'
    assert test "$cfg_expose_homedir" = 'false'
    assert test "$cfg_clipboard"      = 'false'
    assert test "$cfg_sound"          = 'false'
    assert test "$cfg_microphone"     = 'false'
    assert test "$cfg_gpu"            = 'false'
    assert test "$cfg_internet"       = 'false'
    assert test "$cfg_root_tty2"      = 'false'
    assert test "$cfg_kiosk"          = 'false'
    assert test "$cfg_autostart"      = 'false'
    assert test "$cfg_printer"        = 'false'
    assert test -z "$cfg_usb"
  )

  testName 'populateVMVariables - mixed values 1'
  # shellcheck disable=SC2154
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/mixed-values-1.txt
    assert test "$cfg_color"          = '000000'
    assert test "$cfg_cores"          = '2'
    assert test "$cfg_memory"         = '256'
    assert test "$cfg_disksize"       = '7'
    assert test "$cfg_expose_homedir" = 'false'
    assert test "$cfg_clipboard"      = 'true'
    assert test "$cfg_sound"          = 'true'
    assert test "$cfg_microphone"     = 'false'
    assert test "$cfg_gpu"            = 'true'
    assert test "$cfg_internet"       = 'false'
    assert test "$cfg_root_tty2"      = 'true'
    assert test "$cfg_kiosk"          = 'false'
    assert test "$cfg_autostart"      = 'false'
    assert test "$cfg_printer"        = 'false'
    assert test -z "$cfg_usb"
  )

  testName 'populateVMVariables - mixed values 2'
  # shellcheck disable=SC2154
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/mixed-values-2.txt
    assert test "$cfg_color"          = '000000'
    assert test "$cfg_cores"          = '2'
    assert test "$cfg_memory"         = '256'
    assert test "$cfg_disksize"       = '9'
    assert test "$cfg_expose_homedir" = 'true'
    assert test "$cfg_clipboard"      = 'false'
    assert test "$cfg_sound"          = 'true'
    assert test "$cfg_microphone"     = 'true'
    assert test "$cfg_gpu"            = 'false'
    assert test "$cfg_internet"       = 'true'
    assert test "$cfg_root_tty2"      = 'false'
    assert test "$cfg_kiosk"          = 'false'
    assert test "$cfg_autostart"      = 'false'
    assert test "$cfg_printer"        = 'false'
    assert test -z "$cfg_usb"
  )

  testName 'populateVMVariables - mixed values 3'
  # shellcheck disable=SC2154
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/mixed-values-3.txt
    assert test "$cfg_color"          = '000000'
    assert test "$cfg_cores"          = '4'
    assert test "$cfg_memory"         = '512'
    assert test "$cfg_disksize"       = '27'
    assert test "$cfg_expose_homedir" = 'false'
    assert test "$cfg_clipboard"      = 'false'
    assert test "$cfg_sound"          = 'true'
    assert test "$cfg_microphone"     = 'false'
    assert test "$cfg_gpu"            = 'false'
    assert test "$cfg_internet"       = 'false'
    assert test "$cfg_root_tty2"      = 'false'
    assert test "$cfg_kiosk"          = 'true'
    assert test "$cfg_autostart"      = 'true'
    assert test "$cfg_printer"        = 'true'
    assert test -z "$cfg_usb"
  )

  testName 'populateVMVariables - usb device list parsing 1'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/usb-device-list-1.txt
    assert test "$cfg_usb" = ' android printer'
  )

  testName 'populateVMVariables - usb device list parsing 2'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/usb-device-list-2.txt
    assert test "$cfg_usb" = ' android'
  )

  testName 'populateVMVariables - usb device list sorting and deduplication'
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/usb-device-list-unordered-duplicates.txt
    assert test "$cfg_usb" = ' android printer webcam'
  )

  testName 'populateVMVariables - replace ALL with max core count'
  # shellcheck disable=SC2154
  (
    max_core_count=$(nproc)
    populateVMVariables "$non_existing_vm" ./test-files/configs/core-count-all.txt
    assert test "$cfg_cores" = "$max_core_count"
  )

  testName 'populateVMVariables - provide NULL defaults for non existing vm'
  # shellcheck disable=SC2154
  (
    populateVMVariables "$non_existing_vm" ./test-files/configs/minimal-viable-config.txt
    assert test "$vm_color"          = 'NULL'
    assert test "$vm_cores"          = 'NULL'
    assert test "$vm_memory"         = 'NULL'
    assert test "$vm_disksize"       = 'NULL'
    assert test "$vm_expose_homedir" = 'NULL'
    assert test "$vm_clipboard"      = 'NULL'
    assert test "$vm_sound"          = 'NULL'
    assert test "$vm_microphone"     = 'NULL'
    assert test "$vm_gpu"            = 'NULL'
    assert test "$vm_internet"       = 'NULL'
    assert test "$vm_root_tty2"      = 'NULL'
    assert test "$vm_kiosk"          = 'NULL'
    assert test "$vm_autostart"      = 'NULL'
    assert test "$vm_printer"        = 'NULL'
    assert test "$vm_usb"            = 'NULL'
  )
)

testName 'populateVMVariables - reject unknown redirfilter usbdev class codes'
(
  trap 'virsh undefine 5e96ae71-25f5-4329-9aa9-6673fee3a15e' EXIT
  virsh define ./test-files/sample-vm-definition-usb-class-codes-unknown-redirfilter.xml

  populateVMVariables '5e96ae71-25f5-4329-9aa9-6673fee3a15e' \
    ./test-files/configs/minimal-viable-config.txt 2>&1 |
    assert grep -qE 'unknown redirfilter usbdev class code: "0x1C"'
)

testName 'populateVMVariables - extract usb device types'
(
  trap 'virsh undefine cb2ce12a-a52a-4414-882d-5c849b3719c6' EXIT
  virsh define ./test-files/sample-vm-definition-usb-class-codes.xml

  populateVMVariables 'cb2ce12a-a52a-4414-882d-5c849b3719c6' \
    ./test-files/configs/minimal-viable-config.txt
  assert test "$vm_usb" = ' printer webcam'
)

testName 'populateVMVariables - extract usb device types: sorting and deduplication'
(
  trap 'virsh undefine 89ecca4d-c9fb-4292-b2c4-7ccf988b308a' EXIT
  virsh define ./test-files/sample-vm-definition-usb-class-codes-unordered-duplicates.xml

  populateVMVariables '89ecca4d-c9fb-4292-b2c4-7ccf988b308a' \
    ./test-files/configs/minimal-viable-config.txt
  assert test "$vm_usb" = ' android printer webcam'
)

testName 'populateVMVariables - extract flags from existing vm 1'
# shellcheck disable=SC2154
(
  trap 'virsh undefine 3abd672c-b187-49ab-bb96-1646772547df' EXIT
  virsh define ./test-files/sample-vm-definition-1.xml

  populateVMVariables '3abd672c-b187-49ab-bb96-1646772547df' \
    ./test-files/configs/minimal-viable-config.txt
  assert test "$vm_color"          = '??????'
  assert test "$vm_cores"          = '3'
  assert test "$vm_memory"         = '768'
  assert test "$vm_disksize"       = '??????'
  assert test "$vm_expose_homedir" = 'false'
  assert test "$vm_clipboard"      = 'true'
  assert test "$vm_sound"          = 'true'
  assert test "$vm_microphone"     = 'true'
  assert test "$vm_gpu"            = 'false'
  assert test "$vm_internet"       = 'true'
  assert test "$vm_root_tty2"      = '??????'
  assert test "$vm_kiosk"          = '??????'
  assert test "$vm_autostart"      = 'false'
  assert test "$vm_printer"        = '??????'
  assert test -z "$vm_usb"
)

testName 'populateVMVariables - extract flags from existing vm 2'
# shellcheck disable=SC2154
(
  trap 'virsh undefine 9260d48d-adf8-4f37-9dc0-36cab8316e74' EXIT
  virsh define ./test-files/sample-vm-definition-2.xml

  populateVMVariables '9260d48d-adf8-4f37-9dc0-36cab8316e74' \
    ./test-files/configs/minimal-viable-config.txt
  assert test "$vm_cores"          = '2'
  assert test "$vm_memory"         = '512'
  assert test "$vm_expose_homedir" = 'false'
  assert test "$vm_clipboard"      = 'false'
  assert test "$vm_sound"          = 'false'
  assert test "$vm_microphone"     = 'false'
  assert test "$vm_gpu"            = 'true'
  assert test "$vm_internet"       = 'false'
  assert test "$vm_autostart"      = 'false'
  assert test -z "$vm_usb"
)

testName 'populateVMVariables - extract flags from existing vm 3'
# shellcheck disable=SC2154
(
  trap 'virsh undefine d8135b2e-9678-4539-81fb-7776b6afc576' EXIT
  virsh define ./test-files/sample-vm-definition-3.xml

  populateVMVariables 'd8135b2e-9678-4539-81fb-7776b6afc576' \
    ./test-files/configs/minimal-viable-config.txt
  assert test "$vm_cores"          = '4'
  assert test "$vm_memory"         = '768'
  assert test "$vm_expose_homedir" = 'true'
  assert test "$vm_clipboard"      = 'true'
  assert test "$vm_sound"          = 'true'
  assert test "$vm_microphone"     = 'false'
  assert test "$vm_gpu"            = 'false'
  assert test "$vm_internet"       = 'true'
  assert test "$vm_autostart"      = 'false'
  assert test -z "$vm_usb"
)

testName 'populateVMVariables - extract disksize from existing vm'
# shellcheck disable=SC2154
(
  image="$SETUP_VM_TMPDIR/image.qcow2"
  sed -r "s,TMP_DISK_IMAGE_PLACEHOLDER,$image," \
    ./test-files/sample-vm-definition-4.xml > "$SETUP_VM_TMPDIR/definition.xml"
  dd if=/dev/zero count=0 bs=1 seek=8G of="$image"

  trap 'virsh undefine f36e41c2-ca1a-4fd3-b1ea-b0718d407374; rm "$image"' EXIT
  virsh define "$SETUP_VM_TMPDIR/definition.xml"

  populateVMVariables 'f36e41c2-ca1a-4fd3-b1ea-b0718d407374' \
    ./test-files/configs/minimal-viable-config.txt
  assert test "$vm_cores"          = '3'
  assert test "$vm_memory"         = '768'
  assert test "$vm_disksize"       = '8'
  assert test "$vm_expose_homedir" = 'false'
  assert test "$vm_clipboard"      = 'true'
  assert test "$vm_sound"          = 'true'
  assert test "$vm_microphone"     = 'true'
  assert test "$vm_gpu"            = 'false'
  assert test "$vm_internet"       = 'true'
  assert test "$vm_autostart"      = 'false'
  assert test -z "$vm_usb"
)

testName 'populateVMVariables - detect deviations between config file and vm state'
# shellcheck disable=SC2154
(
  trap 'virsh undefine 3abd672c-b187-49ab-bb96-1646772547df' EXIT
  virsh define ./test-files/sample-vm-definition-1.xml

  (
    populateVMVariables '3abd672c-b187-49ab-bb96-1646772547df' \
      ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test -z "$vm_cfg_deviations"
  )

  (
    populateVMVariables '3abd672c-b187-49ab-bb96-1646772547df' \
      ./test-files/configs/config-for-deviation-test-2.txt
    assert test "$vm_cfg_deviations" = 'cores clipboard microphone'
  )

  (
    populateVMVariables '3abd672c-b187-49ab-bb96-1646772547df' \
      ./test-files/configs/config-for-deviation-test-3.txt
    assert test "$vm_cfg_deviations" = ' memory sound microphone gpu'
  )

  (
    populateVMVariables '3abd672c-b187-49ab-bb96-1646772547df' \
      ./test-files/configs/config-for-deviation-test-4.txt
    assert test "$vm_cfg_deviations" = ' expose_homedir internet autostart'
  )

  (
    populateVMVariables '3abd672c-b187-49ab-bb96-1646772547df' \
      ./test-files/configs/config-for-deviation-test-5.txt
    assert test "$vm_cfg_deviations" = ' gpu usb'
  )
)

testName 'populateVMVariables - detect deviations in configured disksize'
# shellcheck disable=SC2154
(
  image="$SETUP_VM_TMPDIR/image.qcow2"
  sed -r "s,TMP_DISK_IMAGE_PLACEHOLDER,$image," \
    ./test-files/sample-vm-definition-4.xml > "$SETUP_VM_TMPDIR/definition.xml"
  dd if=/dev/zero count=0 bs=1 seek=8G of="$image"

  trap 'virsh undefine f36e41c2-ca1a-4fd3-b1ea-b0718d407374; rm "$image"' EXIT
  virsh define "$SETUP_VM_TMPDIR/definition.xml"

  (
    populateVMVariables 'f36e41c2-ca1a-4fd3-b1ea-b0718d407374' \
      ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test -z "$vm_cfg_deviations"
  )

  (
    populateVMVariables 'f36e41c2-ca1a-4fd3-b1ea-b0718d407374' \
      ./test-files/configs/config-for-deviation-test-6.txt
    assert test "$vm_cfg_deviations" = 'cores disksize'
  )
)

testName 'reapplyConfigFlags'
# shellcheck disable=SC2154
(
  trap 'virsh undefine 3abd672c-b187-49ab-bb96-1646772547df' EXIT
  virsh define ./test-files/sample-vm-definition-1.xml
  vm_name="vm-scripts-virtual-machine-for-testing-1"

  (
    populateVMVariables "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test "$vm_cores"          = '3'
    assert test "$vm_memory"         = '768'
    assert test "$vm_expose_homedir" = 'false'
    assert test "$vm_clipboard"      = 'true'
    assert test "$vm_sound"          = 'true'
    assert test "$vm_microphone"     = 'true'
    assert test "$vm_gpu"            = 'false'
    assert test "$vm_internet"       = 'true'
    assert test "$vm_autostart"      = 'false'
    assert test -z "$vm_usb"
  )

  # Nothing should change
  reapplyConfigFlags "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test "$vm_cores"          = '3'
    assert test "$vm_memory"         = '768'
    assert test "$vm_expose_homedir" = 'false'
    assert test "$vm_clipboard"      = 'true'
    assert test "$vm_sound"          = 'true'
    assert test "$vm_microphone"     = 'true'
    assert test "$vm_gpu"            = 'false'
    assert test "$vm_internet"       = 'true'
    assert test "$vm_autostart"      = 'false'
    assert test -z "$vm_usb"
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-1.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-1.txt
    assert test "$vm_cores"          = '8'
    assert test "$vm_memory"         = '768'
    assert test "$vm_expose_homedir" = 'false'
    assert test "$vm_clipboard"      = 'false'
    assert test "$vm_sound"          = 'true'
    assert test "$vm_microphone"     = 'false'
    assert test "$vm_gpu"            = 'false'
    assert test "$vm_internet"       = 'true'
    assert test "$vm_autostart"      = 'false'
    assert test -z "$vm_usb"
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-2.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-2.txt
    assert test "$vm_cores"          = '8'
    assert test "$vm_memory"         = '1024'
    assert test "$vm_expose_homedir" = 'false'
    assert test "$vm_clipboard"      = 'false'
    assert test "$vm_sound"          = 'true'
    assert test "$vm_microphone"     = 'true'
    assert test "$vm_gpu"            = 'true'
    assert test "$vm_internet"       = 'false'
    assert test "$vm_autostart"      = 'false'
    assert test -z "$vm_usb"
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-3.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-3.txt
    assert test "$vm_cores"          = '8'
    assert test "$vm_memory"         = '1024'
    assert test "$vm_expose_homedir" = 'false'
    assert test "$vm_clipboard"      = 'false'
    assert test "$vm_sound"          = 'false'
    assert test "$vm_microphone"     = 'false'
    assert test "$vm_gpu"            = 'false'
    assert test "$vm_internet"       = 'true'
    assert test "$vm_autostart"      = 'false'
    assert test -z "$vm_usb"
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-4.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-4.txt
    assert test "$vm_cores"          = '8'
    assert test "$vm_memory"         = '1024'
    assert test "$vm_expose_homedir" = 'false'
    assert test "$vm_clipboard"      = 'true'
    assert test "$vm_sound"          = 'true'
    assert test "$vm_microphone"     = 'false'
    assert test "$vm_gpu"            = 'false'
    assert test "$vm_internet"       = 'true'
    assert test "$vm_autostart"      = 'false'
    assert test -z "$vm_usb"
  )

  # Test switching from no sound to sound+microphone
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-3.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-3.txt
    assert test "$vm_sound"      = 'false'
    assert test "$vm_microphone" = 'false'
  )
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-2.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-2.txt
    assert test "$vm_sound"      = 'true'
    assert test "$vm_microphone" = 'true'
  )

  # Ensure that switching expose_homedir gets explicitly ignored
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-5.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-5.txt
    assert test "$cfg_expose_homedir" = 'true'
    assert test "$vm_expose_homedir" = 'false'
  )

  # Switching autostart
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-6.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-6.txt
    assert test "$vm_autostart" = 'true'
  )
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-2.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-2.txt
    assert test "$vm_autostart" = 'false'
  )

  # Switching usb devices
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-7.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-7.txt
    assert test "$vm_usb" = ' webcam'
    xml=$(virsh dumpxml --inactive "$vm_name")
    printf '%s\n' "$xml" | assert grep -qF "<usbdev allow='no'/>"
    { ! printf '%s\n' "$xml" | grep -qE '<usbdev class=.\<0xFF\>'; } ||
      assert false 'reapplyConfigFlags: xml contains 0xFF usb class'
  )
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-8.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-8.txt
    assert test "$vm_usb" = ' android'
    virsh dumpxml --inactive "$vm_name" | assert grep -qF "<usbdev allow='no'/>"
  )
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-9.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-9.txt
    assert test "$vm_usb" = ' android printer'
    virsh dumpxml --inactive "$vm_name" | assert grep -qF "<usbdev allow='no'/>"
  )
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-10-usb-duplicates.txt
  (
    # Both `android` and `printer` try to insert class="0xFF"
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-10-usb-duplicates.txt
    assert test "$vm_usb" = ' android printer'

    xml=$(virsh dumpxml --inactive "$vm_name")
    printf '%s\n' "$xml" | assert grep -qF "<usbdev allow='no'/>"
    printf '%s\n' "$xml" | grep -cE '<usbdev class=.\<0x06\>' | grep -qxF '1' ||
      assert false 'reapplyConfigFlags: xml contains multiple 0x06 usb classes'
    printf '%s\n' "$xml" | grep -cE '<usbdev class=.\<0x07\>' | grep -qxF '1' ||
      assert false 'reapplyConfigFlags: xml contains multiple 0x07 usb classes'
    printf '%s\n' "$xml" | grep -cE '<usbdev class=.\<0xFF\>' | grep -qxF '1' ||
      assert false 'reapplyConfigFlags: xml contains multiple 0xFF usb classes'
  )
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-2.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-2.txt
    assert test -z "$vm_usb"

    xml=$(virsh dumpxml --inactive "$vm_name")
    { ! printf '%s\n' "$xml" | grep -qF '<redirdev'; } ||
      assert false 'makeVirtInstallCommand: xml contains redirector device'
    { ! printf '%s\n' "$xml" | grep -qF '<redirfilter'; } ||
      assert false 'makeVirtInstallCommand: xml contains redirfilter'
    { ! printf '%s\n' "$xml" | grep -qF '<usbdev'; } ||
      assert false 'makeVirtInstallCommand: xml contains usb filter rule'
  )
)

testName 'reapplyConfigFlags - disksize'
# shellcheck disable=SC2154
(
  image="$SETUP_VM_TMPDIR/image.qcow2"
  sed -r "s,TMP_DISK_IMAGE_PLACEHOLDER,$image," \
    ./test-files/sample-vm-definition-4.xml > "$SETUP_VM_TMPDIR/definition.xml"
  dd if=/dev/zero count=0 bs=1 seek=8G of="$image"

  trap 'virsh undefine f36e41c2-ca1a-4fd3-b1ea-b0718d407374; rm "$image"' EXIT
  virsh define "$SETUP_VM_TMPDIR/definition.xml"
  vm_name="vm-scripts-virtual-machine-for-testing-4"

  (
    populateVMVariables "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test "$vm_cores"    = '3'
    assert test "$vm_memory"   = '768'
    assert test "$vm_disksize" = '8'
  )

  # Nothing should change
  reapplyConfigFlags "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test "$vm_cores"    = '3'
    assert test "$vm_memory"   = '768'
    assert test "$vm_disksize" = '8'
  )

  # Ensure that switching disksize gets explicitly ignored
  reapplyConfigFlags "$vm_name" ./test-files/configs/change-flags-11.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/change-flags-11.txt
    assert test "$vm_disksize" = '8'
    assert test "$cfg_disksize" = '4'
  )
)

testName 'topoext flag'
# shellcheck disable=SC2154
(
  trap 'virsh undefine 3abd672c-b187-49ab-bb96-1646772547df' EXIT
  virsh define ./test-files/sample-vm-definition-1.xml
  vm_name="vm-scripts-virtual-machine-for-testing-1"

  (
    populateVMVariables "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test "$cfg_topoext" = 'false'
    assert test "$vm_topoext" = 'false'
    assert test -z "$vm_cfg_deviations"
  )

  (
    populateVMVariables "$vm_name" ./test-files/configs/topoext.txt
    assert test "$cfg_topoext" = 'true'
    assert test "$vm_topoext" = 'false'
    assert test "$vm_cfg_deviations" = ' topoext'
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/topoext.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/topoext.txt
    assert test "$cfg_topoext" = 'true'
    assert test "$vm_topoext" = 'true'
    assert test "$vm_cfg_deviations" = ''
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test "$cfg_topoext" = 'false'
    assert test "$vm_topoext" = 'false'
    assert test "$vm_cfg_deviations" = ''
  )
)

testName 'cpupin flag'
# shellcheck disable=SC2154
(
  trap 'virsh undefine e1e1469d-c271-4402-b9c3-5c14e0f97fb0' EXIT
  virsh define ./test-files/sample-vm-20-cores.xml
  vm_name="vm-scripts-virtual-machine-for-testing-cpupin"

  (
    populateVMVariables "$vm_name" ./test-files/configs/cpupin-1-empty.txt
    assert test -z "$cfg_cpupin"
    assert test -z "$vm_cpupin"
    assert test -z "$vm_cfg_deviations"
  )

  (
    populateVMVariables "$vm_name" ./test-files/configs/cpupin-2.txt
    assert test -n "$cfg_cpupin"
    assert test -z "$vm_cpupin"
    assert test "$vm_cfg_deviations" = ' cpupin'
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/cpupin-2.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/cpupin-2.txt
    assert test -n "$cfg_cpupin"
    assert test -n "$vm_cpupin"
    assert test -z "$vm_cfg_deviations"
  )
  virsh vcpupin "$vm_name" --config | assert grep -qE '^\s*0\s+0$'
  virsh vcpupin "$vm_name" --config | assert grep -qE '^\s*1\s+1$'
  virsh vcpupin "$vm_name" --config | assert grep -qE '^\s*4\s+2$'
  virsh vcpupin "$vm_name" --config | assert grep -qE '^\s*12\s+12$'

  (
    populateVMVariables "$vm_name" ./test-files/configs/cpupin-2-shuffled-order.txt
    assert test -n "$cfg_cpupin"
    assert test -n "$vm_cpupin"
    assert test -z "$vm_cfg_deviations"
  )

  (
    populateVMVariables "$vm_name" ./test-files/configs/cpupin-3.txt
    assert test -n "$cfg_cpupin"
    assert test -n "$vm_cpupin"
    assert test "$vm_cfg_deviations" = ' cpupin'
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/cpupin-3.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/cpupin-3.txt
    assert test -n "$cfg_cpupin"
    assert test -n "$vm_cpupin"
    assert test -z "$vm_cfg_deviations"
  )

  (
    populateVMVariables "$vm_name" ./test-files/configs/cpupin-1-empty.txt
    assert test -z "$cfg_cpupin"
    assert test -n "$vm_cpupin"
    assert test "$vm_cfg_deviations" = ' cpupin'
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/cpupin-1-empty.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/cpupin-1-empty.txt
    assert test -z "$cfg_cpupin"
    assert test -z "$vm_cpupin"
    assert test -z "$vm_cfg_deviations"
  )
)

testName 'cpu topology'
# shellcheck disable=SC2154
(
  trap 'virsh undefine 3abd672c-b187-49ab-bb96-1646772547df' EXIT
  virsh define ./test-files/sample-vm-definition-1.xml
  vm_name="vm-scripts-virtual-machine-for-testing-1"

  (
    populateVMVariables "$vm_name" ./test-files/configs/cpu-topology-1.txt
    assert test "$cfg_cores" = '4*2'
    assert test "$vm_cores" = '3'
    assert test "$vm_cfg_deviations" = 'cores'
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/cpu-topology-1.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/cpu-topology-1.txt
    assert test "$cfg_cores" = '4*2'
    assert test "$vm_cores" = '4*2'
    assert test -z "$vm_cfg_deviations"
    xml=$(virsh dumpxml --inactive "$vm_name")
    printf '%s\n' "$xml" | assert grep -qF '>8</vcpu>'
    printf '%s\n' "$xml" | assert grep -qE '<cache\s+mode=.passthrough./>'
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/cpu-topology-2.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/cpu-topology-2.txt
    assert test "$cfg_cores" = '2*4'
    assert test "$vm_cores" = '2*4'
    assert test -z "$vm_cfg_deviations"
    xml=$(virsh dumpxml --inactive "$vm_name")
    printf '%s\n' "$xml" | assert grep -qF '>8</vcpu>'
    printf '%s\n' "$xml" | assert grep -qE '<cache\s+mode=.passthrough./>'
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/cpu-topology-3.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/cpu-topology-3.txt
    assert test "$cfg_cores" = '16*2'
    assert test "$vm_cores" = '16*2'
    assert test -z "$vm_cfg_deviations"
    xml=$(virsh dumpxml --inactive "$vm_name")
    printf '%s\n' "$xml" | assert grep -qF '>32</vcpu>'
    printf '%s\n' "$xml" | assert grep -qE '<cache\s+mode=.passthrough./>'
  )

  reapplyConfigFlags "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
  (
    populateVMVariables "$vm_name" ./test-files/configs/config-for-deviation-test-1-no-changes.txt
    assert test "$cfg_cores" = '3'
    assert test "$vm_cores" = '3'
    assert test -z "$vm_cfg_deviations"
    xml=$(virsh dumpxml --inactive "$vm_name")
    printf '%s\n' "$xml" | assert grep -qF '>3</vcpu>'
    { ! printf '%s\n' "$xml" | grep -qE '<cache mode=.\<passthrough\>'; } ||
      assert false 'reapplyConfigFlags: xml contains cpu cache mode: passthrough'
  )
)

testName 'makeVirtInstallCommand'
(
  printf 'Generating xml definition...\n'
  non_existing_vm="test-vm-name-which-does-not-exist-2023-07-16"
  virt_install_command=$(makeVirtInstallCommand "$non_existing_vm" "$SETUP_VM_TMPDIR/image.qcow2" 8)
  printf '%s\n' "$virt_install_command" | assert grep -qF -- '--disk size=8,'

  printf 'Validating xml definition...\n'
  xml=$(sh -c "$virt_install_command --print-xml --dry-run --check disk_size=off")
  printf '%s\n' "$xml" | assert grep -qF "<name>$non_existing_vm</name>"
  printf '%s\n' "$xml" | assert grep -qF "<source file=\"$SETUP_VM_TMPDIR/image.qcow2\"/>"
  printf '%s\n' "$xml" | assert grep -qF 'discard="unmap"'
  printf '%s\n' "$xml" | assert grep -qF '<clipboard copypaste="no"/>'
  printf '%s\n' "$xml" | assert grep -qF '<filetransfer enable="no"/>'
  printf '%s\n' "$xml" | assert grep -qF '<listen type="none"/>'
  printf '%s\n' "$xml" | assert grep -qF '<gl enable="no"/>'
  { ! printf '%s\n' "$xml" | grep -qF 'org.qemu.guest_agent.0'; } ||
    assert false 'makeVirtInstallCommand: xml contains org.qemu.guest_agent.0'
  { ! printf '%s\n' "$xml" | grep -qF '<sound model='; } ||
    assert false 'makeVirtInstallCommand: xml contains sound card'
  { ! printf '%s\n' "$xml" | grep -qF '<redirdev'; } ||
    assert false 'makeVirtInstallCommand: xml contains redirector device'
)

printf '\033[1;32mAll tests passed!\033[0m\n'
