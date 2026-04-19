#!/bin/sh -e

. /etc/profile
export PS1='\W $ '
export FLATPAK_USER_DIR="/var/lib/$USER/flatpak"
test ! -e "$HOME/.local/bin" || export PATH="$PATH:$HOME/.local/bin"
test ! -e "/var/lib/$USER/pip3-target" ||
  export PATH="$PATH:/var/lib/$USER/pip3-target/bin" PYTHONPATH="/var/lib/$USER/pip3-target"

if test ! -e /var/lib/user/emptty-started-after-install; then
  setup-custom-homedir.sh
  touch /var/lib/user/emptty-started-after-install
fi

xrdb -merge "$HOME/.Xresources" || true
exec /usr/bin/openbox-session
