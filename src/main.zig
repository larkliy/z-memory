const std = @import("std");
const memory = @import("memory.zig");
const console = @import("console.zig");



pub fn main() !void {
    const allocator = std.heap.c_allocator;
    
    var stdin_buffer: [1024]u8 = undefined;
    var stdout_buffer: [1024]u8 = undefined;

    var con = console.Console.init(&stdin_buffer, &stdout_buffer);

    try con.writeln("Welcome to z-memory!");
    
    var is_example_printed = false;

    while (true) {

        if (!is_example_printed) {
            try con.writeln("Enter the command like this: readbytes <ProcessName.exe> <AddressInHex> <SizeInDecimal>");
            try con.writeln("Or: write <ProcessName.exe> <AddressInHex> <Type[int, float, string]> <Value>");
            try con.writeln("Example: read notepad.exe 0x00400000 10");
            try con.writeln("Enter the 'exit' command to quit.");
            is_example_printed = true;
        }

        try con.write("> ");
        const command = try con.readLine();

        if (std.mem.startsWith(u8, command, "exit")) {
            try con.write("Exit...");
            break;
        } else if (std.mem.startsWith(u8, command, "readbytes")) {

            var args_list = std.ArrayList([]const u8).empty;
            defer args_list.deinit(allocator);

            var it = std.mem.tokenizeScalar(u8, command, ' ');
            _ = it.next(); // Skip the command itself
            while (it.next()) |token|
                try args_list.append(allocator, token);

            if (args_list.items.len != 3)
                return error.InvalidReadArgsCount;
            
            const process_name = args_list.items[0];

            var mem = try memory.Memory.init(allocator, process_name);
            defer mem.deinit(allocator);
            
            const address_str = args_list.items[1];
            const address = try std.fmt.parseInt(usize, address_str, 16);

            const read_size_str = args_list.items[2];
            const read_size = try std.fmt.parseInt(u32, read_size_str, 10);

            const read_buf = try allocator.alloc(u8, read_size);
            defer allocator.free(read_buf);

            const read = try mem.read(address, read_buf);

            try con.println("Read bytes size: {d}", .{read});

            try con.write("Read bytes: ");
            
            for (read_buf[0..read]) |byte| {
                try con.print("{X:0>2} ", .{byte});
            }

            try con.writeln("");
            
        } else if (std.mem.startsWith(u8, command, "write"))  {

            var args_list = std.ArrayList([]const u8).empty;
            defer args_list.deinit(allocator);

            var it = std.mem.tokenizeScalar(u8, command, ' ');
            _ = it.next(); // Skip the command itself
            while (it.next()) |token|
                try args_list.append(allocator, token);

            if (args_list.items.len != 4)
                return error.InvalidWriteArgsCount;

            const process_name = args_list.items[0];

            var mem = try memory.Memory.init(allocator, process_name);
            defer mem.deinit(allocator);

            const address_str = args_list.items[1];
            const address = try std.fmt.parseInt(usize, address_str, 16);

            const type_name = args_list.items[1];
            const value = args_list.items[2];

            if (std.mem.eql(u8, type_name, "int")) {

                const val = try std.fmt.parseInt(u32, value, 10);
                try mem.write_struct(address, u32, val);

            } else if (std.mem.eql(u8, type_name, "float")) {

                const val = try std.fmt.parseFloat(f32, value);
                try mem.write_struct(address, f32, val);

            } else if (std.mem.eql(u8, type_name, "string")) {

                try mem.write_struct(address, []const u8, value);

            }

            try con.writeln("Successfully!");
        } else {
            try con.writeln("Unknown command!");
        }
    }
}