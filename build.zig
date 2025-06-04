const std = @import("std");
const mem = std.mem;
const fs = std.fs;

fn collectSources(b: *std.Build, path: std.Build.LazyPath, extensions: []const []const u8) []const []const u8 {
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

        for (extensions) |e| {
            if (mem.eql(u8, ext[1..], e)) {
                list.append(b.allocator.dupe(u8, entry.name) catch @panic("OOM")) catch @panic("OOM");
            }
        }
    }

    return list.toOwnedSlice() catch |e| std.debug.panic("Failed to allocate memory: {s}", .{@errorName(e)});
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "whether to statically or dynamically link the library") orelse @as(std.builtin.LinkMode, if (target.result.isGnuLibC()) .dynamic else .static);

    const icu_dep = b.dependency("icu", .{});

    var icui18n = if (linkage == .static)
        b.addStaticLibrary(.{
            .name = "icui18n",
            .target = target,
            .optimize = optimize,
        })
    else
        b.addSharedLibrary(.{
            .name = "icui18n",
            .target = target,
            .optimize = optimize,
        });
    icui18n.linkLibCpp();

    icui18n.addCSourceFiles(.{
        .root = icu_dep.path("icu4c/source/i18n"),
        .files = collectSources(b, icu_dep.path("icu4c/source/i18n"), &.{ "c", "cpp" }),
        .flags = &.{
            "-DU_I18N_IMPLEMENTATION=1",
        },
    });

    icui18n.installHeadersDirectory(icu_dep.path("icu4c/source/i18n/unicode"), "unicode", .{});

    icui18n.addIncludePath(icu_dep.path("icu4c/source/common"));
    icui18n.addIncludePath(icu_dep.path("icu4c/source/i18n"));
    b.installArtifact(icui18n);

    const icuuc = if (linkage == .static)
        b.addStaticLibrary(.{
            .name = "icuuc",
            .target = target,
            .optimize = optimize,
        })
    else
        b.addSharedLibrary(.{
            .name = "icuuc",
            .target = target,
            .optimize = optimize,
        });
    icuuc.linkLibCpp();

    icuuc.addCSourceFile(.{
        .file = icu_dep.path("icu4c/source/stubdata/stubdata.cpp"),
    });

    icuuc.addCSourceFiles(.{
        .root = icu_dep.path("icu4c/source/common"),
        .files = collectSources(b, icu_dep.path("icu4c/source/common"), &.{ "c", "cpp" }),
        .flags = &.{
            "-DU_COMMON_IMPLEMENTATION=1",
        },
    });

    icuuc.installHeadersDirectory(icu_dep.path("icu4c/source/common/unicode"), "unicode", .{});

    icuuc.addIncludePath(icu_dep.path("icu4c/source/common"));
    b.installArtifact(icuuc);

    const genccode = b.addExecutable(.{
        .name = "genccode",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    genccode.addCSourceFile(.{
        .file = icu_dep.path("icu4c/source/tools/genccode/genccode.c"),
    });

    genccode.addCSourceFiles(.{
        .root = icu_dep.path("icu4c/source/tools/toolutil"),
        .files = &.{
            "filestrm.cpp",
            "pkg_genc.cpp",
            "toolutil.cpp",
            "ucbuf.cpp",
            "uoptions.cpp",
        },
        .flags = &.{
            "-DU_TOOLUTIL_IMPLEMENTATION=1",
        },
    });

    genccode.addIncludePath(icu_dep.path("icu4c/source/tools/toolutil"));
    genccode.addIncludePath(icu_dep.path("icu4c/source/common"));

    genccode.linkLibCpp();
    genccode.linkLibrary(icuuc);

    b.installArtifact(genccode);

    const icupkg = b.addExecutable(.{
        .name = "icupkg",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    icupkg.addCSourceFile(.{
        .file = icu_dep.path("icu4c/source/tools/icupkg/icupkg.cpp"),
    });

    icupkg.addCSourceFiles(.{
        .root = icu_dep.path("icu4c/source/tools/toolutil"),
        .files = &.{
            "filestrm.cpp",
            "pkg_genc.cpp",
            "toolutil.cpp",
            "ucbuf.cpp",
            "uoptions.cpp",
            "pkg_icu.cpp",
            "package.cpp",
            "swapimpl.cpp",
            "uparse.cpp",
            "pkgitems.cpp",
        },
        .flags = &.{
            "-DU_TOOLUTIL_IMPLEMENTATION=1",
        },
    });

    icupkg.addIncludePath(icu_dep.path("icu4c/source/tools/toolutil"));
    icupkg.addIncludePath(icu_dep.path("icu4c/source/common"));
    icupkg.addIncludePath(icu_dep.path("icu4c/source/i18n"));

    icupkg.linkLibCpp();
    icupkg.linkLibrary(icui18n);
    icupkg.linkLibrary(icuuc);

    b.installArtifact(icupkg);
}
