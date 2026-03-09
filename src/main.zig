const std = @import("std");

const mem = @import("memory.zig");


pub fn main() !void {
    const alloc = std.heap.c_allocator;
    var process = try mem.Memory.init(alloc, "notepad.exe");
    defer process.deinit(alloc);

    const address = 0xF3CF1F9598;

    const buffer = try process.read_struct(address, u8);
    std.debug.print("Buffer: {any}\n", .{buffer});
}