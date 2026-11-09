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
