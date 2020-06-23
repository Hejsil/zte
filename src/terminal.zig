const std = @import("std");

const c = @import("c.zig");
const os = std.os;
const vt100 = @import("vt100.zig");

const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;

var old_tc_attr: ?os.termios = null;

pub fn clear(stream: var) !void {
    try stream.writeAll(vt100.erase.inDisplay(vt100.erase.all) ++ vt100.cursor.position(""));
}

pub fn init(stdin: fs.File) !void {
    old_tc_attr = try os.tcgetattr(stdin.handle);
    try enableRawMode(stdin);
}

pub fn deinit(stdin: fs.File) !void {
    if (old_tc_attr) |old|
        try os.tcsetattr(stdin.handle, os.TCSA.FLUSH, old);
}

pub const Size = struct {
    rows: usize,
    columns: usize,
};

pub fn size(stdout: fs.File, stdin: fs.File) !Size {
    var ws: c.winsize = undefined;
    if (c.ioctl(stdout.handle, c.TIOCGWINSZ, &ws) == -1 or ws.ws_col == 0) {
        // If getting the terminal size with ioctl didn't work, then we move
        // the cursor to the bottom right of the screen and asks for the cursor
        // position.
        // TODO: We sould probably restore the cursor position when we are done.
        //       This program doesn't require that this is done, but if someone
        //       copy pastes this, then they probably want that behavior.
        try stdout.writeAll(vt100.cursor.forward("999") ++ vt100.cursor.down("999"));
        const pos = try cursorPosition(stdout, stdin);
        return Size{
            .columns = pos.x,
            .rows = pos.y,
        };
    }

    return Size{
        .columns = ws.ws_col,
        .rows = ws.ws_row,
    };
}

pub const Pos = struct {
    x: usize,
    y: usize,
};

pub fn cursorPosition(stdout: fs.File, stdin: fs.File) !Pos {
    try stdout.writeAll(vt100.device.statusReport(vt100.device.request.active_position));

    var buf: [1024]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) : (len += 1) {
        const l = try stdin.read(buf[len .. len + 1]);
        if (l != 1 or buf[len] == 'R')
            break;
    }
    const response = buf[0..len];

    if (len < vt100.escape.len)
        return error.CursorPosition;
    if (!mem.eql(u8, vt100.escape, buf[0..vt100.escape.len]))
        return error.CursorPosition;

    var iter = mem.split(buf[vt100.escape.len..len], ";");
    const rows_str = iter.next() orelse return error.CursorPosition;
    const cols_str = iter.next() orelse return error.CursorPosition;
    if (iter.next()) |_|
        return error.CursorPosition;

    return Pos{
        .x = try fmt.parseUnsigned(usize, cols_str, 10),
        .y = try fmt.parseUnsigned(usize, rows_str, 10),
    };
}

fn enableRawMode(file: fs.File) !void {
    var raw = try os.tcgetattr(file.handle);
    raw.iflag &= ~@as(@TypeOf(raw.lflag), BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.oflag &= ~@as(@TypeOf(raw.lflag), os.OPOST);
    raw.cflag &= ~@as(@TypeOf(raw.lflag), os.CS8);
    raw.lflag &= ~@as(@TypeOf(raw.lflag), os.ECHO | os.ICANON | os.IEXTEN | os.ISIG);
    raw.cc[5] = 0;
    raw.cc[7] = 1;
    try os.tcsetattr(file.handle, os.TCSA.FLUSH, raw);
}

const builtin = @import("builtin");
const tcflag_t = c_uint;
const cc_t = u8;
const speed_t = c_uint;

const VTIME = 5;
const VMIN = 6;

const BRKINT = 0o0002;
const INPCK = 0o0020;
const ISTRIP = 0o0040;
const ICRNL = 0o0400;
const IXON = 0o2000;

const Termios = switch (builtin.arch) {
    .x86_64 => extern struct {
        iflag: tcflag_t,
        oflag: tcflag_t,
        cflag: tcflag_t,
        lflag: tcflag_t,
        line: cc_t,
        cc: [NCCS]cc_t,
        ispeed: speed_t,
        ospeed: speed_t,
    },
    else => @compileError("Unsupported arch"),
};
