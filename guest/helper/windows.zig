//! The guest helper for Windows: the frame protocol of `protocol.zig`, over the `viosock` Winsock provider.
//!
//! The driver registers an address family at install time; it is not a fixed number, so it is asked for
//! through `\\.\Viosock`. Output pumping uses one thread per pipe and a thread watching for the host to hang up,
//! because Windows has no `poll` for pipes and sockets together.

const std = @import("std");
const protocol = @import("protocol.zig");

const winapi: std.builtin.CallingConvention = .winapi;
const Socket = usize;
const invalid_socket: Socket = ~@as(usize, 0);

const WSADATA = extern struct { bytes: [512]u8 = undefined };
const SockaddrVm = extern struct { family: u16, reserved1: u16 = 0, port: u32, cid: u32 };

extern "ws2_32" fn WSAStartup(version: u16, data: *WSADATA) callconv(winapi) c_int;
extern "ws2_32" fn socket(af: c_int, kind: c_int, protocol: c_int) callconv(winapi) Socket;
extern "ws2_32" fn bind(s: Socket, name: *const anyopaque, length: c_int) callconv(winapi) c_int;
extern "ws2_32" fn listen(s: Socket, backlog: c_int) callconv(winapi) c_int;
extern "ws2_32" fn accept(s: Socket, address: ?*anyopaque, length: ?*c_int) callconv(winapi) Socket;
extern "ws2_32" fn recv(s: Socket, buffer: [*]u8, length: c_int, flags: c_int) callconv(winapi) c_int;
extern "ws2_32" fn send(s: Socket, buffer: [*]const u8, length: c_int, flags: c_int) callconv(winapi) c_int;
extern "ws2_32" fn closesocket(s: Socket) callconv(winapi) c_int;

extern "kernel32" fn CreateFileW(name: [*:0]const u16, access: u32, share: u32, security: ?*anyopaque, creation: u32, flags: u32, template: ?*anyopaque) callconv(winapi) ?*anyopaque;
extern "kernel32" fn DeviceIoControl(handle: ?*anyopaque, code: u32, in: ?*anyopaque, in_size: u32, out: ?*anyopaque, out_size: u32, returned: *u32, overlapped: ?*anyopaque) callconv(winapi) c_int;
extern "kernel32" fn CloseHandle(handle: ?*anyopaque) callconv(winapi) c_int;
extern "kernel32" fn TerminateProcess(handle: ?*anyopaque, code: u32) callconv(winapi) c_int;
extern "kernel32" fn Sleep(milliseconds: u32) callconv(winapi) void;
extern "kernel32" fn WaitForSingleObject(handle: ?*anyopaque, milliseconds: u32) callconv(winapi) u32;
extern "kernel32" fn GetExitCodeProcess(handle: ?*anyopaque, code: *u32) callconv(winapi) c_int;
extern "kernel32" fn CreateJobObjectW(security: ?*anyopaque, name: ?[*:0]const u16) callconv(winapi) ?*anyopaque;
extern "kernel32" fn AssignProcessToJobObject(job: ?*anyopaque, process: ?*anyopaque) callconv(winapi) c_int;
extern "kernel32" fn TerminateJobObject(job: ?*anyopaque, code: u32) callconv(winapi) c_int;
extern "kernel32" fn ResumeThread(thread: ?*anyopaque) callconv(winapi) u32;
extern "kernel32" fn PeekNamedPipe(pipe: ?*anyopaque, buffer: ?*anyopaque, size: u32, read: ?*u32, available: ?*u32, left: ?*u32) callconv(winapi) c_int;
extern "kernel32" fn FreeConsole() callconv(winapi) c_int;
extern "kernel32" fn GlobalAlloc(flags: u32, bytes: usize) callconv(winapi) ?*anyopaque;
extern "kernel32" fn GlobalFree(handle: ?*anyopaque) callconv(winapi) ?*anyopaque;
extern "kernel32" fn GlobalLock(handle: ?*anyopaque) callconv(winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(handle: ?*anyopaque) callconv(winapi) c_int;
extern "user32" fn CreateWindowExW(ex_style: u32, class: [*:0]const u16, name: ?[*:0]const u16, style: u32, x: c_int, y: c_int, w: c_int, h: c_int, parent: ?*anyopaque, menu: ?*anyopaque, instance: ?*anyopaque, param: ?*anyopaque) callconv(winapi) ?*anyopaque;
extern "user32" fn DestroyWindow(window: ?*anyopaque) callconv(winapi) c_int;
extern "user32" fn OpenClipboard(owner: ?*anyopaque) callconv(winapi) c_int;
extern "user32" fn CloseClipboard() callconv(winapi) c_int;
extern "user32" fn EmptyClipboard() callconv(winapi) c_int;
extern "user32" fn GetClipboardData(format: u32) callconv(winapi) ?*anyopaque;
extern "user32" fn SetClipboardData(format: u32, handle: ?*anyopaque) callconv(winapi) ?*anyopaque;
extern "kernel32" fn GetTickCount64() callconv(winapi) u64;

const ioctl_get_af = 0x0801300C;
const sock_stream = 1;

/// The address family the `viosock` driver registered, or null while the driver is not ready.
fn vsockFamily() ?u16 {
    const device = std.unicode.utf8ToUtf16LeStringLiteral("\\\\.\\Viosock");
    const handle = CreateFileW(device, 0x80000000, 1, null, 3, 0x80, null);
    if (handle == null or @intFromPtr(handle) == ~@as(usize, 0)) return null;
    defer _ = CloseHandle(handle);
    var family: u32 = 0;
    var returned: u32 = 0;
    if (DeviceIoControl(handle, ioctl_get_af, null, 0, &family, @sizeOf(u32), &returned, null) == 0) return null;
    return if (family == 0) null else @intCast(family);
}

pub fn main(init: std.process.Init) !void {
    // Started at logon, in the user's session, the helper would otherwise leave a console window on the desktop.
    _ = FreeConsole();
    var data = WSADATA{};
    if (WSAStartup(0x0202, &data) != 0) fatal(init.io, "WSAStartup failed");

    // The driver may still be loading at boot; wait for it.
    const family = while (true) {
        if (vsockFamily()) |f| break f;
        Sleep(2000);
    };
    const listener = while (true) {
        const s = socket(family, sock_stream, 0);
        if (s != invalid_socket) break s;
        Sleep(2000);
    };
    const address = SockaddrVm{ .family = family, .port = protocol.port, .cid = protocol.any_cid };
    if (bind(listener, &address, @sizeOf(SockaddrVm)) != 0) fatal(init.io, "cannot bind the vsock port");
    if (listen(listener, 16) != 0) fatal(init.io, "cannot listen on the vsock port");

    while (true) {
        const connection = accept(listener, null, null);
        if (connection == invalid_socket) continue;
        const thread = std.Thread.spawn(.{}, serve, .{ init.io, connection }) catch {
            _ = closesocket(connection);
            continue;
        };
        thread.detach();
    }
}

fn fatal(io: std.Io, message: []const u8) noreturn {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("terrarium-helper: {s}\n", .{message}) catch {};
    writer.interface.flush() catch {};
    std.process.exit(1);
}

fn readExact(s: Socket, buffer: []u8) !void {
    var done: usize = 0;
    while (done < buffer.len) {
        const n = recv(s, buffer[done..].ptr, @intCast(buffer.len - done), 0);
        if (n <= 0) return error.ConnectionClosed;
        done += @intCast(n);
    }
}

fn writeAll(s: Socket, bytes: []const u8) !void {
    var done: usize = 0;
    while (done < bytes.len) {
        const n = send(s, bytes[done..].ptr, @intCast(bytes.len - done), 0);
        if (n <= 0) return error.ConnectionClosed;
        done += @intCast(n);
    }
}

/// One connection: frames are written whole, under a lock, because two threads send output.
const Connection = struct {
    io: std.Io,
    socket: Socket,
    lock: std.Io.Mutex = .init,
    finished: std.atomic.Value(bool) = .init(false),
    process: ?*anyopaque = null,
    /// The job the command runs in, so a host that hangs up ends everything it started.
    job: ?*anyopaque = null,
    /// When the command exited (GetTickCount64), or 0 while it runs.
    exited_at: std.atomic.Value(u64) = .init(0),

    fn sendFrame(c: *Connection, kind: u8, payload: []const u8) !void {
        c.lock.lockUncancelable(c.io);
        defer c.lock.unlock(c.io);
        try writeAll(c.socket, &protocol.header(kind, payload.len));
        try writeAll(c.socket, payload);
    }
};

fn serve(io: std.Io, s: Socket) void {
    var state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer state.deinit();
    const arena = state.allocator();
    var connection = Connection{ .io = io, .socket = s };
    // `run` may already have closed the socket to end its watcher.
    defer if (connection.socket != invalid_socket) {
        _ = closesocket(connection.socket);
    };

    var header: [5]u8 = undefined;
    readExact(s, &header) catch return;
    const length = std.mem.readInt(u32, header[1..5], .big);
    if (length > protocol.max_frame) return connection.sendFrame(protocol.error_kind, "request is too large") catch {};
    const payload = arena.alloc(u8, length) catch return;
    readExact(s, payload) catch return;

    switch (header[0]) {
        protocol.hello_kind => connection.sendFrame(protocol.hello_kind, "terrarium-helper " ++ protocol.version ++ " windows") catch {},
        protocol.exec_kind => run(&connection, arena, payload) catch |err| {
            connection.sendFrame(protocol.error_kind, @errorName(err)) catch {};
        },
        protocol.clipboard_get_kind => clipboardGet(&connection, arena),
        protocol.clipboard_set_kind => clipboardSet(&connection, arena, payload),
        else => connection.sendFrame(protocol.error_kind, "unknown request") catch {},
    }
}

/// The most clipboard text moved at once.
const clipboard_limit = 1 << 20;
const cf_unicodetext = 13;
const gmem_moveable = 0x2;

/// A window to own the clipboard: `SetClipboardData` fails after `EmptyClipboard` without one. A message-only window.
fn clipboardWindow() ?*anyopaque {
    const hwnd_message: ?*anyopaque = @ptrFromInt(~@as(usize, 2));
    return CreateWindowExW(0, std.unicode.utf8ToUtf16LeStringLiteral("STATIC"), null, 0, 0, 0, 0, 0, hwnd_message, null, null, null);
}

/// Opens the clipboard, trying again briefly while another program holds it. Fails with no desktop (session 0).
fn openClipboard(owner: ?*anyopaque) bool {
    for (0..10) |_| {
        if (OpenClipboard(owner) != 0) return true;
        Sleep(20);
    }
    return false;
}

/// Sends the clipboard's text with LF line ends. A clipboard without text is empty text.
fn clipboardGet(connection: *Connection, arena: std.mem.Allocator) void {
    const owner = clipboardWindow();
    defer if (owner) |w| {
        _ = DestroyWindow(w);
    };
    if (!openClipboard(owner)) return connection.sendFrame(protocol.error_kind, protocol.no_clipboard) catch {};
    defer _ = CloseClipboard();
    const handle = GetClipboardData(cf_unicodetext) orelse return connection.sendFrame(protocol.clipboard_kind, "") catch {};
    const locked: [*:0]const u16 = @ptrCast(@alignCast(GlobalLock(handle) orelse
        return connection.sendFrame(protocol.error_kind, "cannot read the clipboard") catch {}));
    defer _ = GlobalUnlock(handle);
    const utf8 = std.unicode.utf16LeToUtf8Alloc(arena, std.mem.span(locked)) catch
        return connection.sendFrame(protocol.error_kind, "the clipboard holds invalid text") catch {};
    const text = protocol.crlfToLf(utf8);
    if (text.len > clipboard_limit) return connection.sendFrame(protocol.error_kind, "clipboard text is too large") catch {};
    connection.sendFrame(protocol.clipboard_kind, text) catch {};
}

/// Replaces the clipboard's text with `text`, given with LF line ends.
fn clipboardSet(connection: *Connection, arena: std.mem.Allocator, text: []const u8) void {
    if (text.len > clipboard_limit) return connection.sendFrame(protocol.error_kind, "clipboard text is too large") catch {};
    const crlf = protocol.lfToCrlf(arena, text) catch return connection.sendFrame(protocol.error_kind, "out of memory") catch {};
    const wide = std.unicode.utf8ToUtf16LeAlloc(arena, crlf) catch
        return connection.sendFrame(protocol.error_kind, "the text is not valid UTF-8") catch {};
    const memory = GlobalAlloc(gmem_moveable, (wide.len + 1) * 2) orelse
        return connection.sendFrame(protocol.error_kind, "out of memory") catch {};
    const target: [*]u16 = @ptrCast(@alignCast(GlobalLock(memory) orelse {
        _ = GlobalFree(memory);
        return connection.sendFrame(protocol.error_kind, "out of memory") catch {};
    }));
    @memcpy(target[0..wide.len], wide);
    target[wide.len] = 0;
    _ = GlobalUnlock(memory);

    const owner = clipboardWindow();
    defer if (owner) |w| {
        _ = DestroyWindow(w);
    };
    if (!openClipboard(owner)) {
        _ = GlobalFree(memory);
        return connection.sendFrame(protocol.error_kind, protocol.no_clipboard) catch {};
    }
    defer _ = CloseClipboard();
    _ = EmptyClipboard();
    // On success the system owns the memory.
    if (SetClipboardData(cf_unicodetext, memory) == null) {
        _ = GlobalFree(memory);
        return connection.sendFrame(protocol.error_kind, "cannot set the clipboard") catch {};
    }
    connection.sendFrame(protocol.exit_kind, &protocol.exitPayload(0)) catch {};
}

/// Sends a pipe's output until it ends. It reads only what is waiting, so it never blocks on a pipe that something the
/// command started still holds open: once the command has exited, it stops after 300 ms without output, or 2 s at most.
fn pump(connection: *Connection, file: std.Io.File, kind: u8) void {
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        var available: u32 = 0;
        // Fails once every writer has closed and the pipe is empty.
        if (PeekNamedPipe(file.handle, null, 0, null, &available, null) == 0) return;
        const exited = connection.exited_at.load(.acquire);
        const since = if (exited == 0) 0 else GetTickCount64() -| exited;
        if (since > 2000 or (available == 0 and since > 300)) return;
        if (available == 0) {
            Sleep(10);
            continue;
        }
        const n = file.readStreaming(connection.io, &.{&buffer}) catch return;
        if (n == 0) return;
        connection.sendFrame(kind, buffer[0..n]) catch return;
    }
}

/// Watches for the host hanging up: nothing is sent after the request, so any receive result means it left.
fn watch(connection: *Connection) void {
    var byte: [1]u8 = undefined;
    _ = recv(connection.socket, &byte, 1, 0);
    if (!connection.finished.load(.acquire)) {
        if (connection.job) |job| {
            _ = TerminateJobObject(job, 1);
        } else if (connection.process) |p| {
            _ = TerminateProcess(p, 1);
        }
    }
}

fn run(connection: *Connection, arena: std.mem.Allocator, payload: []const u8) !void {
    const request = std.json.parseFromSliceLeaky(protocol.ExecRequest, arena, payload, .{ .ignore_unknown_fields = true }) catch
        return connection.sendFrame(protocol.error_kind, "malformed exec request");
    if (request.argv.len == 0) return connection.sendFrame(protocol.error_kind, "no command given");

    var child = std.process.spawn(connection.io, .{
        .argv = request.argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
        .create_no_window = true,
        // Suspended until it is in its job, so nothing it starts escapes the job.
        .start_suspended = true,
    }) catch |err| {
        const text = switch (err) {
            error.FileNotFound => try std.fmt.allocPrint(arena, "command not found: {s}", .{request.argv[0]}),
            else => try std.fmt.allocPrint(arena, "cannot run {s}: {s}", .{ request.argv[0], @errorName(err) }),
        };
        return connection.sendFrame(protocol.error_kind, text);
    };
    connection.process = child.id;
    connection.job = CreateJobObjectW(null, null);
    defer if (connection.job) |job| {
        _ = CloseHandle(job);
    };
    if (connection.job) |job| {
        if (AssignProcessToJobObject(job, child.id) == 0) {
            _ = CloseHandle(job);
            connection.job = null;
        }
    }
    _ = ResumeThread(child.thread_handle);

    const watcher = try std.Thread.spawn(.{}, watch, .{connection});
    // The watcher reads `connection`, which lives on this thread's stack: closing the socket ends its receive, and it
    // is joined before this function returns.
    defer {
        connection.finished.store(true, .release);
        _ = closesocket(connection.socket);
        connection.socket = invalid_socket;
        watcher.join();
    }
    // Without its pumps the command could not be heard: it is ended, and the host told why, while the socket is open.
    const out = std.Thread.spawn(.{}, pump, .{ connection, child.stdout.?, protocol.stdout_kind }) catch |e| {
        endCommand(connection, &child);
        connection.sendFrame(protocol.error_kind, "cannot start a thread for the command's output") catch {};
        return e;
    };
    const err = std.Thread.spawn(.{}, pump, .{ connection, child.stderr.?, protocol.stderr_kind }) catch |e| {
        endCommand(connection, &child);
        out.join();
        connection.sendFrame(protocol.error_kind, "cannot start a thread for the command's output") catch {};
        return e;
    };
    // The command's exit ends the pumps soon after, even while something it started holds the pipes.
    _ = WaitForSingleObject(child.id, 0xFFFFFFFF);
    connection.exited_at.store(@max(GetTickCount64(), 1), .release);
    out.join();
    err.join();

    // The whole 32-bit exit code (the standard library's wait keeps only its low byte), read while the handle is still
    // open; the watcher stops using the handle once `finished` is set, before `wait` closes it.
    _ = WaitForSingleObject(child.id, 0xFFFFFFFF);
    var code: u32 = 1;
    _ = GetExitCodeProcess(child.id, &code);
    connection.finished.store(true, .release);
    _ = child.wait(connection.io) catch {};
    try connection.sendFrame(protocol.exit_kind, &protocol.exitPayload(@bitCast(code)));
}

/// Ends the command and all it started, and reaps it.
fn endCommand(connection: *Connection, child: *std.process.Child) void {
    if (connection.job) |job| {
        _ = TerminateJobObject(job, 1);
    } else {
        _ = TerminateProcess(child.id, 1);
    }
    connection.exited_at.store(@max(GetTickCount64(), 1), .release);
    connection.finished.store(true, .release);
    _ = child.wait(connection.io) catch {};
}
