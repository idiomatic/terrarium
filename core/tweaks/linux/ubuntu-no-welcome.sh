# Closes the Welcome to Ubuntu window of a live session, waiting up to 50 s for it to open and failing if it does not, unless this tweak closed it since the guest booted; refused without the `ubuntu-desktop-bootstrap` snap.
# timeout: 60
[ -d /snap/ubuntu-desktop-bootstrap ] || { echo "not an Ubuntu live session" >&2; exit 1; }
# A mark in /run, which a reboot clears as it reopens the window, lets the tweak run again.
mark=/run/terrarium-ubuntu-no-welcome
# The window can open after the helper answers; the bracket keeps the pattern from matching this script.
for _ in $(seq 50); do
    pkill -f "[u]buntu_bootstrap --try-or-install" && { touch "$mark"; exit 0; }
    [ -e "$mark" ] && { echo "already closed"; exit 0; }
    sleep 1
done
echo "the Welcome to Ubuntu window did not open within 50 s" >&2
exit 1
