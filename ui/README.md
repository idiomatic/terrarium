# ui

`TerrariumUI`, in Swift over AppKit: the window `terrarium run` shows. It attaches to an `Owner` from [core](../core/README.md) through `OwnerUI`, which the owner calls on the main queue, and it acts on the owner through its public methods.

| File | Holds |
|---|---|
| `RunWindow.swift` | the window, its title, closing, and quitting |
| `RunMenus.swift` | the menus, the commit sheet, and Capture System Keys |
| `RunClipboard.swift` | Paste to Guest, Copy from Guest, and Share Clipboard |
| `RunScale.swift` | the scale steps and Match Guest to Window |
| `RunSize.swift` | the window's shape as the guest's display changes size |
| `ConsoleLog.swift` | the Console Log window |

`makeRunWindow` is what the executable gives `Backend.windowFactory`.

## Using the window

`terrarium run` shows the VM in this window and stays until you close it. [AGENTS.md](../AGENTS.md#run-window) holds the requirements.

* The title shows the VM's state. Closing the window stops the VM.
* *File* menu: *Commit…* and *Commit When VM Stops…* (what `terrarium commit` does), *Screenshot…*, *Reveal VM Folder*, and *Copy VM ID*.
* *Edit* menu: *Paste to Guest* (Command-V) and *Copy from Guest* (Command-C) move text between the host's pasteboard and the guest's clipboard; *Share Clipboard* (off by default) does it whenever the window gains or loses focus. Both need a running guest with a helper.
* *VM* menu: *Pause*; *Send Key*, for chords the host keeps, such as Ctrl+Alt+Delete or Cmd+Tab (Escape and the guest OS's own shortcuts, each named by its effect); and *Capture System Keys*, off by default so Cmd-Tab and screenshots stay yours (turn it on to give the guest every shortcut).
* *Window* menu: *Console Log*.
