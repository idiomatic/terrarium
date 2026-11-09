# `--provision combustion` recipe

`Combustion.swift` builds a FAT volume labeled `COMBUSTION` holding `combustion/script` and `combustion/terrarium-helper`. openSUSE's Minimal-VM, MicroOS, and Leap Micro images run [Combustion](https://github.com/openSUSE/combustion) in the initrd at their first boot: it looks for a volume labeled `combustion`, `COMBUSTION`, `ignition`, or `IGNITION` (a FAT label is upper case), copies its `combustion` directory, and runs `script` from inside it, so the helper is found beside the script. The script installs the helper in `/usr/local/bin` with a systemd unit and enables it.

It runs once, at the first boot of an image, so a guest saved after it has the helper and needs no `--provision` again.
