# `--install alpine` recipe

`AlpineInstall.swift` builds the install's apkovl on a FAT volume (`--provision alpine`, in [Recipe.swift](../Recipe.swift), builds the live one). `install.start` (the `local.d` hook that runs `setup-alpine`) and `answers` (its answer file) are real files; `build.zig` embeds them in the `__TERRARIUM` section. Section names are at most 16 characters.

How the recipes work is in [core/README.md](../../README.md#recipes).
