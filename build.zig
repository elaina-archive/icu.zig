const std = @import("std");
const mem = std.mem;
const fs = std.fs;

fn collectSources(b: *std.Build, path: std.Build.LazyPath) []const []const u8 {
    const p = path.getPath(b);

    var dir = fs.openDirAbsolute(p, .{
        .iterate = true,
    }) catch |e| std.debug.panic("Failed to open {s}: {s}", .{ p, @errorName(e) });
    defer dir.close();

    var list = std.ArrayList([]const u8).init(b.allocator);
    defer list.deinit();

    var iter = dir.iterate();
    while (iter.next() catch |e| std.debug.panic("Failed to iterate {s}: {s}", .{ p, @errorName(e) })) |entry| {
        if (entry.kind != .file) continue;

        const ext = fs.path.extension(entry.name);

        if (mem.eql(u8, ext, ".cpp") or mem.eql(u8, ext, ".c")) {
            list.append(b.allocator.dupe(u8, entry.name) catch @panic("OOM")) catch @panic("OOM");
        }
    }

    return list.toOwnedSlice() catch |e| std.debug.panic("Failed to allocate memory: {s}", .{@errorName(e)});
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "whether to statically or dynamically link the library") orelse @as(std.builtin.LinkMode, if (target.result.isGnuLibC()) .dynamic else .static);

    const icu_dep = b.dependency("icu", .{});

    const icui18n = std.Build.Step.Compile.create(b, .{
        .name = "icui18n",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    icui18n.addCSourceFiles(.{
        .root = icu_dep.path("icu4c/source/i18n"),
        .files = collectSources(b, icu_dep.path("icu4c/source/i18n")),
        .flags = &.{
            "-DU_I18N_IMPLEMENTATION=1",
        },
    });

    icui18n.addIncludePath(icu_dep.path("icu4c/source/common"));
    icui18n.addIncludePath(icu_dep.path("icu4c/source/i18n"));
    b.installArtifact(icui18n);

    const icuuc = std.Build.Step.Compile.create(b, .{
        .name = "icuuc",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    icuuc.addCSourceFiles(.{
        .root = icu_dep.path("icu4c/source/common"),
        .files = collectSources(b, icu_dep.path("icu4c/source/common")),
        .flags = &.{
            "-DU_COMMON_IMPLEMENTATION=1",
        },
    });

    icuuc.addIncludePath(icu_dep.path("icu4c/source/common"));
    b.installArtifact(icuuc);
}
