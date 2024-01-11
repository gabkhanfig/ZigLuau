const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

pub const Language = enum {
    lua51,
    lua52,
    lua53,
    lua54,
    luau,
};

pub fn build(b: *Build) void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "shared", "Build shared library instead of static") orelse false;

    const upstream = b.dependency("luau", .{});

    const zigluau = b.addModule("zigluau", .{ .root_source_file = .{ .path = "src/zigluau/lib.zig" } });

    const luauCppLib = buildLuau(b, target, optimize, upstream, shared);

    zigluau.addIncludePath(upstream.path("Common/include"));
    zigluau.addIncludePath(upstream.path("Compiler/include"));
    zigluau.addIncludePath(upstream.path("Ast/include"));
    zigluau.addIncludePath(upstream.path("VM/include"));

    zigluau.linkLibrary(luauCppLib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/zigluau/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("zigluau", zigluau);
    //tests.linkLibrary(zigluau);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run zigluau tests");
    test_step.dependOn(&run_tests.step);
}

fn buildLuau(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, shared: bool) *Step.Compile {
    const lib_opts = .{
        .name = "luau",
        .target = target,
        .optimize = optimize,
        .version = std.SemanticVersion{ .major = 0, .minor = 607, .patch = 0 },
    };
    const lib = if (shared)
        b.addSharedLibrary(lib_opts)
    else
        b.addStaticLibrary(lib_opts);

    lib.addIncludePath(upstream.path("Common/include"));
    lib.addIncludePath(upstream.path("Compiler/include"));
    lib.addIncludePath(upstream.path("Ast/include"));
    lib.addIncludePath(upstream.path("VM/include"));

    const flags = [_][]const u8{
        "-DLUA_USE_LONGJMP=1",
        "-DLUA_API=extern\"C\"",
        "-DLUACODE_API=extern\"C\"",
        "-DLUACODEGEN_API=extern\"C\"",
    };

    for (luau_source_files) |file| {
        lib.addCSourceFile(.{ .file = upstream.path(file), .flags = &flags });
    }
    lib.addCSourceFile(.{ .file = .{ .path = "src/zigluau/luau.cpp" }, .flags = &flags });
    lib.linkLibCpp();

    return lib;
}

const luau_source_files = [_][]const u8{
    "Compiler/src/BuiltinFolding.cpp",
    "Compiler/src/Builtins.cpp",
    "Compiler/src/BytecodeBuilder.cpp",
    "Compiler/src/Compiler.cpp",
    "Compiler/src/ConstantFolding.cpp",
    "Compiler/src/CostModel.cpp",
    "Compiler/src/TableShape.cpp",
    "Compiler/src/Types.cpp",
    "Compiler/src/ValueTracking.cpp",
    "Compiler/src/lcode.cpp",

    "VM/src/lapi.cpp",
    "VM/src/laux.cpp",
    "VM/src/lbaselib.cpp",
    "VM/src/lbitlib.cpp",
    "VM/src/lbuffer.cpp",
    "VM/src/lbuflib.cpp",
    "VM/src/lbuiltins.cpp",
    "VM/src/lcorolib.cpp",
    "VM/src/ldblib.cpp",
    "VM/src/ldebug.cpp",
    "VM/src/ldo.cpp",
    "VM/src/lfunc.cpp",
    "VM/src/lgc.cpp",
    "VM/src/lgcdebug.cpp",
    "VM/src/linit.cpp",
    "VM/src/lmathlib.cpp",
    "VM/src/lmem.cpp",
    "VM/src/lnumprint.cpp",
    "VM/src/lobject.cpp",
    "VM/src/loslib.cpp",
    "VM/src/lperf.cpp",
    "VM/src/lstate.cpp",
    "VM/src/lstring.cpp",
    "VM/src/lstrlib.cpp",
    "VM/src/ltable.cpp",
    "VM/src/ltablib.cpp",
    "VM/src/ltm.cpp",
    "VM/src/ludata.cpp",
    "VM/src/lutf8lib.cpp",
    "VM/src/lvmexecute.cpp",
    "VM/src/lvmload.cpp",
    "VM/src/lvmutils.cpp",

    "Ast/src/Ast.cpp",
    "Ast/src/Confusables.cpp",
    "Ast/src/Lexer.cpp",
    "Ast/src/Location.cpp",
    "Ast/src/Parser.cpp",
    "Ast/src/StringUtils.cpp",
    "Ast/src/TimeTrace.cpp",
};
