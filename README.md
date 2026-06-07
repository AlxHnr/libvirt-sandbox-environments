Scripts in this repository create and configure VMs from minimal config files. These configs can
contain a list of packages to install into the VM. They also define VM permissions like microphone
access, host clipboard access and which ports should be exposed to the internet.

This allows you to define separate and independent environments for work, banking, surfing and
development. The concept is heavily borrowed from [Qubes OS](https://www.qubes-os.org/), which I've
used for over half a decade. I've stopped using Qubes because it is way too heavy and overkill for
my threat model. It also lacks basic things like GPU acceleration. With these scripts here I can
just add the `gpu` flag to a VMs config and reapply it through a script.

VMs run a minimal Alpine Linux system with Openbox as window manager.

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

Create a directory, e.g. `./vm-configs/YOUR_VM_NAME/` and a file named `config` inside it:

```
cores=8
memory=4096
disksize=16
color=03bbaf
sound+microphone
internet
```

Then run `./setup-vms.sh ./vm-configs/`.

### Configuration flags

|         Flag        | Required | Static | Description                                                                 |
|:-------------------:|:--------:|:------:|-----------------------------------------------------------------------------|
|        cores        |    ✔️    |        | vCPUs, e.g. `cores=8`, `cores=ALL` or `cores=4*2` to define thread topology |
|        memory       |    ✔️    |        | Memory to assign in MiB                                                     |
|        color        |    ✔️    |   ✔️   | Wallpaper/background color for distinguishing VMs                           |
|       disksize      |    ✔️    |   ✔️   | Size of the VMs qcow2 image in GiB                                          |
|    disksize\_home   |          |   ✔️   | Size of the qcow2 image of the VMs `/home/user/` in GiB                     |
|   expose\_homedir   |          |   ✔️   | Create `/vm-data/VM_NAME/home/` and mount it into the VM                    |
|      root\_tty2     |          |   ✔️   | Spawn a terminal on TTY2 with root auto-login                               |
|        kiosk        |          |   ✔️   | Start all programs maximized without window decoration                      |
|      autostart      |          |        | Start the VM at boot                                                        |
|      clipboard      |          |        | Allow the VM to synchronize with the hosts clipboard                        |
|        sound        |          |        | Allow the VM to output sound                                                |
|   sound+microphone  |          |        | Allow the VM to output sound and access the microphone                      |
|         gpu         |          |        | Allow the VM to utilize the hosts GPU via OpenGL                            |
|       internet      |          |        | Allow the VM to access the internet                                         |
| internet+expose=... |          |        | Forward ports from host to guest, e.g. `tcp:80:8080,udp:12:12`              |
|      cpupin=...     |          |        | Pin guest cores to host cores, e.g. `cpupin=0:8,1:9,2:10,3:11`              |
|       topoext       |          |        | AMD CPU feature for passing through SMT topology, see FAQ below             |

**Static** means the flag will only be applied during VM creation and will not be updated by
subsequent runs of `./setup-vms.sh ./vm-configs/`.

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

The optional file `./vm-configs/YOUR_VM_NAME/setup-user.sh` will be run as a normal user inside the
VMs `$HOME` directory. It runs only one single time on the very first boot, right before the desktop
environment launches. If this script exits with a non-zero status, the desktop won't start.

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

# Issues and limitations

* Multi-touch mouse gestures are not forwarded to guest VMs
* Fractional scaling on the host breaks VM window resizing. Instead, change the dpi setting in
  `./files/home/Xresources` before creating your VMs
  ([#71](https://gitlab.com/virt-viewer/virt-viewer/-/work_items/71),
  [#144](https://gitlab.com/virt-viewer/virt-viewer/-/work_items/144),
  [#524](https://github.com/virt-manager/virt-manager/issues/524))
* Virt-viewer does not forward the F10 key to the VM when the mouse is outside the VM window, even
  if the window is focused ([#173](https://gitlab.com/virt-viewer/virt-viewer/-/work_items/173))
* VMs without the `gpu` flag have a very small chance of freezing when e.g. dragging large windows
  around. In that case they need a hard-reset
* On systems which remap capslock (e.g. to escape), it will cause the key to be [pressed
  twice](https://gitlab.freedesktop.org/spice/spice-gtk/-/issues/143). A workaround can be found
  here: <https://gitlab.freedesktop.org/spice/spice/-/issues/66>

# FAQ

## How secure are sandboxes created by these scripts?

They may not be as paranoid as Qubes OS, but are still way stronger than the sandboxing used by
Flatpak and modern web browsers.

These scripts follow modern development practices and don't try to be smart. They are just a very
thin configuration layer around libvirt. The actual security comes from the enormous amount of
resources and millions of man-hours poured into hardening QEMU. Everything in this repository is
designed to be as restrictive as possible by default. If a VM has no explicit clipboard or GPU
permissions, it will never be able to access those.

While the host can send commands to the guests, the guests will never be able to communicate with
the host through the scripts provided by this repository. The only exception is the VMs setup
process. It uses a signed Alpine image and only runs code which can be traced back to its origin.
Once the installation is complete, guests will be treated like they're compromised from thereon. A
guests home image or home directory can be stored separately and may contain clutter from previous
usage. Therefore the homedir is not exposed to the VM during the entire setup process and only gets
attached right after the installation has finished.

## How to recreate a VM from scratch?

Delete the VM trough virt-manager and rerun `./setup-vms.sh ./vm-configs/`. To regenerate
images/directories created trough `disksize_home` or `expose_homedir`, remove
`/vm-data/VM_NAME/image-home.qcow2` or `/vm-data/VM_NAME/home/` before running the script.

## I have set the clipboard flag but am unable to copy/paste

The VM needs a full, complete shutdown before starting it again to ensure the
flag is set. Make sure that virt-viewer has `Share clipboard` enabled in its
preferences, which can be found at the top right corner of the VM window.

## I have forwarded host ports to a VM, but it doesn't work

The VM needs a full, complete shutdown before starting it again to ensure the
ports are defined. If your config forwards port 80 on the host to the guests
port 8080, e.g:

```
internet+expose=tcp:80:8080
```

you may still have to update your firewall rules. Example on Fedora:

```sh
sudo firewall-cmd --zone=public --add-port=80/tcp
```

## How to increase/decrease font scaling?

See `Xft.dpi` in `./files/home/Xresources`.

## How to use a different keyboard layout?

See `./files/setup-alpine.cfg` and `./files/bin/openbox-custom-autostart.sh`.

## Do the scripts work with user session VMs?

That requires changing `LIBVIRT_DEFAULT_URI` to `qemu:///session` in the codebase. A lot of the code
will still apply system-session specific settings to the VM. Everything should work despite that,
but these settings are overkill for plain user sessions.

## How to enable Vulkan acceleration for VMs?

As of right now, you can't. But I will add a Vulkan flag when these issues are resolved:

* https://gitlab.com/libvirt/libvirt/-/work_items/638
* Being able to use the Venus renderer without disabling the sandbox
* Packages have to land in Fedora, including updated SELinux policies

## Are guest VMs using wayland?

Not yet, the following issues need to be resolved:

* Find a lightweight window manager which works without a full desktop environment
* Get xdg screencast portals working

Potential candidates and their issues:

* Mutter: has deep hidden dependencies to gnome-shell, which breaks IBUS/keyboard layout switching
* KWin: no viable screencast portal, xdg-desktop-portal-kde only works within Plasma
* Weston: doesn't support runtime resolution switching
  ([#339](https://gitlab.freedesktop.org/wayland/weston/-/issues/339),
  [#341](https://gitlab.freedesktop.org/wayland/weston/-/issues/341))
* Wlroots-based compositors like Labwc suffer from flipped mouse cursors
  ([#2315](https://gitlab.com/qemu-project/qemu/-/work_items/2315),
  [#3921](https://gitlab.freedesktop.org/wlroots/wlroots/-/work_items/3921))

## How to attach devices like webcams or microphones to a VM?

Run `lsusb.py -ciu` from usbutils to find the PCI device to which your webcam is attached. If this
PCI device also hosts other USB devices which you don't want to expose to your VM, try reconnecting
your webcam to a different USB port.

To auto-attach the PCI device every time your VM starts, use virt-manager's GUI.

To attach the device temporarily to a running VM until it shuts down, create the following XML file.
Example for PCI device `0000:c1:00.3`:

```xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
    <address domain="0x0000" bus="0xc1" slot="0x00" function="0x3"/>
  </source>
</hostdev>
```

Then run `virsh attach-device VM_NAME --live ./YOUR_XML.xml`. Alpine guests support PCI hotplugging
and should recognize your hardware.

### Why not use qemu/libvirt's builtin mechanism for attaching USB devices?

They suffer from performance issues, which cause webcams to glitch and audio hardware to underrun or
have weird delays. Hacks like switching to USB 2.0 (ehci), tweaking iothreads and pinning cores make
it less worse, but never fix it completely. Some modern webcams won't even start in USB 2.0 mode.

## Audio latencies fluctuate heavily, how to fix them?

* Remove `sound` and `sound+microphone` from the VM configuration
* Rerun `./setup-vms.sh`
* Attach the PCI device hosting your sound hardware to the VM, as described in the previous section
* When the VM starts, use alsamixer to adjust the volume

**Note**: These steps are only necessary for low-latency audio work and are overkill for video calls
and voice-overs.

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
