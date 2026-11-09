# `--provision nocloud` recipe

`NoCloud.swift` builds a FAT volume labeled `TERRARIUM` (the helper and `install.sh`) and a script of keys typed over VNC through the VM's `Plan.script`, as the Windows install does. It is for images with no cloud-init that ask their questions on the text console, as Debian's `nocloud` images do.

The times are blind and were measured on Debian 13 with 2 GiB and 2 CPUs: systemd's first-boot wizard waits for a key at about 30 s (the first key is typed at 45 s); it then asks for a timezone (skipped) and for root's password and its confirmation; the login prompt follows by about 20 s. The login and the install command are typed twice, 50 s apart: typed at a shell they do nothing harmful, and the second pair covers a slower boot. A faster Mac may need earlier times, and a slower one later; the helper answered 106 s after the start in the test.

The install script puts the helper in `/usr/local/bin` with a systemd unit, so a committed overlay (or any later boot) has the helper without `--provision`. A password given with `--password` is typed in the clear on the console; one the recipe makes is random, printed once by `start`, and kept in `vms/<id>/nocloud-password` until the VM stops. The wizard's questions differ by image, so this recipe fits only images that ask what Debian's does: another image needs its own measured script.
