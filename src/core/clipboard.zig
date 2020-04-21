const std = @import("std");

const fs = std.fs;
const heap = std.heap;
const math = std.math;
const mem = std.mem;
const process = std.process;
const os = std.os;

const ChildProcess = std.ChildProcess;

pub fn copy(allocator: *mem.Allocator) !*ChildProcess {
    var env = try process.getEnvMap(allocator);
    defer env.deinit();

    const path = env.get("PATH") orelse "./";

    var buf: [os.PATH_MAX]u8 = undefined;
    if (getPathToExe(&buf, path, "xclip")) |p| {
        return try exec(allocator, &[_][]const u8{ p, "-selection", "clipboard" }, .Pipe, .Ignore);
    } else if (getPathToExe(&buf, path, "xsel")) |p| blk: {
        return try exec(allocator, &[_][]const u8{ p, "-b" }, .Pipe, .Ignore);
    }

    return error.NoCopyCommand;
}

pub fn paste(allocator: *mem.Allocator) !*ChildProcess {
    var env = try process.getEnvMap(allocator);
    defer env.deinit();

    const path = env.get("PATH") orelse "./";

    var buf: [os.PATH_MAX]u8 = undefined;
    if (getPathToExe(&buf, path, "xclip")) |p| {
        return try exec(allocator, &[_][]const u8{ p, "-selection", "clipboard", "-o" }, .Ignore, .Pipe);
    } else if (getPathToExe(&buf, path, "xsel")) |p| blk: {
        return try exec(allocator, &[_][]const u8{ p, "-b" }, .Ignore, .Pipe);
    }

    return error.NoCopyCommand;
}

fn exec(
    allocator: *mem.Allocator,
    argv: []const []const u8,
    stdin: ChildProcess.StdIo,
    stdout: ChildProcess.StdIo,
) !*ChildProcess {
    const p = try ChildProcess.init(argv, allocator);

    p.stdin_behavior = stdin;
    p.stdout_behavior = stdout;
    p.stderr_behavior = ChildProcess.StdIo.Ignore;
    try p.spawn();
    return p;
}

fn getPathToExe(buf: *[os.PATH_MAX]u8, path_list: []const u8, exe: []const u8) ?[]u8 {
    var iter = mem.tokenize(path_list, ":");
    while (iter.next()) |path| {
        var allocator = &heap.FixedBufferAllocator.init(buf).allocator;
        const file = fs.path.join(allocator, &[_][]const u8{ path, exe }) catch continue;
        fs.cwd().access(file, .{}) catch continue;
        return file;
    }

    return null;
}
