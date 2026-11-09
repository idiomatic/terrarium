# Specifications

External specifications terrarium relies on. Collected files sit beside this index; the rest are links.

## Collected

* [rfc6143-rfb.txt](rfc6143-rfb.txt): *The Remote Framebuffer Protocol* (RFC 6143), <https://www.rfc-editor.org/rfc/rfc6143.txt>. `shot`, `click`, `type`, and `key` speak RFB to the VNC server of Virtualization.framework.
* [UEFI_Spec_Final_2.11.pdf](UEFI_Spec_Final_2.11.pdf): *UEFI Specification 2.11*, <https://uefi.org/sites/default/files/resources/UEFI_Spec_Final_2.11.pdf>. EFI guests, the Windows framebuffer loader (GOP, Boot Services, device paths).
* [virtio-v1.3.pdf](virtio-v1.3.pdf): *Virtual I/O Device (VIRTIO) Version 1.3*, <https://docs.oasis-open.org/virtio/virtio/v1.3/virtio-v1.3.pdf>. Block, network, socket (vsock), GPU, and file-system devices that guests see.
* [qcow2.rst](qcow2.rst): *Qcow2 Image File Format*, <https://gitlab.com/qemu-project/qemu/-/raw/master/docs/interop/qcow2.rst>. `pull` converts qcow2 images (Fedora's cloud image) to raw disks in [Qcow2.swift](../../core/images/Qcow2.swift).
* [mcp-2026-07-28/](mcp-2026-07-28/): *Model Context Protocol, specification 2026-07-28* (the `.mdx` pages, `schema.json`, and `schema.ts`), <https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/docs/specification/2026-07-28>. The stdio MCP server; start at [basic/transports/stdio.mdx](mcp-2026-07-28/basic/transports/stdio.mdx) and [server/tools.mdx](mcp-2026-07-28/server/tools.mdx).

## Linked

### Apple

* *Virtualization*, <https://developer.apple.com/documentation/virtualization>. The host framework: VMs, devices, `VZMacGuestProvisioningOptions`, `VZVirtioSocketDevice`, EFI boot.
* *DiskImageKit*, <https://developer.apple.com/documentation/diskimagekit>. Per-VM overlays (stacked ASIF layers).
* `sys/vsock.h` in the macOS SDK (`$(xcrun --show-sdk-path)/usr/include/sys/vsock.h`). `AF_VSOCK` for the guest helper's listener.

### Windows

* *Windows Setup Automation Overview*, <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview>, and *Automate Windows Setup*, <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup>. Answer files (`autounattend.xml`) for unattended installs.
* *Add a Custom Script to Windows Setup*, <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup>. `SetupComplete.cmd`, where the helper is installed.
* *Windows PE Introduction*, <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-intro>. The environment the installer runs in.
* *DISM Image Management Command-Line Options*, <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-image-management-command-line-options-s14>. Applying `install.wim` and adding drivers.
* *BCDBoot Command-Line Options*, <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/bcdboot-command-line-options-techref-di>. Boot files for an applied image.
* *DiskPart*, <https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/diskpart>. Partitioning the target disk.
* *virtio-win*, <https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md>; ISO at <https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso> (877 MB, a download and not a specification). Windows drivers for the virtio devices.
* *Running Windows 11 and Server 2025 with macOS Virtualization.framework*, <https://mustafaakin.dev/blog/windows-on-tart/>. The private-API and framebuffer findings summarized in [windows.md](../windows.md); reimplemented from, not copied.
* *Tart*, <https://tart.run>. Prior art for the VNC server and Windows guests; its license is nonstandard, so nothing is copied.

### Linux recipes

* *cloud-init NoCloud datasource*, <https://docs.cloud-init.io/en/latest/reference/datasources/nocloud.html>. The `cidata` volume of the `cloud-init` recipe.
* *Alpine local backup (apkovl)*, <https://wiki.alpinelinux.org/wiki/Alpine_local_backup>, and *Alpine setup scripts*, <https://wiki.alpinelinux.org/wiki/Alpine_setup_scripts>. The `--provision alpine` and `--install alpine` recipes.
* *OpenRC service script guide*, <https://github.com/OpenRC/openrc/blob/master/service-script-guide.md>. The helper's launch hook on Alpine.

### Language

* *Zig documentation*, <https://ziglang.org/documentation/master/>. The guest helper (Zig 0.17+) and the UEFI loader (`std.os.uefi`).
