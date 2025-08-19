This repository contains scripts for bootstrapping and maintaining Alpine Linux environments for
sandboxing.

# Why?

The Linux Desktop is moving into the right direction with Flatpak and its permission model, but it
is still not quite there where I want it to be. Alternatives like [Qubes
OS](https://www.qubes-os.org/) offer superior sandboxing, but it is very heavy and lacks GPU
acceleration. I need something between these two worlds and libvirt VMs are fitting my needs.

# Installation (Fedora)

```sh
sudo dnf install ansifilter bc libvirt netcat qemu tar util-linux-script virt-install virt-viewer
sudo gpasswd -a "$USER" libvirt
sudo mkdir -p /vm-data/
sudo chown "$USER:qemu" /vm-data/
sudo chmod 770 /vm-data/
```

Then follow the instructions located at the top of each file in `./host-configs/`.

# Defining VMs

Create a directory, e.g. in `./vm-configs/`, named after the VM to create and configure it as
described below. Then run `./setup-vms.sh ./vm-configs/`. Here is an example config to be placed in
`./vm-configs/YOUR_VM_NAME/config`:

```
cores=8
memory=4096
disksize=16
color=03bbaf
sound+microphone
internet
root_tty2
```

### Configuration flags

|       Flag       | Required | Static | Description                                                                 |
|:----------------:|:--------:|:------:|-----------------------------------------------------------------------------|
|       cores      |    ✔️    |        | vCPUs, e.g. `cores=8`, `cores=ALL` or `cores=4*2` to define thread topology |
|      memory      |    ✔️    |        | Memory to assign in MiB                                                     |
|       color      |    ✔️    |   ✔️   | Wallpaper/background color for distinguishing VMs                           |
|     disksize     |    ✔️    |   ✔️   | Size of the VMs qcow2 image                                                 |
|  expose\_homedir |          |   ✔️   | Create `/vm-data/VM_NAME/home/` and mount it into the VM                    |
|    root\_tty2    |          |   ✔️   | Spawn a terminal on TTY2 with root auto-login                               |
|       kiosk      |          |   ✔️   | Start all programs maximized without window decoration                      |
|     autostart    |          |        | Start the VM at boot                                                        |
|     clipboard    |          |        | Allow the VM to synchronize with the hosts clipboard                        |
|       sound      |          |        | Allow the VM to output sound                                                |
| sound+microphone |          |        | Allow the VM to output sound and access the microphone                      |
|        gpu       |          |        | Allow the VM to utilize the hosts GPU via OpenGL                            |
|     internet     |          |        | Allow the VM to access the internet                                         |
|      usb=...     |          |        | Allow attaching USB devices to the VM, see below                            |
|    cpupin=...    |          |        | Pin guest cores to host cores, e.g. `cpupin=0:8,1:9,2:10,3:11`              |
|      topoext     |          |        | AMD CPU feature for passing through SMT topology, see FAQ below             |

**Static** means the flag will only be applied during VM creation and will not be updated by
subsequent runs of `./setup-vms.sh ./vm-configs/`.

The `usb=...` flag accepts `android`, `printer`, `HID` and `webcam`. E.g. `usb=printer,webcam`.

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

The optional file `./vm-configs/YOUR_VM_NAME/setup.sh` will be run as root inside the VM during
setup. It runs after system configuration and package installation, but before the users homedir
gets mounted. If this script exits with a non-zero exit status, `./setup-vms.sh` will also fail with
the same exit status.

**Note**: These files will only be read during VM creation. Updating them has no effect on already
existing VMs.

# Usage

Example for launching an app in a virt-viewer window:

```sh
./run-in-vm.sh YOUR_VM_NAME firefox
./run-in-vm.sh YOUR_VM_NAME flatpak run com.discordapp.Discord
```

If the VM is not running, it will be started by the script. Closing the virt-viewer window will
gracefully close all windows currently open inside the VM. All VMs are running an openbox desktop
with an application tray hiding in the bottom left corner of the desktop.

**Note**: The console output of commands running in VMs will not be forwarded to the host due to
security reasons.

# Updating VMs

This script will send update commands to running VMs and keeps waiting for future VMs to start:

```sh
./update-service.sh ./vm-configs/
```

# Known Bugs

* Fractional scaling breaks VM window resizing. Set it to 100%, or a multiple it, and configure this
  file instead: `./files/Xresources` -> `Xft.dpi`
* On systems which remap capslock (e.g. to escape), it will cause the key to be [pressed
  twice](https://gitlab.freedesktop.org/spice/spice-gtk/-/issues/143). A workaround can be found
  here: <https://gitlab.freedesktop.org/spice/spice/-/issues/66>
* Virt-viewer does not forward the F10 key to the VM when the mouse is outside the VM window, even
  if the window is focused
* Virt-viewer sometimes auto-attaches your external dock's audio device to VMs with webcam
  permissions. That can mess up your configured audio setup. Detach the device from the VM via the
  menu on the top left corner of the virt-viewer window

# FAQ

## How to recreate a VM from scratch?

Delete the VM trough virt-manager and rerun `./setup-vms.sh ./vm-configs/`.

## I have set the clipboard flag but am unable to copy/paste

The VM must be restarted after applying the clipboard flag via `./setup-vms.sh ./vm-configs/`. Make
sure that virt-viewer has `Share clipboard` enabled in its preferences, which can be found at the
top right corner of the VM window.

## How to increase/decrease font scaling?

See `Xft.dpi` in `./files/Xresources`.

## How to use a different keyboard layout?

See `./files/setup-alpine.cfg` and `./files/openbox-autostart.sh`.

## How to run multiple webcams at once?

Find the PCI host devices to which your webcams are attached via `lsusb.py -ciu`. Add those PCI
devices to your VM.

### Why not just use a qemu USB 3.0 controller?

They cause webcam glitches due to some bug in qemu/kvm.

## How to do audio work if VMs have massively inconsistent audio latencies?

Remove `sound` and `sound+microphone` from the VM configuration and rerun `./setup-vms.sh
./vm-configs/`. Use `lsusb.py -ciu` to find the PCI device to which your sound hardware is attached.
Use virt-manager to manually assign this PCI device to your VM. When the VM starts, use alsamixer to
adjust the volume.

**Note**: You must assign whole PCI devices instead of just a single USB device to fix the latency,
according to my own testing.

## Rootless podman does not work when `expose_homedir` is set

Storing container images in your mounted home directory leads to the following error:

```
Error: copying system image from manifest list: writing blob: adding layer with blob"sha256:..."/""/"sha256:...": unpacking failed (error: exit status 1; output: setting up pivot dir:mkdir ./.pivot_root...: permission denied)
```

Run `podman system reset` and create the file `~/.config/containers/storage.conf`:

```conf
[storage]
driver = "overlay"
graphroot = "/var/lib/user/containers/storage"
```

Note that this requires the `fuse-overlayfs` package to be installed inside the VM. Also make sure
that the VMs configured disksize is large enough to store your images.

## What does the topoext flag do?

It prevents multiple CPU threads on the same core from being seen as separate CPU cores. When using
this flag, make sure your vcpu topology is defined properly and the cores are pinned accordingly.

![topoext.png](https://raw.githubusercontent.com/AlxHnr/media/refs/heads/gh-pages/topoext.png)
