#!/bin/sh -e

mkdir -p "$XDG_CONFIG_HOME/tint2/"
mkdir -p "$XDG_CONFIG_HOME/openbox/"
cp --update=none /usr/local/share/guest-home-files/Xresources "$HOME/.Xresources"
cp --update=none /usr/local/share/guest-home-files/tint2rc  "$XDG_CONFIG_HOME/tint2/"
cp --update=none /usr/local/share/guest-home-files/rc.xml   "$XDG_CONFIG_HOME/openbox/"
cp --update=none /usr/local/bin/openbox-custom-autostart.sh "$XDG_CONFIG_HOME/openbox/autostart.sh"
