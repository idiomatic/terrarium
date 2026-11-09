const std = @import("std");
const uefi = std.os.uefi;
const Gop = uefi.protocol.GraphicsOutput;
const BS = uefi.tables.BootServices;
const cc = std.builtin.CallingConvention.c;

var gop0: *Gop = undefined;
var fb: [*]u8 = undefined;
var width: usize = 0;
var height: usize = 0;
var real_exit: *const fn (uefi.Handle, uefi.tables.MemoryMapKey) callconv(cc) uefi.Status = undefined;
var pages: []align(4096) uefi.Page = &.{};

/// What each GOP's mode said before the shim changed it, to put back if the loaded image returns.
const Saved = struct {
    gop: *Gop,
    pixel_format: Gop.PixelFormat,
    pixels_per_scan_line: u32,
    frame_buffer_base: u64,
    frame_buffer_size: usize,
};
var saved: [8]Saved = undefined;
var saved_count: usize = 0;

fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    var w: [512:0]u16 = undefined;
    var n: usize = 0;
    for (s) |c| {
        if (c == '\n') {
            w[n] = '\r';
            n += 1;
        }
        w[n] = c;
        n += 1;
    }
    w[n] = 0;
    _ = uefi.system_table.con_out.?.outputString(@ptrCast(&w)) catch {};
}

/// The one refresh: the last picture before the OS takes the display.
fn hookExit(h: uefi.Handle, key: uefi.tables.MemoryMapKey) callconv(cc) uefi.Status {
    _ = gop0._blt(gop0, @ptrCast(fb), .blt_buffer_to_video, 0, 0, 0, 0, width, height, width * 4);
    return real_exit(h, key);
}

/// Gives every GOP a linear BGRX framebuffer in runtime memory (the firmware's is blit-only).
fn installFramebuffer(bs: *BS, gops: []*Gop) !void {
    gop0 = gops[0];
    width = gop0.mode.info.horizontal_resolution;
    height = gop0.mode.info.vertical_resolution;
    const bytes = width * height * 4;
    pages = try bs.allocatePages(.any, .runtime_services_data, (bytes + 4095) / 4096);
    fb = @ptrCast(pages.ptr);
    @memset(fb[0..bytes], 0);
    for (gops) |g| {
        saved[saved_count] = .{
            .gop = g,
            .pixel_format = g.mode.info.pixel_format,
            .pixels_per_scan_line = g.mode.info.pixels_per_scan_line,
            .frame_buffer_base = g.mode.frame_buffer_base,
            .frame_buffer_size = g.mode.frame_buffer_size,
        };
        saved_count += 1;
        g.mode.info.pixel_format = .blue_green_red_reserved_8_bit_per_color;
        g.mode.info.pixels_per_scan_line = @intCast(width);
        g.mode.frame_buffer_base = @intFromPtr(fb);
        g.mode.frame_buffer_size = bytes;
    }
    real_exit = bs._exitBootServices;
    bs._exitBootServices = hookExit;
    updateCrc(bs);
}

/// Puts back what `installFramebuffer` changed, for when the loaded image returns: the firmware unloads the shim then, and
/// a hook left behind would run freed code at the next boot option's ExitBootServices.
fn removeFramebuffer(bs: *BS) void {
    bs._exitBootServices = real_exit;
    updateCrc(bs);
    for (saved[0..saved_count]) |s| {
        s.gop.mode.info.pixel_format = s.pixel_format;
        s.gop.mode.info.pixels_per_scan_line = s.pixels_per_scan_line;
        s.gop.mode.frame_buffer_base = s.frame_buffer_base;
        s.gop.mode.frame_buffer_size = s.frame_buffer_size;
    }
    bs.freePages(pages) catch {};
}

/// A changed table must carry its new CRC32, computed with the field itself zero.
fn updateCrc(bs: *BS) void {
    bs.hdr.crc32 = 0;
    const bytes: [*]const u8 = @ptrCast(bs);
    bs.hdr.crc32 = bs.calculateCrc32(bytes[0..bs.hdr.header_size]) catch 0;
}

const media_path = std.unicode.utf8ToUtf16LeStringLiteral("\\EFI\\BOOT\\BOOTAA64.EFI");
const windows_path = std.unicode.utf8ToUtf16LeStringLiteral("\\EFI\\Microsoft\\Boot\\bootmgfw.efi");

/// Starts `path` from the file system on `h` if it has one; returns whether an image was started.
fn start(bs: *BS, h: uefi.Handle, path: [*:0]const u16) bool {
    const sfs = (bs.handleProtocol(uefi.protocol.SimpleFileSystem, h) catch return false) orelse return false;
    const root = sfs.openVolume() catch return false;
    const f = root.open(path, .read, .{}) catch return false;
    f.close() catch {};
    const dp = (bs.handleProtocol(uefi.protocol.DevicePath, h) catch return false) orelse return false;
    const len = std.mem.len(path);
    const full = dp.createFileDevicePath(uefi.pool_allocator, path[0..len]) catch return false;
    const img = bs.loadImage(false, uefi.handle, .{ .device_path = full }) catch return false;
    _ = bs.startImage(img) catch |e| say("startImage: {s}\n", .{@errorName(e)});
    return true;
}

/// Installer media first (\EFI\BOOT\BOOTAA64.EFI on another volume), else the Windows Boot Manager on this image's own volume.
fn chainload(bs: *BS) void {
    const me = (bs.handleProtocol(uefi.protocol.LoadedImage, uefi.handle) catch return) orelse return;
    const handles = (bs.locateHandleBuffer(.{ .by_protocol = &uefi.protocol.SimpleFileSystem.guid }) catch return) orelse return;
    for (handles) |h| {
        if (h == me.device_handle) continue;
        if (start(bs, h, media_path)) return;
    }
    if (me.device_handle) |own| if (start(bs, own, windows_path)) return;
    say("nothing to boot\n", .{});
}

pub fn main() void {
    const bs = uefi.system_table.boot_services.?;
    const handles = (bs.locateHandleBuffer(.{ .by_protocol = &Gop.guid }) catch return) orelse return;
    var list: [8]*Gop = undefined;
    var n: usize = 0;
    for (handles) |h| {
        const g = (bs.handleProtocol(Gop, h) catch continue) orelse continue;
        if (n < list.len) {
            list[n] = g;
            n += 1;
        }
    }
    if (n == 0) return;
    installFramebuffer(bs, list[0..n]) catch return;
    chainload(bs);
    // Only reached when the loaded image returned, or there was nothing to start.
    removeFramebuffer(bs);
}
