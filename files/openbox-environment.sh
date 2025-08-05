export PS1='\W $ '
export FLATPAK_USER_DIR='/var/lib/user/flatpak'
test ! -e "$HOME/.local/bin" || export PATH="$PATH:$HOME/.local/bin"
test ! -e /var/lib/user/pip3-target ||
  export PATH="$PATH:/var/lib/user/pip3-target/bin" PYTHONPATH='/var/lib/user/pip3-target'
xrdb -merge "$HOME/.Xresources"
