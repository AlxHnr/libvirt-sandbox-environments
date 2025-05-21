#!/bin/sh -e
# Sends a graceful close signal to all open windows. Ignores special window types like docks,
# notification pop-ups, etc.

kwinCall()
(
  endpoint="$1"
  function="$2"
  shift 2

  dbus-send --print-reply --dest=org.kde.KWin "$endpoint" "org.kde.kwin.$function" "$@"
)

loadScript()
(
  script_path="$1"
  plugin_name="$2"

  kwinCall /Scripting Scripting.loadScript "string:$script_path" "string:$plugin_name" |
    tail -n 1 |
    grep -oE '\d+$'
)

script_path=$(mktemp "$XDG_RUNTIME_DIR/kwin-close-all-windows-XXXXXX.js")
trap 'rm "$script_path"' EXIT

cat > "$script_path" <<'EOF'
workspace.windowList().forEach(window => {
  if(window.normalWindow) {
    window.closeWindow();
  }
})
EOF

plugin_name=$(basename "$script_path")
script_id=$(loadScript "$script_path" "$plugin_name")
{
  kwinCall "/Scripting/Script$script_id" Script.run
  kwinCall "/Scripting/Script$script_id" Script.stop
  kwinCall "/Scripting" Scripting.unloadScript "string:$plugin_name"
} >/dev/null
