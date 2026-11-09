//! The frame protocol shared by the helpers (`unix.zig` and `windows.zig`).
//!
//! One request per connection, as frames: kind (u8), length (u32, big endian, at most `max_frame`), payload.
//!   host -> helper   0x00 hello (empty)            0x01 exec: JSON {"argv": ["prog", "arg", ...]}
//!                    0x02 clipboard get (empty)    0x03 clipboard set: UTF-8 text
//!                    0x04 put: JSON {"path": "...", "mode": 420}, then 0x05 data frames of at most `data_limit` bytes and
//!                         an empty one to end; the file is written whole or not at all, and missing directories are made
//!                    0x06 get: JSON {"path": "..."}
//!   helper -> host   0x00 hello: "terrarium-helper 1 <os> <instance>" (the instance: 16 hex digits, new each time the helper
//!                         starts, so a guest that restarted answers with another)
//!                    0x13 clipboard text (UTF-8, LF line ends; a set is answered by an exit frame of 0)
//!                    0x10 stdout bytes   0x11 stderr bytes
//!                    0x05 data: a get's file, in frames of at most `data_limit` bytes, then an exit frame of 0
//!                         (a put is answered by an exit frame of 0 once the file is in place)
//!                    0x12 exit: i32 big endian, the exit code or the negated signal number
//!                    0x1f error: UTF-8 text, ends the exchange
//! If the host closes the connection while a command runs, the command is killed.

const std = @import("std");

pub const port: u32 = 4242;
pub const version = "1";
pub const max_frame = 16 << 20;
pub const any_cid: u32 = 0xFFFFFFFF;

pub const hello_kind = 0x00;
pub const exec_kind = 0x01;
pub const clipboard_get_kind = 0x02;
pub const clipboard_set_kind = 0x03;
pub const put_kind = 0x04;
pub const data_kind = 0x05;
pub const get_kind = 0x06;
pub const stdout_kind = 0x10;
pub const stderr_kind = 0x11;
pub const exit_kind = 0x12;
pub const clipboard_kind = 0x13;
pub const error_kind = 0x1f;

/// The most file bytes in one data frame.
pub const data_limit = 1 << 20;

/// `mode` is the Unix permission bits; Windows ignores it.
pub const PutRequest = struct { path: []const u8, mode: u32 = 0o644 };
pub const GetRequest = struct { path: []const u8 };

/// The error text for a guest that has no clipboard to use (no session, or no tool); the host falls back to typing.
pub const no_clipboard = "no clipboard";

/// Converts text with LF line ends to CRLF (the Windows clipboard's), leaving existing CRLF pairs alone.
pub fn lfToCrlf(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (text, 0..) |byte, i| {
        if (byte == '\n' and (i == 0 or text[i - 1] != '\r')) try out.append(allocator, '\r');
        try out.append(allocator, byte);
    }
    return out.toOwnedSlice(allocator);
}

/// Converts CRLF to LF, in place; returns the shortened text.
pub fn crlfToLf(text: []u8) []u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\r' and i + 1 < text.len and text[i + 1] == '\n') continue;
        text[n] = text[i];
        n += 1;
    }
    return text[0..n];
}

/// This helper's instance ID: 16 lowercase hex digits from random bytes, chosen once at startup.
pub fn newInstance(random_bytes: [8]u8) [16]u8 {
    return std.fmt.bytesToHex(random_bytes, .lower);
}

/// The hello payload: the helper's name and protocol version, the guest OS, and the instance ID.
pub fn helloText(buffer: []u8, os: []const u8, instance: []const u8) []const u8 {
    return std.fmt.bufPrint(buffer, "terrarium-helper {s} {s} {s}", .{ version, os, instance }) catch "terrarium-helper";
}

pub const ExecRequest = struct { argv: []const []const u8 };

pub fn header(kind: u8, length: usize) [5]u8 {
    var bytes: [5]u8 = undefined;
    bytes[0] = kind;
    std.mem.writeInt(u32, bytes[1..5], @intCast(length), .big);
    return bytes;
}

/// The payload of an exit frame: the exit code, or the negated signal number.
pub fn exitPayload(code: i32) [4]u8 {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &bytes, code, .big);
    return bytes;
}

test "header is the kind and a big-endian length" {
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x00, 0x01, 0x02, 0x03 }, &header(stdout_kind, 0x010203));
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x00, 0x00, 0x00, 0x00 }, &header(hello_kind, 0));
}

test "a frame can be as long as max_frame" {
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x01, 0x00, 0x00, 0x00 }, &header(exec_kind, max_frame));
}

test "exit payload carries the code or the negated signal" {
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 3 }, &exitPayload(3));
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0xff, 0xff, 0xf7 }, &exitPayload(-9));
}

test "an exec request ignores unknown fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const request = try std.json.parseFromSliceLeaky(ExecRequest, arena.allocator(), "{\"argv\": [\"ls\", \"-l\"], \"x\": 1}", .{ .ignore_unknown_fields = true });
    try std.testing.expectEqual(2, request.argv.len);
    try std.testing.expectEqualStrings("ls", request.argv[0]);
}

test "line ends convert to CRLF and back" {
    const crlf = try lfToCrlf(std.testing.allocator, "a\nb\r\nc\n");
    defer std.testing.allocator.free(crlf);
    try std.testing.expectEqualStrings("a\r\nb\r\nc\r\n", crlf);
    var copy = try std.testing.allocator.dupe(u8, crlf);
    defer std.testing.allocator.free(copy);
    try std.testing.expectEqualStrings("a\nb\nc\n", crlfToLf(copy[0..]));
}

test "a put request defaults its mode and ignores unknown fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const request = try std.json.parseFromSliceLeaky(PutRequest, arena.allocator(), "{\"path\": \"/tmp/a\", \"x\": 1}", .{ .ignore_unknown_fields = true });
    try std.testing.expectEqualStrings("/tmp/a", request.path);
    try std.testing.expectEqual(0o644, request.mode);
}

test "the hello names the helper, its protocol, the OS, and the instance" {
    var buffer: [96]u8 = undefined;
    const instance = newInstance(.{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef });
    try std.testing.expectEqualStrings("0123456789abcdef", &instance);
    try std.testing.expectEqualStrings("terrarium-helper 1 linux 0123456789abcdef", helloText(&buffer, "linux", &instance));
}
