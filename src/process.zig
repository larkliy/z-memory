const std = @import("std");
const win = std.os.windows;

pub const PROCESSENTRY32 = extern struct {
    dwSize: win.DWORD,
    cntUsage: win.DWORD,
    th32ProcessID: win.DWORD,
    th32DefaultHeapID: win.ULONG_PTR,
    th32ModuleID: win.DWORD,
    cntThreads: win.DWORD,
    th32ParentProcessID: win.DWORD,
    pcPriClassBase: win.LONG,
    dwFlags: win.DWORD,
    szExeFile: [win.MAX_PATH]win.CHAR,
};

extern "kernel32" fn CreateToolhelp32Snapshot(dwFlags: win.DWORD, th32ProcessID: win.DWORD) callconv(.winapi) win.HANDLE;
extern "kernel32" fn Process32First(hSnapshot: win.HANDLE, lppe: ?*PROCESSENTRY32) callconv(.winapi) win.BOOL;
extern "kernel32" fn Process32Next(hSnapshot: win.HANDLE, lppe: ?*PROCESSENTRY32) callconv(.winapi) win.BOOL;

pub const Process = struct {
    process_id: u32,
    name: []u8,
    allocator: std.mem.Allocator,

    pub noinline fn getProcessByName(allocator: std.mem.Allocator, name: []const u8) !Process {

        const snapshot = CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0);

        if (snapshot == win.INVALID_HANDLE_VALUE)
            return error.SnapshotNotFound;

        defer _ = win.CloseHandle(snapshot);

        var process_entry: PROCESSENTRY32 = undefined;
        process_entry.dwSize = @sizeOf(PROCESSENTRY32);

        if (Process32First(snapshot, &process_entry) == win.FALSE)
            return error.ProcessNotFound;

        while (true) {
            const sliced_name = std.mem.sliceTo(&process_entry.szExeFile, 0);

            if (std.mem.eql(u8, sliced_name, name)) {
                const process = Process { 
                    .process_id = process_entry.th32ProcessID,
                    .name = try allocator.dupe(u8, sliced_name),
                    .allocator = allocator,
                };

                return process;
            }

            if (Process32Next(snapshot, &process_entry) == win.FALSE)
                break;
        }

        return error.ProcessNotFound;
    }

    pub fn deinit(self: *Process) void {
        self.allocator.free(self.name);
    }
};