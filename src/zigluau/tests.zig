const std = @import("std");
//const Luau = @import("lib.zig");
const Luau = @import("zigluau");
const LuaState = Luau.LuaState;

test "luau newstate" {
    var state = try LuaState.newstate(std.testing.allocator);
    defer state.close();

    //const source = "print(\"hello world!\")";
    //Luau.compile(source, .{});
}

test "luau compile source" {
    var state = try LuaState.newstate(std.testing.allocator);
    defer state.close();

    const source = "print(\"hello world!\")";
    const bytecode = try Luau.compile(source, null);
    defer bytecode.deinit();
}

test "luau load bytecode" {
    var state = try LuaState.newstate(std.testing.allocator);
    defer state.close();

    const source = "print(\"hello world!\")";
    var bytecode = try Luau.compile(source, null);
    defer bytecode.deinit();

    try Luau.load(&state, "...", &bytecode, 0);
}

//test "luau "
