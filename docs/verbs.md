# Verbs

Each verb is a `terrarium` subcommand and an MCP tool of the same name and parameters, except `run` (CLI only). [AGENTS.md](../AGENTS.md#verbs) holds the requirements, with every verb's arguments and options. `terrarium help` lists the verbs from the code, and `terrarium help VERB` shows a verb's arguments and options. On Linux, the clipboard needs `wl-clipboard` or `xclip` and a graphical session the root helper can reach; on most desktops it cannot, and `clipboard set` types the text instead. This page adds examples and advice.

A verb that acts on a running VM takes it first, as `VM`: its ID (which `start` prints and `ps` lists) or a unique prefix of it. The examples use `$id` for it.

## Images

```
terrarium pull https://example.com/alpine-virt.iso
terrarium images
terrarium rmi alpine-virt
```

An image is named by its name without the hash when only one image has that name, else `<name>-<hash>`, or a unique prefix of that.

`pull` converts qcow2 images (version 2 or 3, with plain or zlib-compressed clusters) to raw disks, and extracts the disk image from a tar archive that holds just one file (a `.tar.gz` of `disk.raw`, say). It cannot read qcow2 images with a backing file, encryption, or zstd compression, or choose among the files of a larger archive.

## Lifecycle

```
terrarium start alpine-virt --provision alpine \
  --tweak linux/no-blank --save alpine
terrarium run alpine
terrarium run alpine --clone alpine2
terrarium run alpine2 --continue
id=$(terrarium start alpine --ephemeral)
terrarium commit $id snapshot
terrarium stop $id
```

`start` needs to know what becomes of the VM's work (`--ephemeral`, `--save`, `--clone`, or `--continue`); [Layers](layers.md) explains the four, and `commit` takes the same words for a running VM.

## Layers

```
terrarium layers
terrarium squash experiment experiment-flat
terrarium rm experiment
```

[Layers](layers.md) explains saving, naming, sharing, and squashing them. `rm` leaves the layers made from the removed one whole, since each holds its own clones of its ancestors' files.

## Observe and control

```
terrarium shot $id > screen.png
terrarium click $id 640,400
terrarium type $id "hello"
terrarium key $id ctrl+alt+delete
terrarium exec $id uname -a
echo hi | terrarium clipboard $id set -
terrarium wait $id
terrarium exec $id poweroff; terrarium wait $id --down
terrarium wait $id; terrarium exec $id reboot; terrarium wait $id --reboot
terrarium put $id ~/src/app /home/debian/app
terrarium get $id /home/debian/app/out.log ~/Downloads
```

`wait`, then `exec reboot`, then `wait --reboot` cannot miss a fast restart: with no earlier `wait`, the first instance ID `wait --reboot` sees is its baseline.

### Recording

```
terrarium record $id ~/Movies/demo.mp4 --clicks
terrarium click $id 640,400 --duration 500
terrarium type $id "hello, world" --interval 90
terrarium click $id 640,400 --drag-to 900,500 --duration 800
terrarium record $id --stop
```

`record` writes an H.264 video of the screen until `record --stop`, `--max-seconds` (ten minutes by default), or the VM stops. Frames come only when the screen changes, at most `--fps` a second (10 by default), so a still screen costs nothing and plays as a held frame. Windows draws its own pointer into the screen; for macOS, which does not, terrarium draws one where it last put the pointer. `--clicks` marks each click terrarium sends with a dot and a ring (amber for the left button, blue for the right, purple for the middle; a drag's release gets the ring alone), and `--crop X,Y,W,H` keeps part of the screen (above Windows' taskbar, say). It records no sound, and needs no permission on the Mac. For a recording that looks like a person at work, `type --interval MS` types a character at a time, `move --duration MS` and `click --duration MS` glide the pointer rather than jump it, and `click --drag-to X,Y --duration MS` drags at that pace. Clicks and pointer moves made by hand in a `run` window are not drawn.

A command that outlasts a client's patience should not run under `exec`. A Linux or macOS guest takes it detached, with its output in a file (`terrarium exec $id sh -c 'setsid sh -c "make > /tmp/build.log 2>&1" </dev/null >/dev/null 2>&1 &'`), which `terrarium get $id /tmp/build.log .` or a short `exec` reads later. `exec` kills what it started, its process group (a job object on Windows), when its connection ends, and `setsid` leaves the group.

## MCP

`terrarium mcp` serves the verbs as MCP tools; [Use it from an agent](mcp.md) shows how to configure a client, and [AGENTS.md](../AGENTS.md#mcp) says what the server does.
