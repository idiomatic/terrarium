# Scales GNOME's display to 2x with `gdctl` (GNOME 48 or later), at once and kept for the display's current mode, waiting up to 90 s for a session (not the login screen's); does nothing without GNOME; terrarium runs it at every start of a Linux guest with `--retina`.
# timeout: 120
# It sets the scale for the display's current mode and keeps it (gdctl --persistent), so a 1280x800 display stays at 1x.
command -v gdctl >/dev/null || { echo "no gdctl (GNOME 48 or later): nothing to scale"; exit 0; }
tries=0
while :; do
	for bus in /run/user/*/bus; do
		[ -S "$bus" ] || continue
		uid=${bus#/run/user/}; uid=${uid%/bus}
		user=$(id -nu "$uid" 2>/dev/null) || continue
		# Not the login screen's greeter: a system user, or GDM's own.
		[ "$uid" -ge 1000 ] 2>/dev/null || continue
		case $user in gdm | gdm-* | Debian-gdm) continue ;; esac
		as() { runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" XDG_RUNTIME_DIR="/run/user/$uid" "$@"; }
		monitor=$(as gdctl show 2>/dev/null | sed -n 's/^.*Monitor \([^ ]*\) .*$/\1/p' | head -n 1)
		[ -n "$monitor" ] || continue
		as gdctl set --persistent --logical-monitor --primary --scale 2 --monitor "$monitor" || exit 1
		echo "$user: $monitor at 2x"
		exit 0
	done
	tries=$((tries + 1))
	[ $tries -ge 90 ] && { echo "no GNOME session within 90 s: nothing to scale"; exit 0; }
	sleep 1
done
