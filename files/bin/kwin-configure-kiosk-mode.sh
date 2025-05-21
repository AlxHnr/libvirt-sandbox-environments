#!/bin/sh -e

kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true
cat > "$HOME/.config/kwinrulesrc" <<'EOF'
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
