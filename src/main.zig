const std = @import("std");
const mem = @import("memory.zig");
const console = @import("console.zig");
const hexdump = @import("hexdump.zig");
const proc = @import("process.zig");

pub const CommandOptions = struct {
    allocator: std.mem.Allocator,
    memory: *mem.Memory,
    console: *console.Console,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
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

    var command_options = CommandOptions{
        .allocator = allocator,
        .console = con,
        .memory = &memory.*.?
    };
    
    if (std.mem.startsWith(u8, command, "exit")) {
        
        con.write("Exit...");
        return false;

    } else if (std.mem.startsWith(u8, command, "attach")) {

        if (memory.*) |*mem_ptr| mem_ptr.deinit();

        memory.* = try attachToProcess(allocator, command);

    } else if (std.mem.startsWith(u8, command, "readbytes")) {

        if (!try isProcessAttached(memory.*, con))
            return true;

        try handleReadBytes(&command_options, command);

    } else if (std.mem.startsWith(u8, command, "write")) {

        if (!try isProcessAttached(memory.*, con))
            return true;

        try handleWrite(&command_options, command);

    } else if (std.mem.startsWith(u8, command, "ps")) {
        try handlePs(&command_options, command);
    } else if (std.mem.startsWith(u8, command, "readmod")) {

        if (!try isProcessAttached(memory.*, con))
            return true;

        try handleReadMod(&command_options, command);

    } else if (std.mem.startsWith(u8, command, "readptr")) {
        
        if (!try isProcessAttached(memory.*, con))
            return true;

        try handleReadPtr(&command_options, command);
    
    } else if (std.mem.startsWith(u8, command, "writeptr")) {

        // TODO
        
    } else if (std.mem.startsWith(u8, command, "writemod")) {
        
        try handleWriteMod(&command_options, command);
        
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
        \\Z-Memory Help
        \\
        \\Attach a process
        \\  attach <ProcessName>
        \\
        \\Read memory
        \\  readbytes <AddressInHex> <SizeInDecimal>
        \\
        \\Read Module+Address with type support.
        \\  readmod   <module.dll+RelativeAddress> <int/float/string/bytes:size>
        \\
        \\Read Module+Address+AdditionalAddresses with type support.
        \\  readptr   <module.dll+RelativeAddress+AdditionalAddresses> <int/float/string>
        \\
        \\Write memory
        \\  write     <AddressInHex> <int/float/string> <Value>
        \\
        \\  writemod  <module.dll+RelativeAddress> <int/float/string> <Value>
        \\
        \\List processes
        \\  ps [filter(optional)]
        \\
        \\Show help
        \\  help
        \\
        \\Exit
        \\  exit
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

fn handleReadPtr(options: *CommandOptions, command: []const u8) !void {
    const args = try makeCommandArgsList(options.allocator, command);
    defer options.allocator.free(args);

    var module_and_addresses = std.mem.tokenizeScalar(u8, args[1], '+');

    const module_name = module_and_addresses.next().?;
    const rel_address_str = module_and_addresses.next().?;

    const rel_address = try std.fmt.parseInt(usize, rel_address_str, 16);

    var additional_addresses = std.ArrayList(usize).empty;
    defer additional_addresses.deinit(options.allocator);

    while (module_and_addresses.next()) |addr_str| {

        const add_addr = std.fmt.parseInt(usize, addr_str, 16) catch break;
        try additional_addresses.append(options.allocator, add_addr);
    }

    if (additional_addresses.items.len == 0)
        return error.InvalidReadPtrArgs;

    const absolute_address = try getAbsoluteAddress(options, module_name, rel_address);
    const type_name = args[2];

    var read_addr = try options.memory.read_struct(absolute_address, usize);

    for (additional_addresses.items) |address| {
        read_addr = try options.memory.read_struct(read_addr + address, usize);
    }

    if (std.mem.eql(u8, type_name, "int")) {
        const read_value = try options.memory.read_struct(read_addr, u32);
        options.console.print("Int read: {d}", .{ read_value });
    } else if (std.mem.eql(u8, type_name, "float")) {
        const read_value = try options.memory.read_struct(read_addr, f32);
        options.console.print("Float read: {d}", .{ read_value });
    } else if (std.mem.eql(u8, type_name, "string")) {
        const string_read = try options.memory.read_string(read_addr);
        defer options.allocator.free(string_read);

        options.console.print("String read: {s}", .{ string_read });
    }
}

fn handleWriteMod(options: *CommandOptions, command: []const u8) !void {
    const args = try makeCommandArgsList(options.allocator, command);
    defer options.allocator.free(args);

    var module_and_addr = std.mem.tokenizeScalar(u8, args[1], '+');

    const module_name = module_and_addr.next().?;
    const rel_address_str = module_and_addr.next().?;

    const rel_address = try std.fmt.parseInt(usize, rel_address_str, 16);

    const absolute_address = try getAbsoluteAddress(options, module_name, rel_address);

    const type_name = args[2];

    if (std.mem.eql(u8, type_name, "int")) {
        const val = try std.fmt.parseInt(u32, args[3], 10);
        try options.memory.write_struct(absolute_address, u32, val);
    } else if (std.mem.eql(u8, type_name, "float")) {
        const val = try std.fmt.parseFloat(f32, args[3]);
        try options.memory.write_struct(absolute_address, f32, val);
    } else {
        return error.InvalidWriteModType;
    }
}

fn handleReadMod(options: *CommandOptions, command: []const u8) !void {

    const args = try makeCommandArgsList(options.allocator, command);
    defer options.allocator.free(args);

    var module_and_addr = std.mem.tokenizeScalar(u8, args[1], '+');

    const module_name = module_and_addr.next().?;
    const rel_address_str = module_and_addr.next().?;
    const rel_address = try std.fmt.parseInt(usize, rel_address_str, 16);
    const absolute_address = try getAbsoluteAddress(options, module_name, rel_address);

    const type_name = args[2];

    if (std.mem.eql(u8, type_name, "int")) {
        const value = try options.memory.read_struct(absolute_address, i32);

        options.console.print("Value: {d}", .{value});
    } else if (std.mem.eql(u8, type_name, "float")) {
        const value = try options.memory.read_struct(absolute_address, f32);

        options.console.print("Value: {d}", .{value});
    } else if (std.mem.startsWith(u8, type_name, "bytes:")) {
        var type_and_size = std.mem.tokenizeScalar(u8, type_name, ':');

        _ = type_and_size.next(); // "bytes" keyword

        const read_size = try std.fmt.parseInt(u32, type_and_size.next().?, 10);

        const read_buf = try options.allocator.alloc(u8, read_size);
        defer options.allocator.free(read_buf);

        const read = try options.memory.read(absolute_address, read_buf);

        options.console.println("Read bytes size: {d}", .{read});

        options.console.writeln("Read bytes: ");

        try printBytesPretty(options, absolute_address, read_buf);
    }
}

fn getAbsoluteAddress(options: *CommandOptions, module_name: []const u8, rel_address: usize) !usize {
    var module = try options.memory.process.getModuleBaseAddress(module_name);
    defer module.deinit();

    return rel_address + module.base;
}

fn handlePs(options: *CommandOptions, command: []const u8) !void {
    const args = try makeCommandArgsList(options.allocator, command);
    defer options.allocator.free(args);

    var filter_options: proc.ProcessFilterOptions = undefined;

    if (args.len > 1) {
        const filter_string = args[1];
        filter_options = .{ .should_filter = true, .filter_string = filter_string };
    } else {
        filter_options = .{ .should_filter = false, .filter_string = "" };
    }

    const processes = try proc.Process.getProcesses(options.allocator, filter_options);

    defer {
        for (processes) |*process| process.deinit();
        options.allocator.free(processes);
    }

    for (processes) |*process| {
        options.console.println("Name: {s} | ID: {d}", .{ process.name, process.process_id });
    }

    options.console.writeln("");
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

fn handleReadBytes(options: *CommandOptions, command: []const u8) !void {
    const args = try makeCommandArgsList(options.allocator, command);
    defer options.allocator.free(args);

    if (args.len != 3)
        return error.InvalidReadArgsCount;

    const address_str = args[1];
    const address = try std.fmt.parseInt(usize, address_str, 16);

    const read_size_str = args[2];
    const read_size = try std.fmt.parseInt(u32, read_size_str, 10);

    const read_buf = try options.allocator.alloc(u8, read_size);
    defer options.allocator.free(read_buf);

    const read = try options.memory.read(address, read_buf);

    options.console.println("Read bytes size: {d}", .{read});

    options.console.writeln("Read bytes: ");

    try printBytesPretty(options, address, read_buf);

    options.console.writeln("");
}

fn handleWrite(options: *CommandOptions, command: []const u8) !void {
    const args = try makeCommandArgsList(options.allocator, command);
    defer options.allocator.free(args);

    if (args.len != 4)
        return error.InvalidWriteArgsCount;

    const address_str = args[1];
    const address = try std.fmt.parseInt(usize, address_str, 16);

    const type_name = args[2];
    const value = args[3];

    if (std.mem.eql(u8, type_name, "int")) {
        const val = try std.fmt.parseInt(u32, value, 10);
        try options.memory.write_struct(address, u32, val);
    } else if (std.mem.eql(u8, type_name, "float")) {
        const val = try std.fmt.parseFloat(f32, value);
        try options.memory.write_struct(address, f32, val);
    } else if (std.mem.eql(u8, type_name, "string")) {
        _ = try options.memory.write(address, value);
    }

    options.console.writeln("Successfully!");
}

fn printBytesPretty(options: *CommandOptions, start_address: usize, bytes: []const u8) !void {
    const dump = try hexdump.dump(options.allocator, start_address, bytes, 12);
    defer options.allocator.free(dump);

    options.console.write(dump);
}
