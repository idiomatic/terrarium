# Starts DHCP on each wired NIC without an IPv4 address, as one on a named network needs; terrarium runs it at every start of a Linux guest with --network.
# timeout: 90
# The setup lives in /run or in a running client, so it does not persist; run again, it changes nothing that has an address.
status=0
for path in /sys/class/net/*; do
	nic=${path##*/}
	[ -e "$path/device" ] || continue
	ip -4 addr show dev "$nic" | grep -q ' inet ' && continue
	ip link set "$nic" up
	if command -v networkctl >/dev/null && systemctl is-active -q systemd-networkd 2>/dev/null; then
		mkdir -p /run/systemd/network
		printf '[Match]\nName=%s\n\n[Network]\nDHCP=yes\n' "$nic" > "/run/systemd/network/10-terrarium-$nic.network"
		networkctl reload && networkctl reconfigure "$nic"
	elif command -v nmcli >/dev/null && nmcli -t general status >/dev/null 2>&1; then
		nmcli device set "$nic" managed yes
		nmcli device connect "$nic"
	elif command -v udhcpc >/dev/null; then
		udhcpc -b -i "$nic" -p "/run/udhcpc.$nic.pid" >/dev/null 2>&1
	elif command -v dhcpcd >/dev/null; then
		dhcpcd -b "$nic"
	elif command -v dhclient >/dev/null; then
		dhclient -nw "$nic"
	else
		echo "$nic: no DHCP client (systemd-networkd, NetworkManager, udhcpc, dhcpcd, or dhclient)" >&2
		status=1
		continue
	fi
	tries=0
	until ip -4 addr show dev "$nic" | grep -q ' inet '; do
		tries=$((tries + 1))
		[ $tries -gt 60 ] && { echo "$nic: no DHCP lease after 60 s" >&2; status=1; break; }
		sleep 1
	done
	ip -4 addr show dev "$nic" | awk -v nic="$nic" '/ inet / { print nic, $2 }'
done
exit $status
