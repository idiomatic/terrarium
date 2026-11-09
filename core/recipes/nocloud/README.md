# `--provision nocloud` recipe

`NoCloud.swift` builds a FAT volume labeled `TERRARIUM` (the helper and `install.sh`) and a dialogue (`Plan.expect`) that the owner plays over VNC. It is for images with no cloud-init that ask their questions on the text console, as Debian's `nocloud` images do.

The dialogue is read from the screen, not timed. Every two seconds the owner takes a frame and reads its text with Vision (`core/display/ScreenText.swift`). The next answer is typed once its prompt shows: systemd's "Press any key" screen (optional: Debian 14's wizard starts at the timezone), the timezone (skipped with Return), root's password and its confirmation, the login (`root` and the password), and the command that mounts the volume and runs `install.sh`. A bitmap console font is read with mistakes ("Passuord: -"), so a prompt matches ignoring case and spacing and may differ in a character (two, in a phrase of 12 or more). The console log of these images is empty, so it cannot serve; seven minutes without the next prompt end the dialogue, with a note.

The install script puts the helper in `/usr/local/bin` with a systemd unit, so a committed overlay (or any later boot) has the helper without `--provision`. A password given with `--password` is typed in the clear on the console; one the recipe makes is random, printed once by `start`, and kept in `vms/<id>/nocloud-password` until the VM stops.

On a Mac with other VMs busy the guests can misbehave (kernel oopses were seen with six VMs and swap in use), so test it alone. The helper answered about 100 s after the start on a quiet Mac, for Debian 13 and Debian 14. Another image that asks different questions needs a dialogue of its own.
