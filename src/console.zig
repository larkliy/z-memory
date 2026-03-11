const std = @import("std");
const win = std.os.windows;

extern "kernel32" fn SetConsoleTitleA(name: win.LPCSTR) win.BOOL;
extern "kernel32" fn SetConsoleCP(wCodePageID: win.UINT) win.BOOL;
extern "kernel32" fn SetConsoleOutputCP(wCodePageID: win.UINT) win.BOOL;

pub const Console = struct {
    
    stdin: std.fs.File.Reader = undefined,
    stdout: std.fs.File.Writer = undefined,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, stdin_buffer: []u8, stdout_buffer: []u8) Console {
        enableUtf8Console();
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

    pub fn readLine(self: *Console) []u8 {
        const slice = self.stdin.interface.takeDelimiter('\n') catch unreachable;
        return slice.?[0..slice.?.len - 1];
    }

    pub fn pause(self: *Console) void {
        _ = self.stdin.interface.takeByte() catch return;
    }

    pub fn write(self: *Console, data: []const u8) void {
        self.stdout.interface.writeAll(data) catch return;
        self.stdout.interface.flush() catch return;
    }

    pub fn writeln(self: *Console, data: []const u8) void {
        self.write(data);
        self.write("\n");
        self.stdout.interface.flush() catch return;
    }

    pub fn println(self: *Console, comptime fmt: []const u8, args: anytype) void {
        self.print(fmt, args);
        self.write("\n");
        self.stdout.interface.flush() catch return;
    }

    pub fn print(self: *Console, comptime fmt: []const u8, args: anytype) void {
        self.stdout.interface.print(fmt, args) catch return;
        self.stdout.interface.flush() catch return;
    }

    fn enableUtf8Console() void {
        _ = SetConsoleCP(65001);
        _ = SetConsoleOutputCP(65001);
    }
};