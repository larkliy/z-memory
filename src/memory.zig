const std = @import("std");
const win = std.os.windows;

const Process = @import("process.zig").Process;

const PROCESS_ALL_ACCESS = 0x1F0FFF;

extern "kernel32" fn OpenProcess(dwDesiredAccess: win.DWORD, bInheritHandle: win.BOOL, dwProcessId: win.DWORD) callconv(.winapi) win.HANDLE;

pub const Memory = struct {
    process_handle: win.HANDLE,
    process: Process,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, process_name: []const u8) !Memory {
        const process = try Process.getProcessByName(allocator, process_name);
        const process_handle = OpenProcess(PROCESS_ALL_ACCESS, win.FALSE, process.process_id);

        return Memory {
            .process_handle = process_handle,
            .process = process,
            .allocator = allocator
        };
    }

    pub fn read(self: *Memory, address: u64, buffer: []u8) !usize {
        const result = try win.ReadProcessMemory(
            self.process_handle, 
            @ptrFromInt(address), 
            buffer
        );

        if (result.len == 0) return error.ReadFailed;
        return result.len;
    }

    pub fn read_struct(self: *Memory, address: u64, comptime T: type) !T {
        var buffer: [@sizeOf(T)]u8 = undefined;
        _ = try self.read(address, &buffer);
        return std.mem.bytesToValue(T, &buffer);
    }

    pub fn write(self: *Memory, address: u64, buffer: []const u8) !usize {
        const result = try win.WriteProcessMemory(
            self.process_handle, 
            @ptrFromInt(address), 
            buffer
        );

        if (result.len == 0) return error.WriteFailed;
        return result.len;
    }
    
    pub fn deinit(self: *Memory, allocator: std.mem.Allocator) void {
        _ = win.CloseHandle(self.process_handle);
        self.process.deinit(allocator);
    }
};