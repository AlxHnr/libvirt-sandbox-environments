This repository contains scripts for bootstrapping and maintaining Alpine Linux environments for
sandboxing.

# Why?

The Linux Desktop is moving into the right direction with Flatpak and its permission model, but it
is still not quite there where I want it to be. Alternatives like [Qubes
OS](https://www.qubes-os.org/) offer superior sandboxing, but it is very heavy and lacks GPU
acceleration. I need something between these two worlds and libvirt VMs are fitting my needs.

# Installation (Fedora)

The scripts in this directory expect the current user to be part of the `libvrit` group and have the
permissions to access `/vm-data/`:

```sh
sudo dnf install ansifilter bc tar virt-install virt-manager virt-viewer
sudo gpasswd -a "$USER" libvirt
sudo mkdir -p /vm-data/
sudo chown "$USER:qemu" /vm/data/
sudo chmod 770 /vm-data/
```

Then follow the instructions located at the top of each file in `./host-configs/`.

# Defining VMs

Create a directory in `./vm-configs/` named after the VM to create and configure it as described
below. Then run `./setup-vms.sh`. Here is an example config to be placed in
`./vm-configs/YOUR_VM_NAME/config`:

```
color=bbbbbb
cores=ALL
memory=4096
disksize=16
sound+microphone
internet
root_tty2
```

### Configuration flags

|       Flag       | Required | Static | Description                                              |
|:----------------:|:--------:|:------:|----------------------------------------------------------|
|       cores      |     ✔️    |        | Integer larger than 0 or the string `ALL`                |
|      memory      |     ✔️    |        | Memory to assign in MiB                                  |
|       color      |     ✔️    |    ✔️   | Background color for distinguishing VMs                  |
|     disksize     |     ✔️    |    ✔️   | Size of the VMs qcow2 image                              |
|  expose\_homedir |          |    ✔️   | Create `/vm-data/VM_NAME/home/` and mount it into the VM |
|    root\_tty2    |          |    ✔️   | Spawn a terminal on TTY2 with root auto-login            |
|       kiosk      |          |    ✔️   | Start all programs maximized without window decoration   |
|      printer     |          |    ✔️   | Setup CUPS                                               |
|     autostart    |          |        | Start the VM at boot                                     |
|     clipboard    |          |        | Allow the VM to synchronize with the hosts clipboard     |
|       sound      |          |        | Allow the VM to output sound                             |
| sound+microphone |          |        | Allow the VM to output sound and access the microphone   |
|        gpu       |          |        | Allow the VM to utilize the hosts GPU                    |
|     internet     |          |        | Allow the VM to access the internet                      |
|      usb=...     |          |        | Allow attaching USB devices to the VM, see below         |

**Static** means the flag will only be applied during VM creation and will not be updated by
subsequent runs of `./setup-vms.sh`.

The `usb=...` flag accepts `android`, `printer` and `webcam`. E.g. `usb=webcam` or
`usb=printer,webcam`.

### Install packages during VM creation

The optional file `./vm-configs/YOUR_VM_NAME/packages` can contain a list of Alpine packages to be
installed in addition to the [default packages](./files/packages).

```
firefox
gimp
git
```

The optional file `./vm-configs/YOUR_VM_NAME/flatpaks` can contain a list of flatpak apps to be
installed:

```
com.discordapp.Discord
```

The optional file `./vm-configs/YOUR_VM_NAME/pip` can contain a list of python packages to be
installed:

```
beancount
fava
```

**Note**: These files will only be read during VM creation. Updating them has no effect on already
existing VMs.

# Usage

Example for launching an app in a virt-viewer window:

```sh
./run-in-vm.sh YOUR_VM_NAME firefox
./run-in-vm.sh YOUR_VM_NAME flatpak --user run com.discordapp.Discord
```

If the VM is not running, it will be started by the script. Closing the virt-viewer window will
gracefully close all windows currently open inside the VM. All VMs are running an openbox desktop
with an application tray hiding in the bottom left corner of the desktop.

**Note**: The console output of commands running in VMs will not be forwarded to the host due to
security reasons.

# Updating VMs

This script will send update commands to running VMs and keeps waiting for future VMs to start:

```sh
./update-service.sh
```

# Known Bugs

* `./run-in-vm.sh` only communicates with the VM in one direction (host to VM) for security reasons.
  It does not know when a VM has fully started and uses [guesstimates](./run-in-vm.sh#L47). In the
  rare case that a flatpak app starts before pulseaudio, the app may not see the microphone and
  should be restarted
* Virt-viewer sometimes intercepts the F10 key and does not forward it to the VM. To fix this, click
  into the VMs window or use the scroll wheel while the cursor is inside the VM window
* On systems which remap capslock (e.g. to escape), it will cause the key to be [pressed
  twice](https://gitlab.freedesktop.org/spice/spice-gtk/-/issues/143). A workaround can be found
  here: <https://gitlab.freedesktop.org/spice/spice/-/issues/66>
* When resizing virt-viewer windows on high-resolution displays, it may cause the VMs desktop to
  freeze for ~10 seconds on rare occasions

# FAQ

## How to recreate a VM from scratch?

Delete the VM. E.g. trough virt-manager, optionally together with its qcow2 image and then run
`./setup-vms.sh`.

## I have set the clipboard flag but am unable to copy/paste

The VM must be restarted after applying the clipboard flag via `./setup-vms.sh`. Make sure that
virt-viewer has `Share clipboard` enabled in its preferences, which can be found at the top right
corner of the VM window.

## How to increase/decrease font scaling?

See `Xft.dpi` in `./files/Xresources`.

## How to use a different keyboard layout?

See `./files/setup-alpine.cfg` and `./files/openbox-autostart.sh`.
