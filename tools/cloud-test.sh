#!/bin/bash
# Boots cloud images with --provision cloud-init and reports whether the helper answers, and as whom.
# Usage: tools/cloud-test.sh [< LIST]     LIST: lines of `LABEL URL`; the default is the list below.
# Needs a built `zig-out/bin/terrarium` (or TERRARIUM=PATH); pulls and boots each image, so it takes minutes each.
here=$(cd "$(dirname "$0")" && pwd)
T=${TERRARIUM:-$here/../zig-out/bin/terrarium}
out=$(mktemp)
trap 'rm -f "$out"' EXIT

default_list() {
  cat <<'EOF'
Ubuntu-24.04-cloud https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64.img
Debian-12-genericcloud https://cdimage.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2
Rocky-10-GenericCloud https://download.rockylinux.org/pub/rocky/10/images/aarch64/Rocky-10-GenericCloud-Base.latest.aarch64.qcow2
AlmaLinux-10-GenericCloud https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/AlmaLinux-10-GenericCloud-latest.aarch64.qcow2
CentOS-Stream-10-GenericCloud https://cloud.centos.org/centos/10-stream/aarch64/images/CentOS-Stream-GenericCloud-10-latest.aarch64.qcow2
openSUSE-Leap-16.1-Minimal-VM-Cloud https://download.opensuse.org/distribution/leap/16.1/appliances/Leap-16.1-Minimal-VM.aarch64-Cloud.qcow2
EOF
}

if [ -t 0 ]; then list=$(default_list); else list=$(cat); fi

while read -r label url; do
  [ -z "$label" ] && continue
  echo "=== $label"
  # A pull that stalls is killed after seven minutes.
  name=$(perl -e 'alarm 420; exec @ARGV' "$T" pull "$url" 2>&1 | tail -1)
  echo "stored: $name"
  id=$("$T" start "$name" --provision cloud-init --memory 2048 --cpus 2 2>&1 | tail -1)
  echo "vm: $id"
  ok=no
  for _ in $(seq 1 40); do
    if "$T" exec "$id" /usr/bin/id -un >"$out" 2>/dev/null; then ok=yes; break; fi
    sleep 5
  done
  echo "helper answered: $ok ($(tr -d '\n' <"$out"))"
  if [ "$ok" = yes ]; then
    "$T" exec "$id" /bin/sh -c '. /etc/os-release; echo "$PRETTY_NAME"; uname -m' 2>&1
    "$T" exec "$id" /bin/sh -c 'systemctl is-active terrarium-helper 2>/dev/null || rc-service terrarium-helper status 2>/dev/null' 2>&1
  fi
  "$T" stop "$id" >/dev/null 2>&1
done <<EOF
$list
EOF
echo "=== all done"
