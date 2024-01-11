//! Wrapper around Luau C++ API.
//! https://github.com/luau-lang/luau
//! Credit to the ziglua module! Check it out!
//! https://github.com/natecraddock/ziglua

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("luacode.h");
});

/// This function is defined in luau.cpp and must be called to define the assertion printer
extern "c" fn zig_registerAssertionHandler() void;

/// This function is defined in luau.cpp and ensures Zig uses the correct free when compiling luau code
extern "c" fn zig_luau_free(ptr: *anyopaque) void;

const ALIGNMENT = @alignOf(std.c.max_align_t);

/// Allows Lua to allocate memory using a Zig allocator passed in via data.
/// See https://www.lua.org/manual/5.1/manual.html#lua_Alloc for more details
fn alloc(data: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*align(ALIGNMENT) anyopaque {
    // just like malloc() returns a pointer "which is suitably aligned for any built-in type",
    // the memory allocated by this function should also be aligned for any type that Lua may
    // desire to allocate. use the largest alignment for the target
    const allocator: *Allocator = @ptrCast(@alignCast(data.?));

    if (@as(?[*]align(ALIGNMENT) u8, @ptrCast(@alignCast(ptr)))) |prev_ptr| {
        const prev_slice = prev_ptr[0..osize];

        // when nsize is zero the allocator must behave like free and return null
        if (nsize == 0) {
            allocator.free(prev_slice);
            return null;
        }

        // when nsize is not zero the allocator must behave like realloc
        const new_ptr = allocator.realloc(prev_slice, nsize) catch return null;
        return new_ptr.ptr;
    } else if (nsize == 0) {
        return null;
    } else {
        // ptr is null, allocate a new block of memory
        const new_ptr = allocator.alignedAlloc(u8, ALIGNMENT, nsize) catch return null;
        return new_ptr.ptr;
    }
}

pub const CompileOptions = struct {
    // 0 - no optimization
    // 1 - baseline optimization level that doesn't prevent debuggability
    // 2 - includes optimizations that harm debuggability such as inlining
    optimizationLevel: i32 = 1, // default=1

    // 0 - no debugging support
    // 1 - line info & function names only; sufficient for backtraces
    // 2 - full debug info with local & upvalue names; necessary for debugger
    debugLevel: i32 = 1, // default=1

    // 0 - no code coverage support
    // 1 - statement coverage
    // 2 - statement and expression coverage (verbose)
    coverageLevel: i32 = 0, // default=0

    // global builtin to construct vectors; disabled by default
    vectorLib: ?[*:0]const u8 = null,
    vectorCtor: ?[*:0]const u8 = null,

    // vector type name for type tables; disabled by default
    vectorType: ?[*:0]const u8 = null,

    // null-terminated array of globals that are mutable; disables the import optimization for fields accessed through these
    //mutableGlobals: ?[*:0][*:0]u8 = null,
    mutableGlobals: ?[*c]const [*c]const u8 = null,
};

const LuaCompileOptions = c.lua_CompileOptions;

pub const LuauByteCode = struct {
    bytecode: [:0]u8,

    pub fn deinit(self: *LuauByteCode) void {
        zig_luau_free(self.bytecode.ptr);
        self.* = undefined;
    }
};

/// luau_compile()
pub fn compile(source: [:0]const u8, compileOptions: ?*CompileOptions) !LuauByteCode {
    var size: usize = 0;
    const compOptions = compileOptions;
    const opaqueOptions: ?*anyopaque = @ptrCast(compOptions);
    const options = @as(?*LuaCompileOptions, @ptrCast(@alignCast(opaqueOptions)));
    const bytecode = c.luau_compile(source.ptr, source.len, options, &size);

    if (bytecode == null) return error.Memory;

    return LuauByteCode{
        .bytecode = bytecode[0..(size - 1) :0],
    };
}

/// luau_load()
pub fn load(luaState: *LuaState, chunkname: [:0]const u8, bytecode: *LuauByteCode, env: i32) !void {
    const result = c.luau_load(luaState.state, chunkname.ptr, bytecode.bytecode.ptr, bytecode.bytecode.len, env);
    if (result == 1) {
        return error.Fail;
    }
}

pub const LuaState = struct {
    const Self = @This();

    state: *c.lua_State,
    allocator: *Allocator,

    // luaL_newstate()
    pub fn newstate(allocator: Allocator) !Self {
        zig_registerAssertionHandler();

        // the userdata passed to alloc needs to be a pointer with a consistent address
        // so we allocate an Allocator struct to hold a copy of the allocator's data
        const allocator_ptr = try allocator.create(Allocator);
        allocator_ptr.* = allocator;

        const state = c.lua_newstate(alloc, allocator_ptr).?;
        c.luaL_openlibs(state);
        return Self{
            .state = state,
            .allocator = allocator_ptr,
        };
    }
    const init = newstate;

    // lua_close()
    pub fn close(self: *Self) void {
        c.lua_close(self.state);
        self.allocator.destroy(self.allocator);
        self.* = undefined;
    }
    const deinit = close;
};
