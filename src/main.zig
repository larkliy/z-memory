const std = @import("std");
const memory = @import("memory.zig");
const console = @import("console.zig");

fn readSizeAndPrint(mem: *memory.Memory, con: *console.Console, allocator: std.mem.Allocator, address: usize) !void {
    try con.write("Enter the read size: ");
    const cmd_line = try con.readLine();
    
    const parsed_size = try std.fmt.parseInt(usize, cmd_line, 10);

    var buffer = try allocator.alloc(u8, parsed_size);
    defer allocator.free(buffer);

    const read = try mem.read(address, buffer);

    const result_slice = buffer[0..read];

    try con.println("Read {d} bytes:", .{read});

    for (result_slice) |byte| {
        try con.print("{x:0>2} ", .{byte});
    }

    try con.writeln("");
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    
    var stdin_buffer: [1024]u8 = undefined;
    var stdout_buffer: [1024]u8 = undefined;

    var con = console.Console.init(&stdin_buffer, &stdout_buffer);

    try con.write("Enter the process name: ");
    const process_name = try con.readLine();

    var mem = try memory.Memory.init(allocator, process_name);
    defer mem.deinit(allocator);

    try con.write("Enter an address: ");
    const cmd_line = try con.readLine();
    
    const parsed_address = try std.fmt.parseInt(usize, cmd_line, 16);

    // Передаем зависимости в функцию явно
    try readSizeAndPrint(&mem, &con, allocator, parsed_address);
}