# Closes the Welcome to Ubuntu window of a live session, as it opens.
# timeout: 60
[ -d /snap/ubuntu-desktop-bootstrap ] || { echo "not an Ubuntu live session" >&2; exit 1; }
# The window can open after the helper answers; the bracket keeps the pattern from matching this script.
for _ in $(seq 50); do
    pkill -f "[u]buntu_bootstrap --try-or-install" && exit 0
    sleep 1
done
