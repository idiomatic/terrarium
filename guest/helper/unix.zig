//! The guest helper for Linux and macOS: listens on vsock and runs commands for `terrarium`.
//!
//! The frames are described in `protocol.zig`.

const std = @import("std");
const builtin = @import("builtin");
const c = std.c;
const posix = std.posix;

const protocol = @import("protocol.zig");

extern "c" fn socket(domain: c_int, kind: c_int, protocol: c_int) c_int;

const af_vsock = 40;
const sock_stream = 1;

/// Linux has `sockaddr.vm` in the standard library; Darwin's `sockaddr_vm` leads with a length byte.
const VsockAddress = switch (builtin.os.tag) {
    .linux => std.os.linux.sockaddr.vm,
    else => extern struct {
        len: u8 = 12,
        family: u8 = af_vsock,
        reserved1: u16 = 0,
        port: u32,
        cid: u32,
    },
};

fn listenAddress() VsockAddress {
    return switch (builtin.os.tag) {
        .linux => .{ .port = protocol.port, .cid = protocol.any_cid, .flags = 0 },
        else => .{ .port = protocol.port, .cid = protocol.any_cid },
    };
}

pub fn main(init: std.process.Init) !void {
    // A host that disconnects mid-command must not kill the helper with SIGPIPE. A handler that does nothing, not SIG_IGN:
    // an ignored signal stays ignored across exec, and commands should get the default.
    posix.sigaction(.PIPE, &.{ .handler = .{ .handler = ignoreSignal }, .mask = posix.sigemptyset(), .flags = 0 }, null);

    const listener = socket(af_vsock, sock_stream, 0);
    if (listener < 0) fatal(init.io, "cannot create a vsock socket (is the vsock driver loaded?)");
    const address = listenAddress();
    if (c.bind(listener, @ptrCast(&address), @sizeOf(VsockAddress)) != 0) fatal(init.io, "cannot bind the vsock port");
    if (c.listen(listener, 16) != 0) fatal(init.io, "cannot listen on the vsock port");

    while (true) {
        const connection = c.accept(listener, null, null);
        if (connection < 0) continue;
        const thread = std.Thread.spawn(.{}, serve, .{ init.io, connection }) catch {
            _ = c.close(connection);
            continue;
        };
        thread.detach();
    }
}

fn ignoreSignal(_: posix.SIG) callconv(.c) void {}

fn fatal(io: std.Io, message: []const u8) noreturn {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("terrarium-helper: {s}\n", .{message}) catch {};
    writer.interface.flush() catch {};
    std.process.exit(1);
}

const Frame = struct { kind: u8, payload: []u8 };

fn readExact(fd: c.fd_t, buffer: []u8) !void {
    var done: usize = 0;
    while (done < buffer.len) {
        const n = c.read(fd, buffer[done..].ptr, buffer.len - done);
        if (n <= 0) return error.ConnectionClosed;
        done += @intCast(n);
    }
}

fn writeAll(fd: c.fd_t, bytes: []const u8) !void {
    var done: usize = 0;
    while (done < bytes.len) {
        const n = c.write(fd, bytes[done..].ptr, bytes.len - done);
        if (n <= 0) return error.ConnectionClosed;
        done += @intCast(n);
    }
}

fn writeFrame(fd: c.fd_t, kind: u8, payload: []const u8) !void {
    try writeAll(fd, &protocol.header(kind, payload.len));
    try writeAll(fd, payload);
}

fn readFrame(arena: std.mem.Allocator, fd: c.fd_t) !Frame {
    var header: [5]u8 = undefined;
    try readExact(fd, &header);
    const length = std.mem.readInt(u32, header[1..5], .big);
    if (length > protocol.max_frame) return error.FrameTooLarge;
    const payload = try arena.alloc(u8, length);
    try readExact(fd, payload);
    return .{ .kind = header[0], .payload = payload };
}

fn serve(io: std.Io, fd: c.fd_t) void {
    defer _ = c.close(fd);
    var state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer state.deinit();
    const arena = state.allocator();

    const request = readFrame(arena, fd) catch |err| {
        if (err == error.FrameTooLarge) writeFrame(fd, protocol.error_kind, "request is too large") catch {};
        return;
    };
    switch (request.kind) {
        protocol.hello_kind => writeFrame(fd, protocol.hello_kind, "terrarium-helper " ++ protocol.version ++ " " ++ @tagName(builtin.os.tag)) catch {},
        protocol.exec_kind => run(io, arena, fd, request.payload) catch |err| {
            const text = std.fmt.allocPrint(arena, "{s}", .{@errorName(err)}) catch "error";
            writeFrame(fd, protocol.error_kind, text) catch {};
        },
        protocol.clipboard_get_kind => clipboardGet(io, arena, fd),
        protocol.clipboard_set_kind => clipboardSet(io, arena, fd, request.payload),
        else => writeFrame(fd, protocol.error_kind, "unknown request") catch {},
    }
}

/// The most clipboard text moved at once.
const clipboard_limit = 1 << 20;

const ClipboardTool = struct { get: []const []const u8, set: []const []const u8 };

/// The programs that reach the session's clipboard, tried in order. The macOS helper is a LaunchAgent, so it is in the
/// account's session; on Linux the tools need a graphical session (X11 on display :0 is assumed when none is set).
const clipboard_tools = switch (builtin.os.tag) {
    .macos => [_]ClipboardTool{
        .{ .get = &.{ "/usr/bin/env", "LANG=en_US.UTF-8", "pbpaste" }, .set = &.{ "/usr/bin/env", "LANG=en_US.UTF-8", "pbcopy" } },
    },
    else => [_]ClipboardTool{
        .{ .get = &.{ "wl-paste", "-n" }, .set = &.{"wl-copy"} },
        .{
            .get = &.{ "/usr/bin/env", "DISPLAY=:0", "xclip", "-selection", "clipboard", "-o" },
            .set = &.{ "/usr/bin/env", "DISPLAY=:0", "xclip", "-selection", "clipboard", "-i" },
        },
    },
};

/// Runs one clipboard program: with `input` it is fed that and its output is dropped; without, its output is returned.
/// Null when the program is missing or fails.
fn clipboardTool(io: std.Io, arena: std.mem.Allocator, argv: []const []const u8, input: ?[]const u8) error{TooLarge}!?[]u8 {
    const child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = if (input != null) .pipe else .ignore,
        .stdout = if (input == null) .pipe else .ignore,
        .stderr = .ignore,
        .pgid = 0,
    }) catch return null;
    const pid = child.id.?;
    var output: std.ArrayList(u8) = .empty;
    var too_large = false;
    if (input) |text| {
        const in_fd = child.stdin.?.handle;
        writeAll(in_fd, text) catch {};
        _ = c.close(in_fd);
    } else {
        const out_fd = child.stdout.?.handle;
        var buffer: [64 * 1024]u8 = undefined;
        while (true) {
            const n = c.read(out_fd, &buffer, buffer.len);
            if (n <= 0) break;
            output.appendSlice(arena, buffer[0..@intCast(n)]) catch break;
            if (output.items.len > clipboard_limit) {
                too_large = true;
                break;
            }
        }
        _ = c.close(out_fd);
    }
    const raw: u32 = @bitCast(waitFor(pid));
    if (too_large) return error.TooLarge;
    if (!c.W.IFEXITED(raw) or c.W.EXITSTATUS(raw) != 0) return null;
    return output.items;
}

fn clipboardGet(io: std.Io, arena: std.mem.Allocator, fd: c.fd_t) void {
    for (clipboard_tools) |tool| {
        const text = clipboardTool(io, arena, tool.get, null) catch
            return writeFrame(fd, protocol.error_kind, "clipboard text is too large") catch {};
        if (text) |bytes| return writeFrame(fd, protocol.clipboard_kind, bytes) catch {};
    }
    writeFrame(fd, protocol.error_kind, protocol.no_clipboard) catch {};
}

fn clipboardSet(io: std.Io, arena: std.mem.Allocator, fd: c.fd_t, text: []const u8) void {
    if (text.len > clipboard_limit) return writeFrame(fd, protocol.error_kind, "clipboard text is too large") catch {};
    for (clipboard_tools) |tool| {
        const done = clipboardTool(io, arena, tool.set, text) catch null;
        if (done != null) return writeFrame(fd, protocol.exit_kind, &protocol.exitPayload(0)) catch {};
    }
    writeFrame(fd, protocol.error_kind, protocol.no_clipboard) catch {};
}

fn run(io: std.Io, arena: std.mem.Allocator, fd: c.fd_t, payload: []const u8) !void {
    const request = std.json.parseFromSliceLeaky(protocol.ExecRequest, arena, payload, .{ .ignore_unknown_fields = true }) catch
        return writeFrame(fd, protocol.error_kind, "malformed exec request");
    if (request.argv.len == 0) return writeFrame(fd, protocol.error_kind, "no command given");

    // Its own process group, so a host that hangs up kills everything the command started.
    const child = std.process.spawn(io, .{
        .argv = request.argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
        .pgid = 0,
    }) catch |err| {
        const text = switch (err) {
            error.FileNotFound => try std.fmt.allocPrint(arena, "command not found: {s}", .{request.argv[0]}),
            else => try std.fmt.allocPrint(arena, "cannot run {s}: {s}", .{ request.argv[0], @errorName(err) }),
        };
        return writeFrame(fd, protocol.error_kind, text);
    };
    // The child is reaped here, not by `child.wait`: its exit must be noticed while something it started still holds its
    // output open (`sh -c 'daemon &'`), which would otherwise keep the output from ending.
    const pid = child.id.?;
    const out_fd = child.stdout.?.handle;
    const err_fd = child.stderr.?.handle;
    defer {
        _ = c.close(out_fd);
        _ = c.close(err_fd);
    }

    var fds = [3]posix.pollfd{
        .{ .fd = out_fd, .events = posix.POLL.IN, .revents = 0 },
        .{ .fd = err_fd, .events = posix.POLL.IN, .revents = 0 },
        .{ .fd = fd, .events = posix.POLL.IN, .revents = 0 },
    };
    const kinds = [2]u8{ protocol.stdout_kind, protocol.stderr_kind };
    var open: usize = 2;
    var buffer: [64 * 1024]u8 = undefined;
    const ready = posix.POLL.IN | posix.POLL.HUP | posix.POLL.ERR;
    var status: ?c_int = null;
    // Once the command has exited, what is still coming is read for at most this many more polls.
    var drain: u32 = 10;
    while (open > 0) {
        if (status == null) {
            var raw: c_int = 0;
            if (c.waitpid(pid, &raw, c.W.NOHANG) == pid) status = raw;
        }
        if (status != null) {
            if (drain == 0) break;
            drain -= 1;
        }
        const n = posix.poll(&fds, if (status != null) 100 else 250) catch break;
        if (n == 0) {
            if (status != null) break;
            continue;
        }
        for (0..2) |i| {
            if (fds[i].fd < 0 or fds[i].revents & ready == 0) continue;
            const got = c.read(fds[i].fd, &buffer, buffer.len);
            if (got <= 0) {
                fds[i].fd = -1;
                open -= 1;
            } else {
                writeFrame(fd, kinds[i], buffer[0..@intCast(got)]) catch return killGroup(pid, status);
            }
        }
        if (fds[2].revents & ready != 0) {
            // The host sends nothing after the request, so readable means it hung up.
            const got = c.read(fd, &buffer, buffer.len);
            if (got <= 0) return killGroup(pid, status);
        }
    }

    const raw: u32 = @bitCast(status orelse waitFor(pid));
    var code: i32 = -1;
    if (c.W.IFEXITED(raw)) {
        code = c.W.EXITSTATUS(raw);
    } else if (c.W.IFSIGNALED(raw)) {
        code = -@as(i32, @intCast(@intFromEnum(c.W.TERMSIG(raw))));
    }
    try writeFrame(fd, protocol.exit_kind, &protocol.exitPayload(code));
}

/// Kills the command's whole process group, for a host that hung up, and reaps the command unless it already was.
fn killGroup(pid: posix.pid_t, status: ?c_int) void {
    _ = c.kill(-pid, .KILL);
    if (status == null) _ = waitFor(pid);
}

fn waitFor(pid: posix.pid_t) c_int {
    var raw: c_int = 0;
    while (c.waitpid(pid, &raw, 0) < 0) {
        if (std.c._errno().* != @intFromEnum(posix.E.INTR)) return 0;
    }
    return raw;
}
