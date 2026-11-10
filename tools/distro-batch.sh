#!/bin/bash
# Pulls, boots, checks, and discards images from a list, several at a time, to turn ⬜ cells of docs/distros.md into tested ones.
# Usage: tools/distro-batch.sh LIST [OUTDIR]     LIST: lines of `MODE LABEL URL` (see distro-list.py), MODE one of:
#   cloud    --provision cloud-init, then `exec` as root answers         nocloud  --provision nocloud, the same
#   shot     boot as is, then a `shot` after SHOTWAIT seconds and 20 more (look at OUTDIR/shots/LABEL.b.png)
# Environment: TERRARIUM (default zig-out/bin/terrarium), SHOTWAIT (150), VMS (4 booted at once), HELD (6 images on disk at once),
# PULLS (2 downloads at once). Each VM is stopped and each image removed after its test. Results: OUTDIR/results.tsv
# (LABEL, OK|no-helper|shot|start-failed|pull-failed, detail), OUTDIR/shots/, OUTDIR/logs/. Needs the built terrarium.
here=$(cd "$(dirname "$0")" && pwd)
T=${TERRARIUM:-$here/../zig-out/bin/terrarium}
LIST=${1:?usage: distro-batch.sh LIST [OUTDIR]}
D=${2:-$(mktemp -d /tmp/distro-batch.XXXXXX)}
SHOTWAIT=${SHOTWAIT:-150}; VMS=${VMS:-4}; HELD=${HELD:-6}; PULLS=${PULLS:-2}
mkdir -p "$D"/{shots,logs,held,running,pulling,vmids}; rm -f "$D"/{held,running,pulling,vmids}/*
LINES=(); while IFS= read -r l; do [ -n "$l" ] && LINES+=("$l"); done < "$LIST"
N=${#LINES[@]}
echo "distro-batch: $N images, results in $D"
trap 'for f in "$D"/vmids/*; do [ -e "$f" ] && "$T" stop "$(basename "$f")" >/dev/null 2>&1; done' EXIT

record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$D/results.tsv"; }
count() { ls "$1" | wc -l | tr -d ' '; }

test_one() { # index name
  local i=$1 name=$2 mode label url id who info tries=40
  read -r mode label url <<<"${LINES[$i]}"
  case $mode in
    cloud)   id=$("$T" start "$name" --provision cloud-init --memory 2048 --cpus 2 2>"$D/logs/$label.start.err" | tail -1) ;;
    nocloud) id=$("$T" start "$name" --provision nocloud --memory 2048 --cpus 2 2>"$D/logs/$label.start.err" | tail -1); tries=60 ;;
    *)       id=$("$T" start "$name" --memory 4096 --cpus 4 2>"$D/logs/$label.start.err" | tail -1) ;;
  esac
  if [ -z "$id" ] || ! "$T" ps | grep -q "$id"; then
    record "$label" start-failed "$(tail -c 300 "$D/logs/$label.start.err" | tr '\n\t' '  ')"
  else
    touch "$D/vmids/$id"
    if [ "$mode" != shot ]; then
      for _ in $(seq 1 $tries); do
        if who=$(perl -e 'alarm 20; exec @ARGV' "$T" exec "$id" /bin/sh -c 'id -un' 2>/dev/null); then break; fi; who=""; sleep 5
      done
      if [ -n "$who" ]; then
        info=$(perl -e 'alarm 20; exec @ARGV' "$T" exec "$id" /bin/sh -c '. /etc/os-release; echo "$PRETTY_NAME"; uname -m' 2>&1 | tr '\n' ' ')
        record "$label" OK "$who | $info"
      else
        "$T" logs "$id" > "$D/logs/$label.console.log" 2>&1
        "$T" shot "$id" > "$D/shots/$label.png" 2>/dev/null
        record "$label" no-helper "console: $(tail -n 3 "$D/logs/$label.console.log" | tr '\n\t' '  ' | cut -c1-250)"
      fi
    else
      sleep "$SHOTWAIT"; "$T" shot "$id" > "$D/shots/$label.png" 2>/dev/null
      sleep 20;          "$T" shot "$id" > "$D/shots/$label.b.png" 2>/dev/null
      "$T" logs "$id" > "$D/logs/$label.console.log" 2>&1
      record "$label" shot "$(ls -l "$D/shots/$label.b.png" | awk '{print $5}') bytes"
    fi
    "$T" stop "$id" >/dev/null 2>&1; rm -f "$D/vmids/$id"
  fi
  "$T" rmi "$name" >/dev/null 2>&1
  rm -f "$D/running/$i" "$D/held/$i"
  echo "done $label $(date +%T) free: $(df -h / | tail -1 | awk '{print $4}')"
}

claim() { # a free test slot, taken atomically with a mkdir lock
  while true; do
    if mkdir "$D/lock" 2>/dev/null; then
      if [ "$(count "$D/running")" -lt "$VMS" ]; then touch "$D/running/$1"; rmdir "$D/lock"; return; fi
      rmdir "$D/lock"
    fi
    sleep 2
  done
}

pull_and_test() { # index
  local i=$1 mode label url name
  read -r mode label url <<<"${LINES[$i]}"
  name=$(perl -e 'alarm 1500; exec @ARGV' "$T" pull "$url" 2>"$D/logs/$label.pull.err" | tail -1)
  rm -f "$D/pulling/$i"
  if [ -z "$name" ]; then
    record "$label" pull-failed "$(tail -c 300 "$D/logs/$label.pull.err" | tr '\n\t' '  ')"
    rm -f "$D/held/$i"; return
  fi
  claim "$i"
  echo "=== [$i/$N] $label ($mode) $(date +%T)"
  test_one "$i" "$name"
}

for ((i=0; i<N; i++)); do
  while [ "$(count "$D/held")" -ge "$HELD" ] || [ "$(count "$D/pulling")" -ge "$PULLS" ]; do sleep 2; done
  touch "$D/held/$i" "$D/pulling/$i"
  pull_and_test "$i" &
done
wait
echo "=== all done: $D/results.tsv"
