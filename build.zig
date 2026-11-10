const std = @import("std");

/// Files linked into the `__TERRARIUM` section of the given name (at most 16 characters): the recipes' scripts and answer files, and the tweaks.
const assets = [_]struct { section: []const u8, path: []const u8 }{
    .{ .section = "win-install", .path = "core/recipes/windows/install.cmd" },
    .{ .section = "win-unattend", .path = "core/recipes/windows/unattend.xml" },
    .{ .section = "win-setup", .path = "core/recipes/windows/SetupComplete.cmd" },
    .{ .section = "alp-start", .path = "core/recipes/alpine/install.start" },
    .{ .section = "alp-answers", .path = "core/recipes/alpine/answers" },
    .{ .section = "tw-edge-quiet", .path = "core/tweaks/windows/edge-quiet.ps1" },
    .{ .section = "tw-exp-sleep", .path = "core/tweaks/linux/experimental-sleep.sh" },
    .{ .section = "tw-alpine-repos", .path = "core/tweaks/linux/alpine-repositories.sh" },
    .{ .section = "tw-no-blank", .path = "core/tweaks/linux/no-blank.sh" },
    .{ .section = "tw-ubu-welcome", .path = "core/tweaks/linux/ubuntu-no-welcome.sh" },
    .{ .section = "tw-win-nolock", .path = "core/tweaks/windows/no-lock.ps1" },
    .{ .section = "tw-mac-quiet", .path = "core/tweaks/macos/quiet-setup.sh" },
    .{ .section = "tw-mac-nosaver", .path = "core/tweaks/macos/no-screensaver.sh" },
    .{ .section = "tw-mac-nosleep", .path = "core/tweaks/macos/no-sleep.sh" },
    .{ .section = "tw-win-nosleep", .path = "core/tweaks/windows/no-sleep.ps1" },
};

/// One static helper per guest OS, linked into the `__TERRARIUM` section of the same name.
const Helper = struct {
    section: []const u8,
    root: []const u8,
    query: std.Target.Query,
};

const helpers = [_]Helper{
    .{ .section = "macos", .root = "guest/helper/unix.zig", .query = .{ .cpu_arch = .aarch64, .os_tag = .macos } },
    .{ .section = "linux", .root = "guest/helper/unix.zig", .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl } },
    .{ .section = "windows", .root = "guest/helper/windows.zig", .query = .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu } },
};

/// Links the guest helpers, the Windows shim, and the recipes' files into `command`'s binary, as `__TERRARIUM` sections.
const Embeds = struct {
    helpers: [helpers.len]*std.Build.Step.Compile,
    shim: *std.Build.Step.Compile,

    fn add(self: Embeds, b: *std.Build, command: *std.Build.Step.Run) void {
        inline for (helpers, 0..) |h, index| {
            command.addArgs(&.{ "-Xlinker", "-sectcreate", "-Xlinker", "__TERRARIUM", "-Xlinker", h.section, "-Xlinker" });
            command.addFileArg(self.helpers[index].getEmittedBin());
        }
        command.addArgs(&.{ "-Xlinker", "-sectcreate", "-Xlinker", "__TERRARIUM", "-Xlinker", "winfb", "-Xlinker" });
        command.addFileArg(self.shim.getEmittedBin());
        for (assets) |asset| {
            command.addArgs(&.{ "-Xlinker", "-sectcreate", "-Xlinker", "__TERRARIUM", "-Xlinker", asset.section, "-Xlinker" });
            command.addFileArg(b.path(asset.path));
        }
    }
};

/// A Swift module built as a static library and a `.swiftmodule` in one output directory.
const SwiftModule = struct { dir: std.Build.LazyPath };

/// Compiles every `.swift` file under `source_dirs` (relative to the build root) as the module `name`, importing `imports`.
/// Testing is enabled, so the unit checks can `@testable import` the core.
fn swiftModule(b: *std.Build, name: []const u8, source_dirs: []const []const u8, imports: []const SwiftModule, optimize: std.builtin.OptimizeMode) SwiftModule {
    const script = b.fmt(
        "out=\"$1\"; shift; exec swiftc \"$@\" -module-name {s} -parse-as-library -enable-testing -emit-module -emit-module-path \"$out/{s}.swiftmodule\" -emit-library -static -o \"$out/lib{s}.a\" $(find {s} -name '*.swift' | sort)",
        .{ name, name, name, std.mem.join(b.allocator, " ", source_dirs) catch @panic("OOM") },
    );
    const command = b.addSystemCommand(&.{ "sh", "-c", script, "sh" });
    command.setCwd(b.path("."));
    const dir = command.addOutputDirectoryArg(name);
    // Whole-module: without it swiftc spreads the files over one process per core, and each type-checks all the others.
    command.addArgs(&.{ "-target", "arm64-apple-macos27.0", "-wmo", if (optimize == .debug) "-Onone" else "-O" });
    for (imports) |module| command.addPrefixedDirectoryArg("-I", module.dir);
    command.has_side_effects = true;
    return .{ .dir = dir };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    var embeds: Embeds = undefined;
    inline for (helpers, 0..) |h, index| {
        embeds.helpers[index] = b.addExecutable(.{
            .name = "terrarium-helper",
            .root_module = b.createModule(.{
                .root_source_file = b.path(h.root),
                .target = b.resolveTargetQuery(h.query),
                .optimize = .small,
                .strip = true,
                .single_threaded = false,
                .link_libc = h.query.os_tag != .windows,
            }),
        });
    }
    // The Windows framebuffer shim, an EFI application, is embedded the same way.
    embeds.shim = b.addExecutable(.{
        .name = "winfb",
        .root_module = b.createModule(.{
            .root_source_file = b.path("guest/shim/winfb.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .uefi }),
            .optimize = .small,
        }),
    });

    // The Swift host, in three modules: `TerrariumCore` (no UI; images, recipes, VMs, the verbs), `TerrariumUI` (the `run`
    // window, over AppKit), and the `terrarium` executable (the CLI and the MCP server). Each module's sources are found by
    // the shell when the build runs (so a new file needs no edit here), which is why the steps always run.
    const core = swiftModule(b, "TerrariumCore", &.{"core"}, &.{}, optimize);
    const ui = swiftModule(b, "TerrariumUI", &.{"ui"}, &.{core}, optimize);
    // The linker leaves the binary unsigned; the sign step below signs the installed copy.
    const swiftc = b.addSystemCommand(&.{
        "sh",
        "-c",
        "exec swiftc \"$@\" $(find cli -name '*.swift' | sort)",
        "sh",
        "-target",
        "arm64-apple-macos27.0",
        "-module-name",
        "terrarium",
        "-Xlinker",
        "-no_adhoc_codesign",
    });
    // `find` is relative: run it from the build root, whatever directory `zig build` was started in.
    swiftc.setCwd(b.path("."));
    swiftc.addArgs(&.{ "-wmo", if (optimize == .debug) "-Onone" else "-O" });
    for ([_]SwiftModule{ ui, core }) |module| {
        swiftc.addPrefixedDirectoryArg("-I", module.dir);
        swiftc.addPrefixedDirectoryArg("-L", module.dir);
    }
    swiftc.addArgs(&.{ "-lTerrariumUI", "-lTerrariumCore" });
    embeds.add(b, swiftc);
    // An embedded Info.plist gives the bare executable a bundle name, which the menu bar shows.
    swiftc.addArgs(&.{ "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker" });
    swiftc.addFileArg(b.path("cli/Info.plist"));
    swiftc.addArg("-o");
    const terrarium = swiftc.addOutputFileArg("terrarium");
    swiftc.has_side_effects = true;
    const install = b.addInstallBinFile(terrarium, "terrarium");

    // codesign only works in place, so it signs the installed file rather than a cached artifact.
    const sign = b.addSystemCommand(&.{ "codesign", "--force", "--sign", "-", "--entitlements" });
    sign.addFileArg(b.path("cli/terrarium.entitlements"));
    sign.addFileArg(b.graph.path(.install_bin, "terrarium"));
    sign.stdio = .inherit;
    sign.step.dependOn(&install.step);
    b.getInstallStep().dependOn(&sign.step);

    // The protocol checks need no VM; `tests/live.py` needs a stored Alpine image and is run by hand.
    const protocol = b.addSystemCommand(&.{ "python3", "-I", "tests/mcp.py" });
    protocol.addFileArg(b.graph.path(.install_bin, "terrarium"));
    protocol.step.dependOn(&sign.step);
    const conversion = b.addSystemCommand(&.{ "python3", "-I", "tests/pull.py" });
    conversion.addFileArg(b.graph.path(.install_bin, "terrarium"));
    conversion.step.dependOn(&sign.step);
    const layers = b.addSystemCommand(&.{ "python3", "-I", "tests/layers.py", "core" });
    layers.setCwd(b.path("."));
    const frames = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("guest/helper/protocol.zig"),
            .target = b.graph.host,
        }),
    });
    const frame_tests = b.addRunArtifact(frames);
    // The Unix helper's file transfer, over a socket pair on the host.
    const unix_helper = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("guest/helper/unix.zig"),
            .target = b.graph.host,
            .link_libc = true,
        }),
    });
    const unix_tests = b.addRunArtifact(unix_helper);
    // The core's pure helpers, checked through `@testable import` of the module (built with testing enabled).
    const unit = b.addSystemCommand(&.{
        "sh",
        "-c",
        "exec swiftc \"$@\" tests/unit/main.swift",
        "sh",
        "-target",
        "arm64-apple-macos27.0",
        "-module-name",
        "unit",
        "-Onone",
    });
    unit.setCwd(b.path("."));
    unit.has_side_effects = true;
    unit.addPrefixedDirectoryArg("-I", core.dir);
    unit.addPrefixedDirectoryArg("-L", core.dir);
    unit.addArg("-lTerrariumCore");
    unit.addArg("-o");
    const unit_binary = unit.addOutputFileArg("terrarium-unit");
    const unit_tests = std.Build.Step.Run.create(b, "run unit checks");
    unit_tests.addFileArg(unit_binary);
    const checks = b.step("test", "Check the core's layering, the helper's frames, the core's helpers, the MCP server's protocol handling, and pull");
    checks.dependOn(&layers.step);
    checks.dependOn(&frame_tests.step);
    checks.dependOn(&unix_tests.step);
    checks.dependOn(&unit_tests.step);
    checks.dependOn(&protocol.step);
    checks.dependOn(&conversion.step);

    const run = std.Build.Step.Run.create(b, "run terrarium");
    run.addFileArg(b.graph.path(.install_bin, "terrarium"));
    run.addPassthruArgs();
    run.step.dependOn(&sign.step);
    b.step("run", "Build and run terrarium").dependOn(&run.step);
}
