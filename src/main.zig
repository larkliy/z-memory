const std = @import("std");
const mem = @import("memory.zig");
const console = @import("console.zig");
const hexdump = @import("hexdump.zig");
const proc = @import("process.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdin_buffer: [1024]u8 = undefined;
    var stdout_buffer: [1024]u8 = undefined;

    var con = console.Console.init(allocator, &stdin_buffer, &stdout_buffer);
    try con.set_title("Z-Memory");

    con.writeln("Welcome to z-memory!");

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
            printHelpMessage(&con);
            is_example_printed = true;
        }

        con.print("{s} >", .{if (memory) |mem_ptr| mem_ptr.process.name else "Unattached"});

        const command = con.readLine();

        if (!try handleCommands(allocator, &memory, &con, command, false))
            break;

        con.writeln("");
    }
}

fn handleCommands(allocator: std.mem.Allocator, memory: *?mem.Memory, con: *console.Console, command: []const u8, is_cmd_args: bool) !bool {
    if (std.mem.startsWith(u8, command, "exit")) {
        con.write("Exit...");
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
    } else if (std.mem.startsWith(u8, command, "ps")) {
        try handlePs(allocator, con, command);
    } else if (std.mem.startsWith(u8, command, "help")) {
        printHelpMessage(con);
    } else {
        if (is_cmd_args) {
            return error.InvalidCommand;
        } else {
            con.writeln("Unknown command!");
        }
    }

    return true;
}

fn printHelpMessage(con: *console.Console) void {
    const help_text = 
        \\╔════════════════════════════════════════════════════════╗
        \\║                 🛠  Z-Memory Help Menu                  ║
        \\╠════════════════════════════════════════════════════════╣
        \\║ Attach a process:                                      ║
        \\║   attach <ProcessName>                                 ║
        \\║                                                        ║
        \\║ Read memory:                                           ║
        \\║   readbytes <AddressInHex> <SizeInDecimal>             ║
        \\║                                                        ║
        \\║ Write memory:                                          ║
        \\║   write <AddressInHex> <Type[int,float,string]> <Value>║
        \\║                                                        ║
        \\║ List processes:                                        ║
        \\║   ps [filter(optional)]                                ║
        \\║                                                        ║
        \\║ Show help menu:                                        ║
        \\║   help                                                 ║
        \\║                                                        ║
        \\║ Exit the program:                                      ║
        \\║   exit                                                 ║
        \\╚════════════════════════════════════════════════════════╝
        \\
    ;
    con.write(help_text);
}

fn isProcessAttached(memory: ?mem.Memory, con: *console.Console) !bool {
    if (memory == null) {
        con.write("Process is not attached.");
        return false;
    }

    return true;
}

fn handlePs(allocator: std.mem.Allocator, con: *console.Console, command: []const u8) !void {
    const args = try makeCommandArgsList(allocator, command);
    defer allocator.free(args);

    var filter_options: proc.ProcessFilterOptions = undefined;

    if (args.len > 1) {
        const filter_string = args[1];
        filter_options = .{ .should_filter = true, .filter_string = filter_string };
    } else {
        filter_options = .{ .should_filter = false, .filter_string = "" };
    }

    const processes = try proc.Process.getProcesses(allocator, filter_options);

    defer {
        for (processes) |*process| process.deinit();
        allocator.free(processes);
    }

    for (processes) |*process| {
        con.println("Name: {s} | ID: {d}", .{ process.name, process.process_id });
    }

    con.writeln("");
}

fn attachToProcess(allocator: std.mem.Allocator, command: []const u8) !mem.Memory {
    const args = try makeCommandArgsList(allocator, command);
    defer allocator.free(args);

    if (args.len != 2)
        return error.AttachArgsCountNotMatch;

    const process_name = args[1];
    const memory = mem.Memory.init(allocator, process_name);

    return memory;
}

fn makeCommandArgsList(allocator: std.mem.Allocator, command: []const u8) ![][]const u8 {
    var args_list = std.ArrayList([]const u8).empty;

    var it = std.mem.tokenizeScalar(u8, command, ' ');
    while (it.next()) |token|
        try args_list.append(allocator, token);

    return try args_list.toOwnedSlice(allocator);
}

fn handleReadBytes(allocator: std.mem.Allocator, memory: *mem.Memory, con: *console.Console, command: []const u8) !void {
    const args = try makeCommandArgsList(allocator, command);
    defer allocator.free(args);

    if (args.len != 3)
        return error.InvalidReadArgsCount;

    const address_str = args[1];
    const address = try std.fmt.parseInt(usize, address_str, 16);

    const read_size_str = args[2];
    const read_size = try std.fmt.parseInt(u32, read_size_str, 10);

    const read_buf = try allocator.alloc(u8, read_size);
    defer allocator.free(read_buf);

    const read = try memory.read(address, read_buf);

    con.println("Read bytes size: {d}", .{read});

    con.writeln("Read bytes: ");

    try printBytesPretty(allocator, address, con, read_buf);

    con.writeln("");
}

fn handleWrite(allocator: std.mem.Allocator, memory: *mem.Memory, con: *console.Console, command: []const u8) !void {
    const args = try makeCommandArgsList(allocator, command);
    defer allocator.free(args);

    if (args.len != 4)
        return error.InvalidWriteArgsCount;

    const address_str = args[1];
    const address = try std.fmt.parseInt(usize, address_str, 16);

    const type_name = args[2];
    const value = args[3];

    if (std.mem.eql(u8, type_name, "int")) {
        const val = try std.fmt.parseInt(u32, value, 10);
        try memory.write_struct(address, u32, val);
    } else if (std.mem.eql(u8, type_name, "float")) {
        const val = try std.fmt.parseFloat(f32, value);
        try memory.write_struct(address, f32, val);
    } else if (std.mem.eql(u8, type_name, "string")) {
        _ = try memory.write(address, value);
    }

    con.writeln("Successfully!");
}

fn printBytesPretty(allocator: std.mem.Allocator, start_address: usize, con: *console.Console, bytes: []const u8) !void {
    const dump = try hexdump.dump(allocator, start_address, bytes, 12);
    defer allocator.free(dump);

    con.write(dump);
}
