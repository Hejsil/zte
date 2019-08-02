const std = @import("std");

const c = @import("c.zig");
const vt100 = @import("vt100.zig");

const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;

var old_tc_attr: ?c.termios = null;

pub fn clear(stream: var) !void {
    try stream.write(vt100.erase.inDisplay(vt100.erase.all) ++ vt100.cursor.position(""));
}

pub fn init(stdin: fs.File) !void {
    old_tc_attr = try getAttr(stdin);
    try enableRawMode(stdin);
}

pub fn deinit(stdin: fs.File) !void {
    if (old_tc_attr) |old|
        try setAttr(stdin, old);
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
        try stdout.write(vt100.cursor.forward("999") ++ vt100.cursor.down("999"));
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
    try stdout.write(vt100.device.statusReport(vt100.device.request.active_position));

    var buf: [1024]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) : (len += 1) {
        const l = try stdin.read((*[1]u8)(&buf[len]));
        if (l != 1 or buf[len] == 'R')
            break;
    }
    const response = buf[0..len];

    if (len < vt100.escape.len)
        return error.CursorPosition;
    if (!mem.eql(u8, vt100.escape, buf[0..vt100.escape.len]))
        return error.CursorPosition;

    var iter = mem.separate(buf[vt100.escape.len..len], ";");
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
    var raw = try getAttr(file);
    raw.c_iflag &= ~@typeOf(raw.c_lflag)(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~@typeOf(raw.c_lflag)(c.OPOST);
    raw.c_cflag &= ~@typeOf(raw.c_lflag)(c.CS8);
    raw.c_lflag &= ~@typeOf(raw.c_lflag)(c.ECHO | c.ICANON | c.IEXTEN | c.ISIG);
    raw.c_cc[c.VMIN] = 0;
    raw.c_cc[c.VTIME] = 1;
    try setAttr(file, raw);
}

fn getAttr(file: fs.File) !c.termios {
    var raw: c.termios = undefined;
    if (c.tcgetattr(file.handle, &raw) == -1)
        return error.TermiosError;

    return raw;
}

fn setAttr(file: fs.File, attr: c.termios) !void {
    if (c.tcsetattr(file.handle, c.TCSAFLUSH, &attr) == -1)
        return error.TermiosError;
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
        c_iflag: tcflag_t,
        c_oflag: tcflag_t,
        c_cflag: tcflag_t,
        c_lflag: tcflag_t,
        c_line: cc_t,
        c_cc: [NCCS]cc_t,
        __c_ispeed: speed_t,
        __c_ospeed: speed_t,
    },
    else => @compileError("Unsupported arch"),
};
