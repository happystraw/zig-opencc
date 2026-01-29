//! OpenCC (Open Chinese Convert) Zig Build Script
//!
//! This build script compiles OpenCC library and provides a Zig module.
//!
//! Build Options:
//!   -Dtarget=<triple>              Target platform (default: native)
//!                                  Examples: x86_64-windows, aarch64-macos, aarch64-linux
//!   -Doptimize=<mode>              Optimization mode (default: Debug)
//!                                  Options: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall
//!   -Dbuild-exe=<bool>             Build CLI executables (default: true)
//!   -Dbuild-dict=<bool>            Generate dictionaries (default: true)
//!   -Dpkg-data-dir=<path>          Data directory (default: {prefix}/share/opencc)
//!
//! Build Steps:
//!   zig build                      Build everything (library + executables + dictionaries)
//!   zig build lib                  Build only the static library and headers
//!   zig build exe                  Build only executables (opencc, opencc_dict, opencc_phrase_extract)
//!   zig build dict                 Generate and install dictionaries
//!   zig build test                 Run tests
//!
//! Cross-compilation Examples:
//!   zig build -Dtarget=x86_64-windows
//!   zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast
//!   zig build -Dtarget=aarch64-linux -Dbuild-exe=false

const BuildOptions = struct {
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_exe: bool,
    build_dict: bool,
    pkg_config_header: *Build.Step.ConfigHeader,
    pkg_name: []const u8,
    pkg_version: []const u8,
    pkg_data_dir: []const u8,
};

pub fn build(b: *Build) void {
    const build_options = buildOptions(b);

    // ------ OpenCC ------

    const lib = library(b, build_options);
    const lib_step = libraryStep(b, build_options, lib);
    b.getInstallStep().dependOn(lib_step);

    const exe_step = buildExecutablesStep(b, build_options, lib);
    if (build_options.build_exe) b.getInstallStep().dependOn(exe_step);

    const dict_step = buildDictionariesStep(b, build_options);
    if (build_options.build_dict) b.getInstallStep().dependOn(dict_step);

    // ------ Zig Module ------

    const opencc_dep = b.dependency("opencc", .{});
    const opencc_c = b.addTranslateC(.{
        .root_source_file = opencc_dep.path("src/opencc.h"),
        .target = build_options.target,
        .optimize = build_options.optimize,
    });

    const mod = b.addModule("opencc", .{
        .root_source_file = b.path("src/opencc.zig"),
        .target = build_options.target,
        .optimize = build_options.optimize,
        .imports = &.{
            .{ .name = "c", .module = opencc_c.createModule() },
        },
    });
    mod.linkLibrary(lib);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    run_mod_tests.step.dependOn(dict_step);
    test_step.dependOn(&run_mod_tests.step);
}

fn buildOptions(b: *Build) BuildOptions {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const default_pkg_data_dir = if (target.query.isNative())
        b.fmt("{s}/share/opencc", .{normalizePath(b.allocator, b.install_prefix) catch b.install_prefix})
    else
        "";

    const build_exe = b.option(bool, "build-exe", "Build opencc, opencc_dict, opencc_phrase_extract. default: true") orelse true;
    const build_dict = b.option(bool, "build-dict", "Generate and build opencc builtin dictionaries. default: true") orelse true;
    const pkg_data_dir = b.option([]const u8, "pkg-data-dir", b.fmt("Opencc package data directory. default: \"{s}\"", .{default_pkg_data_dir})) orelse default_pkg_data_dir;

    return .{
        .target = target,
        .optimize = optimize,
        .build_exe = build_exe,
        .build_dict = build_dict,
        .pkg_config_header = configHeader(b),
        .pkg_name = "\"opencc\"",
        .pkg_version = "\"1.2.0\"",
        .pkg_data_dir = b.fmt("\"{s}\"", .{pkg_data_dir}),
    };
}

fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const normalized = try allocator.dupe(u8, path);
    for (normalized) |*c| {
        if (c.* == '\\') {
            c.* = '/';
        }
    }
    return normalized;
}

fn configHeader(b: *Build) *std.Build.Step.ConfigHeader {
    const dep = b.dependency("opencc", .{});
    return b.addConfigHeader(
        .{
            .style = .{ .cmake = dep.path("src/opencc_config.h.in") },
            .include_path = "opencc_config.h",
        },
        .{
            .OPENCC_ENABLE_DARTS = null, // 默认不启用 DARTS 支持
        },
    );
}

fn libraryStep(b: *Build, opts: BuildOptions, lib_opencc: *Build.Step.Compile) *Build.Step {
    const lib_step = b.step("lib", "Build only the static library and headers");
    installHeaderFiles(b, lib_step, opts.pkg_config_header);
    lib_step.dependOn(&b.addInstallArtifact(lib_opencc, .{}).step);
    return lib_step;
}

fn library(b: *Build, opts: BuildOptions) *std.Build.Step.Compile {
    const dep = b.dependency("opencc", .{});
    const lib_marisa = libraryMarisa(b, opts.target, opts.optimize);

    const sources = [_][]const u8{
        "src/Config.cpp",
        "src/Conversion.cpp",
        "src/ConversionChain.cpp",
        "src/Converter.cpp",
        "src/Dict.cpp",
        "src/DictConverter.cpp",
        "src/DictEntry.cpp",
        "src/DictGroup.cpp",
        "src/Lexicon.cpp",
        "src/MarisaDict.cpp",
        "src/MaxMatchSegmentation.cpp",
        "src/PhraseExtract.cpp",
        "src/SerializedValues.cpp",
        "src/SimpleConverter.cpp",
        "src/Segmentation.cpp",
        "src/TextDict.cpp",
        "src/UTF8StringSlice.cpp",
        "src/UTF8Util.cpp",
    };

    const mod = b.createModule(.{
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libcpp = true,
    });

    mod.addCSourceFiles(.{
        .root = dep.path(""),
        .files = &sources,
        .flags = &[_][]const u8{
            "-std=c++17",
            "-Wall",
            "-fno-delete-null-pointer-checks",
        },
    });

    mod.addIncludePath(dep.path("src"));
    mod.addIncludePath(dep.path("deps/marisa-0.2.6/include"));
    mod.addIncludePath(dep.path("deps/rapidjson-1.1.0"));
    mod.addIncludePath(dep.path("deps/tclap-1.2.5"));
    mod.addConfigHeader(opts.pkg_config_header);

    mod.addCMacro("PACKAGE_NAME", opts.pkg_name);
    mod.addCMacro("VERSION", opts.pkg_version);
    mod.addCMacro("PKGDATADIR", opts.pkg_data_dir);
    mod.addCMacro("Opencc_BUILT_AS_STATIC", "1");

    mod.linkLibrary(lib_marisa);

    return b.addLibrary(.{
        .name = "opencc",
        .root_module = mod,
        .linkage = .static,
    });
}
fn libraryMarisa(b: *Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const dep = b.dependency("opencc", .{});
    const sources = [_][]const u8{
        "deps/marisa-0.2.6/lib/marisa/trie.cc",
        "deps/marisa-0.2.6/lib/marisa/agent.cc",
        "deps/marisa-0.2.6/lib/marisa/grimoire/io/reader.cc",
        "deps/marisa-0.2.6/lib/marisa/grimoire/io/writer.cc",
        "deps/marisa-0.2.6/lib/marisa/grimoire/io/mapper.cc",
        "deps/marisa-0.2.6/lib/marisa/grimoire/trie/louds-trie.cc",
        "deps/marisa-0.2.6/lib/marisa/grimoire/trie/tail.cc",
        "deps/marisa-0.2.6/lib/marisa/grimoire/vector/bit-vector.cc",
        "deps/marisa-0.2.6/lib/marisa/keyset.cc",
    };

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });

    mod.addCSourceFiles(.{
        .root = dep.path(""),
        .files = &sources,
        .flags = &[_][]const u8{
            "-std=c++17",
            "-fPIC",
        },
    });
    mod.addIncludePath(dep.path("deps/marisa-0.2.6/include"));
    mod.addIncludePath(dep.path("deps/marisa-0.2.6/lib"));

    return b.addLibrary(.{
        .name = "marisa",
        .root_module = mod,
        .linkage = .static,
    });
}

fn installHeaderFiles(
    b: *Build,
    lib_step: *Build.Step,
    config_header: *std.Build.Step.ConfigHeader,
) void {
    const dep = b.dependency("opencc", .{});
    const header_files = [_][]const u8{
        "opencc.h",
        "Common.hpp",
        "Config.hpp",
        "Conversion.hpp",
        "ConversionChain.hpp",
        "Converter.hpp",
        "Dict.hpp",
        "DictConverter.hpp",
        "DictEntry.hpp",
        "DictGroup.hpp",
        "Exception.hpp",
        "Export.hpp",
        "Lexicon.hpp",
        "MarisaDict.hpp",
        "MaxMatchSegmentation.hpp",
        "Optional.hpp",
        "PhraseExtract.hpp",
        "Segmentation.hpp",
        "Segments.hpp",
        "SerializableDict.hpp",
        "SerializedValues.hpp",
        "SimpleConverter.hpp",
        "TextDict.hpp",
        "UTF8StringSlice.hpp",
        "UTF8Util.hpp",
        "BinaryDict.hpp",
        "DartsDict.hpp",
    };

    inline for (header_files) |header| {
        const install_header = b.addInstallHeaderFile(
            dep.path(b.fmt("src/{s}", .{header})),
            b.fmt("opencc/{s}", .{header}),
        );
        lib_step.dependOn(&install_header.step);
    }

    const install_config_header = b.addInstallHeaderFile(
        config_header.getOutputFile(),
        "opencc/opencc_config.h",
    );
    lib_step.dependOn(&install_config_header.step);
}

fn buildExecutablesStep(b: *Build, opts: BuildOptions, lib_opencc: *Build.Step.Compile) *Build.Step {
    const exe_step = b.step("exe", "Build only executables (opencc, opencc_dict, opencc_phrase_extract)");

    const exe = executable(b, opts, lib_opencc);
    const exe_dict = executableDict(b, opts, lib_opencc);
    const exe_phrase_extract = executablePhraseExtract(b, opts, lib_opencc);

    exe_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    exe_step.dependOn(&b.addInstallArtifact(exe_dict, .{}).step);
    exe_step.dependOn(&b.addInstallArtifact(exe_phrase_extract, .{}).step);

    return exe_step;
}

fn executable(b: *Build, opts: BuildOptions, lib_opencc: *Build.Step.Compile) *Build.Step.Compile {
    const dep = b.dependency("opencc", .{});

    const mod = b.createModule(.{
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libcpp = true,
    });

    mod.addCSourceFile(.{
        .file = dep.path("src/tools/CommandLine.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-Wall",
        },
    });

    mod.addIncludePath(dep.path("."));
    mod.addIncludePath(dep.path("src"));
    mod.addIncludePath(dep.path("deps/marisa-0.2.6/include"));
    mod.addIncludePath(dep.path("deps/rapidjson-1.1.0"));
    mod.addIncludePath(dep.path("deps/tclap-1.2.5"));
    mod.addConfigHeader(opts.pkg_config_header);

    mod.addCMacro("PACKAGE_NAME", opts.pkg_name);
    mod.addCMacro("VERSION", opts.pkg_version);
    mod.addCMacro("PKGDATADIR", opts.pkg_data_dir);
    mod.addCMacro("Opencc_BUILT_AS_STATIC", "1");

    mod.linkLibrary(lib_opencc);

    return b.addExecutable(.{
        .name = "opencc",
        .root_module = mod,
    });
}

fn executableDict(b: *Build, opts: BuildOptions, lib_opencc: *Build.Step.Compile) *Build.Step.Compile {
    const dep = b.dependency("opencc", .{});

    const mod = b.createModule(.{
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libcpp = true,
    });

    mod.addCSourceFile(.{
        .file = dep.path("src/tools/DictConverter.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-Wall",
        },
    });

    mod.addIncludePath(dep.path("."));
    mod.addIncludePath(dep.path("src"));
    mod.addIncludePath(dep.path("deps/marisa-0.2.6/include"));
    mod.addIncludePath(dep.path("deps/rapidjson-1.1.0"));
    mod.addIncludePath(dep.path("deps/tclap-1.2.5"));
    mod.addConfigHeader(opts.pkg_config_header);

    mod.addCMacro("VERSION", opts.pkg_version);
    mod.addCMacro("Opencc_BUILT_AS_STATIC", "1");

    mod.linkLibrary(lib_opencc);

    return b.addExecutable(.{
        .name = "opencc_dict",
        .root_module = mod,
    });
}

fn executablePhraseExtract(b: *Build, opts: BuildOptions, lib_opencc: *Build.Step.Compile) *Build.Step.Compile {
    const dep = b.dependency("opencc", .{});

    const mod = b.createModule(.{
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libcpp = true,
    });

    mod.addCSourceFile(.{
        .file = dep.path("src/tools/PhraseExtract.cpp"),
        .flags = &[_][]const u8{
            "-std=c++17",
            "-Wall",
        },
    });

    mod.addIncludePath(dep.path("."));
    mod.addIncludePath(dep.path("src"));
    mod.addIncludePath(dep.path("deps/marisa-0.2.6/include"));
    mod.addIncludePath(dep.path("deps/rapidjson-1.1.0"));
    mod.addIncludePath(dep.path("deps/tclap-1.2.5"));
    mod.addConfigHeader(opts.pkg_config_header);

    mod.addCMacro("VERSION", opts.pkg_version);
    mod.addCMacro("Opencc_BUILT_AS_STATIC", "1");

    mod.linkLibrary(lib_opencc);

    return b.addExecutable(.{
        .name = "opencc_phrase_extract",
        .root_module = mod,
    });
}

fn executableToolReverseDict(b: *Build, opts: BuildOptions) *Build.Step.Compile {
    // 构建 reverse_dict 工具（纯 Zig 实现，替代 Python 脚本 data/scripts/reverse.py）
    return b.addExecutable(.{
        .name = "reverse_dict",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/reverse_dict.zig"),
            .target = opts.target,
        }),
    });
}

fn buildDictionariesStep(b: *Build, opts: BuildOptions) *Build.Step {
    const dict_step = b.step("dict", "Generate and install dictionaries");
    const dep = b.dependency("opencc", .{});

    var native_opts = opts;
    native_opts.target = b.graph.host;

    const lib_opencc = library(b, native_opts);
    const reverse_dict_exe = executableToolReverseDict(b, native_opts);
    const opencc_dict_exe = executableDict(b, native_opts, lib_opencc);

    const dicts_to_generate = [_]struct {
        input: []const u8,
        output: []const u8,
    }{
        .{ .input = "TWVariants", .output = "TWVariantsRev" },
        .{ .input = "HKVariants", .output = "HKVariantsRev" },
        .{ .input = "JPVariants", .output = "JPVariantsRev" },
    };

    inline for (dicts_to_generate) |dict_gen| {
        const gen_cmd = b.addRunArtifact(reverse_dict_exe);
        gen_cmd.addFileArg(dep.path(b.fmt("data/dictionary/{s}.txt", .{dict_gen.input})));
        const output_txt = gen_cmd.addOutputFileArg(b.fmt("{s}.txt", .{dict_gen.output}));

        const convert_cmd = b.addRunArtifact(opencc_dict_exe);
        convert_cmd.addArg("--input");
        convert_cmd.addFileArg(output_txt);
        convert_cmd.addArg("--from");
        convert_cmd.addArg("text");
        convert_cmd.addArg("--to");
        convert_cmd.addArg("ocd2");
        convert_cmd.addArg("--output");
        const ocd2_output = convert_cmd.addOutputFileArg(b.fmt("{s}.ocd2", .{dict_gen.output}));

        const install_dict = b.addInstallFile(
            ocd2_output,
            b.fmt("share/opencc/{s}.ocd2", .{dict_gen.output}),
        );
        dict_step.dependOn(&install_dict.step);
    }

    const dicts_list = [_][]const u8{
        "STCharacters",
        "STPhrases",
        "TSCharacters",
        "TSPhrases",
        "TWPhrases",
        "TWPhrasesRev",
        "TWVariants",
        "TWVariantsRevPhrases",
        "HKVariants",
        "HKVariantsRevPhrases",
        "JPVariants",
        "JPShinjitaiCharacters",
        "JPShinjitaiPhrases",
    };

    inline for (dicts_list) |dict_name| {
        const convert_cmd = b.addRunArtifact(opencc_dict_exe);
        convert_cmd.addArg("--input");
        convert_cmd.addFileArg(dep.path(b.fmt("data/dictionary/{s}.txt", .{dict_name})));
        convert_cmd.addArg("--from");
        convert_cmd.addArg("text");
        convert_cmd.addArg("--to");
        convert_cmd.addArg("ocd2");
        convert_cmd.addArg("--output");
        const ocd2_output = convert_cmd.addOutputFileArg(b.fmt("{s}.ocd2", .{dict_name}));

        const install_dict = b.addInstallFile(
            ocd2_output,
            b.fmt("share/opencc/{s}.ocd2", .{dict_name}),
        );
        dict_step.dependOn(&install_dict.step);
    }

    const config_files = [_][]const u8{
        "hk2s.json",
        "hk2t.json",
        "jp2t.json",
        "s2hk.json",
        "s2t.json",
        "s2tw.json",
        "s2twp.json",
        "t2hk.json",
        "t2jp.json",
        "t2s.json",
        "t2tw.json",
        "tw2s.json",
        "tw2sp.json",
        "tw2t.json",
    };

    inline for (config_files) |config_file| {
        const install_config = b.addInstallFile(
            dep.path(b.fmt("data/config/{s}", .{config_file})),
            b.fmt("share/opencc/{s}", .{config_file}),
        );
        dict_step.dependOn(&install_config.step);
    }

    return dict_step;
}

const std = @import("std");
const Build = std.Build;
