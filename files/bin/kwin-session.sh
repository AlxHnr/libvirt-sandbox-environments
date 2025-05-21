#!/bin/sh -e

. /etc/profile
export PS1='\W $ '
export FLATPAK_USER_DIR="/var/lib/$USER/flatpak"
test ! -e "$HOME/.local/bin" || export PATH="$PATH:$HOME/.local/bin"
test ! -e "/var/lib/$USER/pip3-target" ||
  export PATH="$PATH:/var/lib/$USER/pip3-target/bin" PYTHONPATH="/var/lib/$USER/pip3-target"
test -e "$XDG_CONFIG_HOME" || init-home-config-directory.sh

exec dbus-launch /usr/bin/kwin_wayland_wrapper \
  --no-lockscreen --no-kactivities --xwayland kwin-session-init.sh
