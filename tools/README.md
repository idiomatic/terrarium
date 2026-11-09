# tools

Maintenance scripts. They are not part of the build or the test suite, and they need only stock macOS programs (`python3`, `curl`, `perl`, and `bash`).

| Tool | What it does |
|---|---|
| `distros.py [OUTPUT [TEMPLATE]]` | Writes [docs/distros.md](../docs/distros.md) from `distros.template.md` (the prose and footnotes), `distros.py` (the popularity ranking, test results, and column groups), and `distros_more.py` (the image URLs). It `HEAD`-checks every image URL and lists any that fail, writing none of them. |
| `distro-list.py [OPTIONS]` | Prints the untested (⬜) cells of docs/distros.md as a batch list (`MODE LABEL URL`), skipping the DVDs, the images known not to work, and anything over `--max-gb`. |
| `distro-batch.sh LIST [OUTDIR]` | Pulls, boots, checks, and discards the images of a list, four VMs at a time with at most six images on disk, and writes `results.tsv`, screenshots, and logs to OUTDIR. |
| `check-urls.sh < URLS` | Prints the final HTTP status of each URL on standard input. |
| `cloud-test.sh [< LIST]` | Pulls cloud images, boots each with `--provision cloud-init`, and reports whether the helper answers and as whom. It uses the built `zig-out/bin/terrarium`, and takes minutes per image. |

## Updating distros.md

Edit it through the template and the data, never by hand; the next run overwrites it. Roughly, in this order:

1. Refresh the URLs in `distros.py` and `distros_more.py`: release numbers and dated names (Fedora Rawhide, Kali weekly, Gentoo, FreeBSD, Debian point releases). To read DistroWatch's [Page Hit Ranking](https://distrowatch.com/dwres.php?resource=popularity) again, update `RANKED` and `RANK_DATE`. A column's 🟩, 🟧, or 🟫 comes from `GROUP`.
2. Run `python3 distros.py`, fix any dead URLs it lists, and rerun until none fail.
3. Test the new ⬜ cells (see [Testing](#testing)).
4. Record each result in `TESTED`, `TESTED_BAD`, `TESTED_FLAT`, or `BAD_FLAT`, and say what ran in the template's footnote.
5. Regenerate, check the diff, and fix any prose in the template that the results make stale. Do this soon after testing: dated URLs go stale within days.

## Testing

The goal is to turn ⬜ cells into tested ones, honestly. `cloud-test.sh` covers cloud images; for a long run use `distro-list.py` and `distro-batch.sh`, which pull ahead, boot several VMs, and remove each image after use. View each `shot` result yourself: a black or half-drawn screen is a failure, and the batch only records that a screenshot was taken.

Rules:

* Run `terrarium ps` first and pass `--vm ID` always: the user may have windowed VMs. Stop only your own, and end with a clean `ps`.
* Order by popularity and cost: cloud images first, then small ISOs. Skip the 10 to 14 GB DVD ISOs and the macOS IPSWs unless asked. Remove only the images you pulled.
* Never pass `--accept-license` unasked. Windows needs an ISO the user saves. Commit nothing unless asked.
* After code changes, rebuild and restart the VMs: the owner process parses chords.
* Record bugs found; do not work around them silently. Known: `pull` once stalled for 7+ minutes with no partial file (did not recur); `key print` cannot reach the guest (the VNC keyboard is Mac-style).

The bar:

* ✅ for a cloud image: `--provision cloud-init`, then `exec` answers as root. For an ISO: it boots to its installer or desktop, seen with `shot` and `key`.
* ❌ when it does not work, with the cause in the footnote. Likely: `nocloud`, Tiny Cloud, Ignition-based images, and Ubuntu Core.
* "Expected to work" stays ⬜. The footnote says exactly what ran.

Pitfalls that look like failures:

* `start` returns when the VM runs, not when the helper answers: poll `exec` (40 tries at 5 s).
* Headless cloud images have no graphical console, so a black `shot` is normal; use `exec`.
* Live desktops are slow: Ubuntu's *Welcome* window appears about 100 s in. Look with `shot` before clicking, and run a `shot` and the read of its file in sequence, not in parallel.
* `exec` runs no shell: use `/bin/sh -c`. Alpine's `id` is `/usr/bin/id`. `pkill -f PATTERN` inside `exec` kills your own `sh`; write `[u]buntu`.
* `osascript` in a macOS guest raises a permission prompt that blocks it until answered.
* Quote URLs containing `?` (zsh globbing).
