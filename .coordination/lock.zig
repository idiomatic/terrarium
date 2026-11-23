//! Advisory locks for agents sharing a project, across its worktrees.
//! Run as `zig run lock.zig -- COMMAND ...` from anywhere in the project.

const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

const usage =
    \\  lock take NAME [MINUTES]    take NAME (default 30 minutes), or fail if held
    \\  lock renew NAME [MINUTES]   extend a lock you hold
    \\  lock release NAME           release a lock you hold
    \\  lock list                   show every lock, and whether it has expired
    \\
;

const Lock = struct {
    owner: []const u8,
    expires: i64,
    note: []const u8,
};

const Context = struct {
    io: Io,
    arena: std.mem.Allocator,
    locks: Dir,
    owner: []const u8,
    note: []const u8,
    now: i64,
    stderr: *Io.Writer,
};

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    var buffer: [512]u8 = undefined;
    var stderr = Io.File.stderr().writer(io, &buffer);
    defer stderr.interface.flush() catch {};
    var cx: Context = .{
        .io = io,
        .arena = arena,
        .locks = openLocks(io, arena) catch |err| switch (err) {
            error.NotInGit => {
                try stderr.interface.writeAll("lock: not within a Git repository\n");
                return 2;
            },
            else => |e| return e,
        },
        .owner = owner(init.environ_map),
        .note = init.environ_map.get("LOCK_NOTE") orelse "",
        .now = Io.Timestamp.now(io, .real).toSeconds(),
        .stderr = &stderr.interface,
    };
    const args = (try init.minimal.args.toSlice(arena))[1..];
    return run(&cx, args) catch |err| switch (err) {
        error.Usage => {
            try cx.stderr.writeAll(usage);
            return 2;
        },
        error.Held => 1,
        error.Misuse => 2,
        else => |e| return e,
    };
}

fn run(cx: *Context, args: []const [:0]const u8) !u8 {
    if (args.len == 1 and std.mem.eql(u8, args[0], "list")) return list(cx);
    if (args.len < 2 or args.len > 3) return error.Usage;
    const command = std.meta.stringToEnum(enum { take, renew, release }, args[0]) orelse
        return error.Usage;
    const name = args[1];
    if (name.len == 0 or name[0] == '.' or std.mem.indexOfAny(u8, name, "/\\") != null)
        return fail(cx, error.Misuse, "bad name: {s}", .{name});
    const minutes = std.fmt.parseUnsigned(u32, if (args.len == 3) args[2] else "30", 10) catch
        return fail(cx, error.Misuse, "bad minutes: {s}", .{args[2]});
    if (cx.owner.len == 0) return fail(cx, error.Misuse, "set AGENT_ID to name yourself", .{});

    const held = read(cx, cx.locks, name);
    if (!std.mem.eql(u8, held.owner, cx.owner)) {
        if (command != .take) return fail(cx, error.Held, "you don't hold {s}", .{name});
        try claim(cx, name, minutes);
    } else if (command == .release) {
        try cx.locks.deleteTree(cx.io, name);
    } else {
        var d = try cx.locks.openDir(cx.io, name, .{});
        defer d.close(cx.io);
        try write(cx, d, minutes);
    }
    return 0;
}

/// `.coordination/locks` at the main worktree's root, which every worktree
/// shares.
fn openLocks(io: Io, arena: std.mem.Allocator) !Dir {
    const root = try mainWorktree(io, arena);
    const path = try std.fs.path.join(arena, &.{ root, ".coordination", "locks" });
    try Dir.cwd().createDirPath(io, path);
    return Dir.cwd().openDir(io, path, .{ .iterate = true });
}

/// The main worktree's root, found as Git finds it, without running Git: the
/// nearest `.git` up from the current directory is either the repository
/// (so its parent is the root), or, in a linked worktree, a file naming its
/// directory under the repository's `worktrees/`, whose `commondir` names
/// the repository. A `.git` file without one (a submodule's) is its own root.
fn mainWorktree(io: Io, arena: std.mem.Allocator) ![]const u8 {
    var dir: []const u8 = try std.process.currentPathAlloc(io, arena);
    while (true) {
        const dot_git = try std.fs.path.join(arena, &.{ dir, ".git" });
        if (Dir.cwd().statFile(io, dot_git, .{})) |stat| {
            if (stat.kind == .directory) return dir;
            const link = try Dir.cwd().readFileAlloc(io, dot_git, arena, .limited(4096));
            const prefix = "gitdir:";
            if (!std.mem.startsWith(u8, link, prefix)) return error.NotInGit;
            const git_dir = try std.fs.path.resolveAlloc(arena, &.{
                dir, std.mem.trim(u8, link[prefix.len..], " \t\r\n"),
            });
            const common_path = try std.fs.path.join(arena, &.{ git_dir, "commondir" });
            const common = Dir.cwd().readFileAlloc(io, common_path, arena, .limited(4096)) catch |err| switch (err) {
                error.FileNotFound => return dir,
                else => |e| return e,
            };
            const repository = try std.fs.path.resolveAlloc(arena, &.{
                git_dir, std.mem.trim(u8, common, " \t\r\n"),
            });
            return std.fs.path.dirname(repository) orelse error.NotInGit;
        } else |err| switch (err) {
            error.FileNotFound => dir = std.fs.path.dirname(dir) orelse return error.NotInGit,
            else => |e| return e,
        }
    }
}

fn owner(env: *const std.process.Environ.Map) []const u8 {
    for ([_][]const u8{ "OPENCODE_SESSION_ID", "CLAUDE_SESSION_ID", "AGENT_ID" }) |key| {
        if (env.get(key)) |value| if (value.len > 0) return value;
    }
    return "";
}

fn list(cx: *Context) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writer(cx.io, &stdout_buffer);
    var it = cx.locks.iterate();
    while (try it.next(cx.io)) |entry| {
        if (entry.kind != .directory or entry.name[0] == '.') continue;
        const l = read(cx, cx.locks, entry.name);
        try stdout.interface.print("{s}\t{s}\t{s}\t{s}\n", .{
            entry.name,
            l.owner,
            if (l.expires > cx.now) "held" else "expired",
            l.note,
        });
    }
    try stdout.interface.flush();
    return 0;
}

/// Builds the lock aside, then renames it into place, so no one ever sees
/// one half written.
fn claim(cx: *Context, name: []const u8, minutes: u32) !void {
    var random: [8]u8 = undefined;
    cx.io.random(&random);
    const new = try std.fmt.allocPrint(cx.arena, ".new.{x}", .{&random});
    const stale = try std.fmt.allocPrint(cx.arena, ".stale.{x}", .{&random});
    try cx.locks.createDir(cx.io, new, .default_dir);
    defer cx.locks.deleteTree(cx.io, new) catch {};
    {
        var d = try cx.locks.openDir(cx.io, new, .{});
        defer d.close(cx.io);
        try write(cx, d, minutes);
    }
    while (true) {
        if (cx.locks.rename(new, cx.locks, name, cx.io)) return else |_| {}
        const seen = read(cx, cx.locks, name);
        const left = @divFloor(seen.expires - cx.now + 59, 60);
        if (seen.expires > cx.now)
            return fail(cx, error.Held, "{s} is held by {s} for {d} more minute{s}", .{
                name, seen.owner, left, if (left == 1) "" else "s",
            });
        // Move the expired lock aside, which only one agent can do; if what
        // moved isn't what was seen, someone else took it first.
        cx.locks.rename(name, cx.locks, stale, cx.io) catch
            return fail(cx, error.Held, "{s} was just taken", .{name});
        const moved = read(cx, cx.locks, stale);
        if (moved.expires != seen.expires or !std.mem.eql(u8, moved.owner, seen.owner)) {
            cx.locks.rename(stale, cx.locks, name, cx.io) catch {};
            return fail(cx, error.Held, "{s} was just taken", .{name});
        }
        try cx.locks.deleteTree(cx.io, stale);
    }
}

fn read(cx: *Context, dir: Dir, name: []const u8) Lock {
    var d = dir.openDir(cx.io, name, .{}) catch return .{ .owner = "", .expires = 0, .note = "" };
    defer d.close(cx.io);
    return .{
        .owner = field(cx, d, "owner"),
        .expires = std.fmt.parseInt(i64, field(cx, d, "expires"), 10) catch 0,
        .note = field(cx, d, "note"),
    };
}

fn field(cx: *Context, d: Dir, name: []const u8) []const u8 {
    const text = d.readFileAlloc(cx.io, name, cx.arena, .limited(64 * 1024)) catch return "";
    return std.mem.trim(u8, text, " \t\r\n");
}

fn write(cx: *Context, d: Dir, minutes: u32) !void {
    const expires = cx.now + @as(i64, minutes) * 60;
    try d.writeFile(cx.io, .{ .sub_path = "owner", .data = try std.fmt.allocPrint(cx.arena, "{s}\n", .{cx.owner}) });
    try d.writeFile(cx.io, .{ .sub_path = "expires", .data = try std.fmt.allocPrint(cx.arena, "{d}\n", .{expires}) });
    if (cx.note.len > 0)
        try d.writeFile(cx.io, .{ .sub_path = "note", .data = try std.fmt.allocPrint(cx.arena, "{s}\n", .{cx.note}) });
}

fn fail(cx: *Context, err: anytype, comptime format: []const u8, args: anytype) @TypeOf(err) {
    cx.stderr.print("lock: " ++ format ++ "\n", args) catch {};
    return err;
}
