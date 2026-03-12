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

extern "kernel32" fn Module32First(hSnapshot: win.HANDLE, lpme: *win.MODULEENTRY32) callconv(.winapi) win.BOOL;
extern "kernel32" fn Module32Next(hSnapshot: win.HANDLE, lpme: *win.MODULEENTRY32,) callconv(.winapi) win.BOOL;

pub const ProcessModuleInfo = struct {
    base: usize,
    name: []const u8,
    len: usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ProcessModuleInfo) void {
        self.allocator.free(self.name);
    }
};


pub const ProcessFilterOptions = struct { 
    filter_string: []const u8,
    should_filter: bool
};

pub const Process = struct {
    process_id: u32,
    name: []u8,
    allocator: std.mem.Allocator,

    pub fn getProcesses(allocator: std.mem.Allocator, options: ProcessFilterOptions) ![]Process {
        var process_list = std.ArrayList(Process).empty;

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

            if (options.should_filter and std.mem.indexOf(u8, sliced_name, options.filter_string) == null) {
                
                if (Process32Next(snapshot, &process_entry) == win.FALSE)
                    break;

                continue;
            }

            try process_list.append(allocator, Process {
                .allocator = allocator,
                .name = try allocator.dupe(u8, sliced_name),
                .process_id = process_entry.th32ProcessID
             });

             if (Process32Next(snapshot, &process_entry) == win.FALSE)
                break;
        }

        return try process_list.toOwnedSlice(allocator);
    }

    pub fn getProcessByName(allocator: std.mem.Allocator, name: []const u8) !Process {
        const processes = try getProcesses(allocator, .{ 
            .should_filter = true, 
            .filter_string = name
        });

        defer allocator.free(processes);

        for (processes) |*proc| {
            defer proc.deinit();

            if (std.mem.eql(u8, proc.name, name)) { 
                return Process {
                    .allocator = allocator,
                    .name = try allocator.dupe(u8, proc.name),
                    .process_id = proc.process_id
                };
            }
        }

        return error.ProcessNotFound;
    }

    pub fn getModuleBaseAddress(self: *Process, moduleName: []const u8) !ProcessModuleInfo {

        const snapshot = CreateToolhelp32Snapshot(win.TH32CS_SNAPMODULE | win.TH32CS_SNAPMODULE32, self.process_id);
        
        if (snapshot == win.INVALID_HANDLE_VALUE)
            return error.SnapshotNotFound;

        defer _ = win.CloseHandle(snapshot);

        var entry: win.MODULEENTRY32 = undefined;
        entry.dwSize = @sizeOf(win.MODULEENTRY32);

        if (Module32First(snapshot, &entry) == win.FALSE) 
            return error.ModuleNotFound;

        while (true) {

            const module_name = std.mem.sliceTo(&entry.szModule, 0);

            if (std.mem.eql(u8, module_name, moduleName)) {
                return ProcessModuleInfo {
                    .allocator = self.allocator,
                    .base = @intFromPtr(entry.modBaseAddr),
                    .len = entry.modBaseSize,
                    .name = try self.allocator.dupe(u8, module_name)
                };
            }


            if (Module32Next(snapshot, &entry) == win.FALSE)
                break;
        }

        return error.ModuleNotFound;
    }

    pub fn deinit(self: *Process) void {
        self.allocator.free(self.name);
    }
};