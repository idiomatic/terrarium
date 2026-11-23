# Tells the virtual disk which blocks the guest has freed (`fstrim -av`, or `fstrim -v /` where that fails, as with BusyBox), so a layer saved after it holds only what is in use; refused without `fstrim`.
# timeout: 300
command -v fstrim >/dev/null || { echo "no fstrim" >&2; exit 1; }
sync
fstrim -av 2>/dev/null || fstrim -v /
