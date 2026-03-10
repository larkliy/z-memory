const std = @import("std");
const mem = @import("memory.zig");
const console = @import("console.zig");
const hexdump = @import("hexdump.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdin_buffer: [1024]u8 = undefined;
    var stdout_buffer: [1024]u8 = undefined;

    var con = console.Console.init(allocator, &stdin_buffer, &stdout_buffer);
    try con.set_title("Z-Memory");

    try con.writeln("Welcome to z-memory!");

    var memory: ?mem.Memory = null;
    defer if (memory) |*mem_ptr| mem_ptr.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        const args_slice = args[1..];

        if (args_slice.len < 1)
            return error.TooFewProcessAttachArgs;

        const process_name = args_slice[0];
        
        const attach_str = try std.fmt.allocPrint(allocator, "attach {s}", .{process_name});
        defer allocator.free(attach_str);

        memory = try attachToProcess(allocator, attach_str);
        
        const command = try std.mem.join(allocator, " ", args_slice[1..]);
        defer allocator.free(command);
        
        _ = try handleCommands(allocator, &memory, &con, command, true);

        return;
    }

    var is_example_printed = false;

    while (true) {
        if (!is_example_printed) {
            try con.write("Before everything write the command 'attach <ProcessName>' to attach the specified process.'");
            try con.writeln("And after put the command like this: readbytes <AddressInHex> <SizeInDecimal>");
            try con.writeln("Or: write <AddressInHex> <Type[int, float, string]> <Value>");
            try con.writeln("Example: read 0x00400000 10");
            try con.writeln("Enter the 'exit' command to quit.");

            try con.writeln("");
            try con.writeln("");
            is_example_printed = true;
        }

        // Process attach status
        try con.print("{s} >", .{if (memory) |mem_ptr| mem_ptr.process.name else "Unattached"});

        const command = try con.readLine();

        if (!try handleCommands(allocator, &memory, &con, command, false))
            break;

        try con.writeln("");
    }
}

fn handleCommands(allocator: std.mem.Allocator, memory: *?mem.Memory, con: *console.Console, command: []const u8, is_cmd_args: bool) !bool {

    if (std.mem.startsWith(u8, command, "exit")) {
        try con.write("Exit...");
        return false;
    } else if (std.mem.startsWith(u8, command, "attach")) {
        if (memory.*) |*mem_ptr| mem_ptr.deinit();

        memory.* = try attachToProcess(allocator, command);

    } else if (std.mem.startsWith(u8, command, "readbytes")) {

        if (!try isProcessAttached(memory.*, con))
            return true;

        try handleReadBytes(allocator, &memory.*.?, con, command);
    } else if (std.mem.startsWith(u8, command, "write")) {
        if (!try isProcessAttached(memory.*, con))
            return true;

        try handleWrite(allocator, &memory.*.?, con, command);


    } else {
        if (is_cmd_args) {
            return error.InvalidCommand;
        } else {
            try con.writeln("Unknown command!");
        }
    }


    return true;
}

fn isProcessAttached(memory: ?mem.Memory, con: *console.Console) !bool {
    if (memory == null) {
        try con.write("Process is not attached.");
        return false;
    }

    return true;
}

fn attachToProcess(allocator: std.mem.Allocator, command: []const u8) !mem.Memory {
    var args_list = try makeCommandArgsList(allocator, command);
    defer args_list.deinit(allocator);

    if (args_list.items.len != 2)
        return error.AttachArgsCountNotMatch;

    const process_name = args_list.items[1];
    const memory = mem.Memory.init(allocator, process_name);

    return memory;
}

fn makeCommandArgsList(allocator: std.mem.Allocator, command: []const u8) !std.ArrayList([]const u8) {
    var args_list = std.ArrayList([]const u8).empty;

    var it = std.mem.tokenizeScalar(u8, command, ' ');
    while (it.next()) |token|
        try args_list.append(allocator, token);

    return args_list;
}

fn handleReadBytes(allocator: std.mem.Allocator, memory: *mem.Memory, con: *console.Console, command: []const u8) !void {
    var args_list = try makeCommandArgsList(allocator, command);
    defer args_list.deinit(allocator);

    if (args_list.items.len != 3)
        return error.InvalidReadArgsCount;

    const address_str = args_list.items[1];
    const address = try std.fmt.parseInt(usize, address_str, 16);

    const read_size_str = args_list.items[2];
    const read_size = try std.fmt.parseInt(u32, read_size_str, 10);

    const read_buf = try allocator.alloc(u8, read_size);
    defer allocator.free(read_buf);

    const read = try memory.read(address, read_buf);

    try con.println("Read bytes size: {d}", .{read});

    try con.writeln("Read bytes: ");

    // for (read_buf[0..read]) |byte| {
    //     try con.print("{X:0>2} ", .{byte});
    // }

    try printBytesPretty(allocator, con, read_buf);

    try con.writeln("");
}

fn handleWrite(allocator: std.mem.Allocator, memory: *mem.Memory, con: *console.Console, command: []const u8) !void {
    var args_list = try makeCommandArgsList(allocator, command);
    defer args_list.deinit(allocator);

    if (args_list.items.len != 4)
        return error.InvalidWriteArgsCount;

    const address_str = args_list.items[1];
    const address = try std.fmt.parseInt(usize, address_str, 16);

    const type_name = args_list.items[2];
    const value = args_list.items[3];

    if (std.mem.eql(u8, type_name, "int")) {
        const val = try std.fmt.parseInt(u32, value, 10);
        try memory.write_struct(address, u32, val);
    } else if (std.mem.eql(u8, type_name, "float")) {
        const val = try std.fmt.parseFloat(f32, value);
        try memory.write_struct(address, f32, val);
    } else if (std.mem.eql(u8, type_name, "string")) {
        _ = try memory.write(address, value);
    }

    try con.writeln("Successfully!");
}

fn printBytesPretty(allocator: std.mem.Allocator, con: *console.Console, bytes: []const u8) !void {
    const dump = try hexdump.dump(allocator, bytes, 10);
    defer allocator.free(dump);

    try con.write(dump);
}
