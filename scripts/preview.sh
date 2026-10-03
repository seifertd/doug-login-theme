#!/usr/bin/env bash
# Preview the theme in an X11 window without rebooting.
#
# Simulates the boot: shows the splash, asks for a passphrase like
# systemd-cryptsetup does (re-asking on a wrong one), then reports the root
# filesystem as mounted, which is what commits the transaction.
#
#   PASS=...    passphrase the fake unlock accepts (default: btrfs)
#   PROMPT=...  prompt text Plymouth is given
#
# Needs sudo: plymouthd only runs as root and only loads themes from
# /usr/share/plymouth/themes. The preview copy is removed again on exit.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=btrfs-cow-preview
SRC=build/preview/$NAME
DEST=/usr/share/plymouth/themes/$NAME
PASS=${PASS:-btrfs}
PROMPT=${PROMPT:-"Please enter passphrase for disk Samsung SSD 970 EVO Plus 1TB (luks-fb1903f3-b4b0-4ab9-a4b6-7b2d339dbe99):"}
LOG=$PWD/build/preview.log

[[ -d $SRC ]] || { echo "run 'make' first" >&2; exit 1; }
[[ -n ${DISPLAY:-} ]] || { echo "needs an X11/XWayland DISPLAY" >&2; exit 1; }
if pgrep -x plymouthd >/dev/null; then echo "plymouthd is already running" >&2; exit 1; fi

sudo -v
XHOST=0
if command -v xhost >/dev/null; then xhost +si:localuser:root >/dev/null && XHOST=1; fi

cleanup() {
    sudo plymouth quit 2>/dev/null || true
    sleep 0.5
    sudo rm -rf "$DEST"
    [[ -f $LOG ]] && sudo chown "$(id -u):$(id -g)" "$LOG"
    if ((XHOST)); then xhost -si:localuser:root >/dev/null || true; fi
}
trap cleanup EXIT

sudo rm -rf "$DEST"
sudo cp -r "$SRC" "$DEST"
rm -f "$LOG"

# With DISPLAY set, plymouthd uses the x11 renderer instead of the real screen.
sudo env DISPLAY="$DISPLAY" XAUTHORITY="${XAUTHORITY:-}" \
    plymouthd --no-daemon --debug --debug-file="$LOG" --no-boot-log \
    --kernel-command-line="quiet splash plymouth.splash=$NAME" &
for _ in $(seq 50); do sudo plymouth --ping 2>/dev/null && break; sleep 0.1; done
sudo plymouth show-splash
sleep 2

echo "type the passphrase into the Plymouth window (accepted: '$PASS')"
for _ in 1 2 3; do
    answer=$(sudo plymouth ask-for-password --prompt="$PROMPT") || break
    sleep 1.5                       # cryptsetup's key derivation
    if [[ $answer == "$PASS" ]]; then
        sudo plymouth update-root-fs --new-root-dir=/   # -> root_mounted callback
        sleep 5
        break
    fi
done

if grep -q 'Execution error' "$LOG" 2>/dev/null || sudo grep -q 'Execution error' "$LOG" 2>/dev/null; then
    echo "script errors in $LOG:" >&2
    sudo grep 'Execution error' "$LOG" | sort | uniq -c >&2
fi
