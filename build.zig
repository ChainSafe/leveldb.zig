const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("leveldb", .{});

    const lib = b.addLibrary(.{
        .name = "leveldb",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    // Rough transliteration of the CMakeLists.txt from the original LevelDB repo
    lib.addCSourceFiles(.{
        .root = upstream.path("."),
        .files = &[_][]const u8{
            "db/builder.cc",
            "db/c.cc",
            "db/db_impl.cc",
            "db/db_iter.cc",
            "db/dbformat.cc",
            "db/dumpfile.cc",
            "db/filename.cc",
            "db/log_reader.cc",
            "db/log_writer.cc",
            "db/memtable.cc",
            "db/repair.cc",
            "db/table_cache.cc",
            "db/version_edit.cc",
            "db/version_set.cc",
            "db/write_batch.cc",
            "table/block_builder.cc",
            "table/block.cc",
            "table/filter_block.cc",
            "table/format.cc",
            "table/iterator.cc",
            "table/merger.cc",
            "table/table_builder.cc",
            "table/table.cc",
            "table/two_level_iterator.cc",
            "util/arena.cc",
            "util/bloom.cc",
            "util/cache.cc",
            "util/coding.cc",
            "util/comparator.cc",
            "util/crc32c.cc",
            "util/env.cc",
            "util/filter_policy.cc",
            "util/hash.cc",
            "util/logging.cc",
            "util/options.cc",
            "util/status.cc",
            "helpers/memenv/memenv.cc",
        },
        .flags = &[_][]const u8{
            "-std=c++17",
            "-Wall",
            "-Wextra",
        },
        .language = .cpp,
    });
    lib.addIncludePath(upstream.path("."));
    lib.addIncludePath(upstream.path("include"));
    const port_config_h = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("port/port_config.h.in") },
    }, .{
        .HAVE_FDATASYNC = target.result.os.tag != .windows and target.result.os.tag != .macos,
        .HAVE_FULLFSYNC = target.result.os.tag == .macos,
        .HAVE_0_CLOEXEC = target.result.os.tag != .windows,
        .HAVE_CRC32C = false,
        .HAVE_SNAPPY = true,
        .HAVE_ZSTD = false,
    });
    lib.addConfigHeader(port_config_h);

    lib.root_module.addCMacro("HAVE_SNAPPY", "1");
    const snappy_dep = b.dependency("snappy", .{});
    lib.linkLibrary(snappy_dep.artifact("snappy"));

    if (target.result.os.tag == .windows) {
        lib.root_module.addCMacro("LEVELDB_PLATFORM_WINDOWS", "1");
        lib.addCSourceFiles(.{
            .root = upstream.path("."),
            .files = &[_][]const u8{
                "util/env_windows.cc",
            },
            .flags = &[_][]const u8{
                "-std=c++17",
                "-Wall",
                "-Wextra",
            },
            .language = .cpp,
        });
    } else {
        if (target.result.os.tag == .macos) {
            lib.root_module.addCMacro("HAVE_FULLFSYNC", "1");
        } else {
            lib.root_module.addCMacro("HAVE_FDATASYNC", "1"); // Linux/BSDs
        }

        lib.root_module.addCMacro("HAVE_0_CLOEXEC", "1");
        lib.root_module.addCMacro("LEVELDB_PLATFORM_POSIX", "1");
        lib.addCSourceFiles(.{
            .root = upstream.path("."),
            .files = &[_][]const u8{
                "util/env_posix.cc",
            },
            .flags = &[_][]const u8{
                "-std=c++17",
                "-Wall",
                "-Wextra",
            },
            .language = .cpp,
        });
    }

    lib.installHeadersDirectory(upstream.path("include/leveldb"), "leveldb", .{});
    b.installArtifact(lib);

    const module = b.addModule("leveldb", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.linkLibrary(lib);

    const unit_tests = b.addTest(.{
        .root_module = module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
