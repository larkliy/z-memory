const std = @import("std");
const win = std.os.windows;

extern "kernel32" fn SetConsoleTitleA(name: win.LPCSTR) win.BOOL;

pub const Console = struct {
    
    stdin: std.fs.File.Reader = undefined,
    stdout: std.fs.File.Writer = undefined,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, stdin_buffer: []u8, stdout_buffer: []u8) Console {
        return Console {
            .stdin = std.fs.File.stdin().reader(stdin_buffer),
            .stdout = std.fs.File.stdout().writer(stdout_buffer),
            .allocator = allocator
        };
    }

    pub fn set_title(self: *Console, title: []const u8) !void {
        const c_title = try self.allocator.dupeZ(u8, title);
        defer self.allocator.free(c_title);

        _ = SetConsoleTitleA(c_title);
    }

    pub fn readLine(self: *Console) ![]u8 {
        const slice = try self.stdin.interface.takeDelimiter('\n');
        return slice.?[0..slice.?.len - 1];
    }

    pub fn pause(self: *Console) !void {
        _ = try self.stdin.interface.takeByte();
    }

    pub fn write(self: *Console, data: []const u8) !void {
        try self.stdout.interface.writeAll(data);
        try self.stdout.interface.flush();
    }

    pub fn writeln(self: *Console, data: []const u8) !void {
        try self.stdout.interface.writeAll(data);
        try self.stdout.interface.writeAll("\n");
        try self.stdout.interface.flush();
    }

    pub fn println(self: *Console, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.interface.print(fmt, args);
        try self.stdout.interface.writeAll("\n");
        try self.stdout.interface.flush();
    }

    pub fn print(self: *Console, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.interface.print(fmt, args);
        try self.stdout.interface.flush();
    }
};