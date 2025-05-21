#!/bin/sh -e

setupKioskMode()
(
  kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true
  cat > "$XDG_CONFIG_HOME/kwinrulesrc" <<'EOF'
[General]
count=1
rules=kiosk-mode

[kiosk-mode]
Description=Kiosk Mode
maximizehoriz=true
maximizehorizrule=3
maximizevert=true
maximizevertrule=3
types=1
EOF
)

kwriteconfig6 --file kxkbrc --group Layout --key LayoutList us
kwriteconfig6 --file kwinrc --group Plugins --key screenedgeEnabled false
kwriteconfig6 --file kdeglobals --group WM --key activeForeground 255,255,255
kwriteconfig6 --file kdeglobals --group WM --key activeBackground COLOR_PLACEHOLDER_DEC
#KIOSK: setupKioskMode

mkdir -p "$XDG_CONFIG_HOME/foot"
cat > "$XDG_CONFIG_HOME/foot/foot.ini" <<'EOF'
font=monospace:size=11

[scrollback]
lines=10000

[mouse]
hide-when-typing=yes
EOF
