const std = @import("std");


fn printLine(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var list = std.ArrayList(u8).empty;

    for (bytes, 0..) |byte, i| {

        if (i < bytes.len) {
           try list.print(allocator, " {X:0>2}", .{byte});
        } else {
            try list.appendSlice(allocator, "   ");
        }
    }

    try list.appendSlice(allocator,"  | ");
    
    for (bytes, 0..) |byte, i| {
        
        if (i > 0 and i % 4 == 0) {
            try list.append(allocator, ' ');
        }

        if (byte >= 0x20 and byte <= 0x7E) {
            try list.print(allocator, "{c}", .{byte});
        } else {
            try list.append(allocator, '.');
        }
    }

    return try list.toOwnedSlice(allocator);
}

pub fn dump(allocator: std.mem.Allocator, bytes: []const u8, line_size: usize) ![]u8 {
    var list = std.ArrayList(u8).empty;

    var buffer = try allocator.alloc(u8, line_size);
    defer allocator.free(buffer);

    var buf_idx: usize = 0;

    for (bytes) |byte| {

        buffer[buf_idx] = byte;
        buf_idx += 1;

        if (buf_idx == line_size) {
            const line = try printLine(allocator, buffer[0..buf_idx]);
            defer allocator.free(line);

            try list.appendSlice(allocator, line);
            try list.append(allocator, '\n');

            buf_idx = 0;
        } 
    }

    if (buf_idx > 0) {
        const line = try printLine(allocator, buffer[0..buf_idx]);
        defer allocator.free(line);
        
        try list.appendSlice(allocator, line);
        try list.append(allocator, '\n');
    }

    return try list.toOwnedSlice(allocator);
}