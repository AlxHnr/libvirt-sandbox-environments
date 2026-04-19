#!/bin/sh -e

copyIfNonExisting()
(
  src="$1"
  dst="$2"

  if test ! -e "$dst"; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
)

copyIfNonExisting /usr/local/share/guest-home-files/Xresources "$HOME/.Xresources"
copyIfNonExisting /usr/local/share/guest-home-files/tint2rc  "$XDG_CONFIG_HOME/tint2/tint2rc"
copyIfNonExisting /usr/local/share/guest-home-files/rc.xml   "$XDG_CONFIG_HOME/openbox/rc.xml"
copyIfNonExisting /usr/local/bin/openbox-custom-autostart.sh "$XDG_CONFIG_HOME/openbox/autostart.sh"
