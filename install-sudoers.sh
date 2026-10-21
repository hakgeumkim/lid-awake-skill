#!/bin/zsh
# Allow the current user to run exactly three pmset commands without a password.
# Run once with: sudo ./install-sudoers.sh
set -e
[[ $EUID -eq 0 ]] || { echo "run with sudo: sudo $0"; exit 1; }
USER_NAME="${SUDO_USER:?run with sudo, not as root directly}"
FILE=/etc/sudoers.d/lid-awake
TMP=$(mktemp)
cat > "$TMP" <<EOF
# LidAwake (~/Projects/lid-awake): toggle lid-closed sleep on power-source changes.
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset sleepnow
EOF
visudo -cf "$TMP"
install -m 0440 -o root -g wheel "$TMP" "$FILE"
rm -f "$TMP"
echo "installed $FILE"
