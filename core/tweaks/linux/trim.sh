# Tells the virtual disk which blocks the guest has freed, so a saved layer holds only what is in use.
# timeout: 300
command -v fstrim >/dev/null || { echo "no fstrim" >&2; exit 1; }
sync
fstrim -av 2>/dev/null || fstrim -v /
