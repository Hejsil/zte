const std = @import("std");

const ascii = std.ascii;
const debug = std.debug;
const fs = std.fs;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

// This was ported from termbox https://github.com/nsf/termbox (not complete)

pub const Key = struct {
    pub const Type = u64;

    pub const unknown = 0xffffffffffffffff;

    pub const f1 = ctrl | (0xffff - 0);
    pub const f2 = ctrl | (0xffff - 1);
    pub const f3 = ctrl | (0xffff - 2);
    pub const f4 = ctrl | (0xffff - 3);
    pub const f5 = ctrl | (0xffff - 4);
    pub const f6 = ctrl | (0xffff - 5);
    pub const f7 = ctrl | (0xffff - 6);
    pub const f8 = ctrl | (0xffff - 7);
    pub const f9 = ctrl | (0xffff - 8);
    pub const f10 = ctrl | (0xffff - 9);
    pub const f11 = ctrl | (0xffff - 10);
    pub const f12 = ctrl | (0xffff - 11);

    pub const insert = ctrl | (0xffff - 12);
    pub const delete = ctrl | (0xffff - 13);
    pub const home = ctrl | (0xffff - 14);
    pub const end = ctrl | (0xffff - 15);

    pub const page_up = ctrl | (0xffff - 16);
    pub const page_down = ctrl | (0xffff - 17);
    pub const arrow_up = ctrl | (0xffff - 18);
    pub const arrow_down = ctrl | (0xffff - 19);
    pub const arrow_left = ctrl | (0xffff - 20);
    pub const arrow_right = ctrl | (0xffff - 21);

    pub const ctrl_arrow_up = ctrl | (0xffff - 22);
    pub const ctrl_arrow_down = ctrl | (0xffff - 23);
    pub const ctrl_arrow_left = ctrl | (0xffff - 24);
    pub const ctrl_arrow_right = ctrl | (0xffff - 25);

    pub const shift_arrow_up = ctrl | (0xffff - 26);
    pub const shift_arrow_down = ctrl | (0xffff - 27);
    pub const shift_arrow_left = ctrl | (0xffff - 28);
    pub const shift_arrow_right = ctrl | (0xffff - 29);

    pub const ctrl_tilde = ctrl | 0x00;
    pub const ctrl_2 = ctrl_tilde;
    pub const ctrl_a = ctrl | 0x01;
    pub const ctrl_b = ctrl | 0x02;
    pub const ctrl_c = ctrl | 0x03;
    pub const ctrl_d = ctrl | 0x04;
    pub const ctrl_e = ctrl | 0x05;
    pub const ctrl_f = ctrl | 0x06;
    pub const ctrl_g = ctrl | 0x07;
    pub const backspace = ctrl | 0x08;
    pub const ctrl_h = backspace;
    pub const tab = ctrl | 0x09;
    pub const ctrl_i = tab;
    pub const ctrl_j = ctrl | 0x0a;
    pub const ctrl_k = ctrl | 0x0b;
    pub const ctrl_l = ctrl | 0x0c;
    pub const enter = ctrl | 0x0d;
    pub const ctrl_m = enter;
    pub const ctrl_n = ctrl | 0x0e;
    pub const ctrl_o = ctrl | 0x0f;
    pub const ctrl_p = ctrl | 0x10;
    pub const ctrl_q = ctrl | 0x11;
    pub const ctrl_r = ctrl | 0x12;
    pub const ctrl_s = ctrl | 0x13;
    pub const ctrl_t = ctrl | 0x14;
    pub const ctrl_u = ctrl | 0x15;
    pub const ctrl_v = ctrl | 0x16;
    pub const ctrl_w = ctrl | 0x17;
    pub const ctrl_x = ctrl | 0x18;
    pub const ctrl_y = ctrl | 0x19;
    pub const ctrl_z = ctrl | 0x1a;
    pub const escape = ctrl | 0x1b;
    pub const ctrl_lsq_bracket = escape;
    pub const ctrl_3 = escape;
    pub const ctrl_4 = ctrl | 0x1c;
    pub const ctrl_backslash = ctrl_4;
    pub const ctrl_5 = ctrl | 0x1d;
    pub const ctrl_rsq_bracket = ctrl_5;
    pub const ctrl_6 = ctrl | 0x1e;
    pub const ctrl_7 = ctrl | 0x1f;
    pub const ctrl_slash = ctrl_7;
    pub const ctrl_underscore = ctrl_7;
    pub const space = ctrl | 0x20;
    pub const backspace2 = ctrl | 0x7f;
    pub const ctrl_8 = backspace2;

    pub const alt = 1 << 63;
    const ctrl = 1 << 62;

    pub const Pick = enum {
        NotCtrl, // picks non ctrl keys over ctrl keys
        CtrlAlphaNum, // picks ctrl_a-z and ctrl_0-9 over other ctrl keys
        CtrlSpecial1, // picks ctrl_{tidle, lsq/rsq_bracket, backslash, slash} over other ctrl keys
        CtrlSpecial2, // picks ctrl_{tidle, lsq/rsq_bracket, backslash, undscore} over other ctrl keys
    };

    /// Returns null terminated array
    pub fn toStr(key: Key.Type, pick: Pick) [32:0]u8 {
        if (key == Key.unknown)
            return ("???" ++ ("\x00" ** 29)).*;
        const modi_str = switch (key & alt) {
            alt => "alt+",
            else => "",
        };

        var utf8_buf: [4]u8 = undefined;
        const key_no_modi = key & ~@as(Type, alt);
        const key_str = switch (key_no_modi) {
            f1 => "f1",
            f2 => "f2",
            f3 => "f3",
            f4 => "f4",
            f5 => "f5",
            f6 => "f6",
            f7 => "f7",
            f8 => "f8",
            f9 => "f9",
            f10 => "f10",
            f11 => "f11",
            f12 => "f12",

            insert => "insert",
            delete => "delete",
            home => "home",
            end => "end",
            backspace => switch (pick) {
                .NotCtrl => "backspace",
                else => "ctrl+h",
            },
            tab => switch (pick) {
                .NotCtrl => "tab",
                else => "ctrl+i",
            },
            enter => switch (pick) {
                .NotCtrl => "enter",
                else => "ctrl+m",
            },
            escape => switch (pick) {
                .NotCtrl => "escape",
                .CtrlAlphaNum => "ctrl+3",
                else => "ctrl+???", // TODO: ctrl_lsq_bracket
            },
            space => "space",
            backspace2 => switch (pick) {
                .NotCtrl => "backspace2",
                else => "ctrl+8",
            },

            page_up => "page_up",
            page_down => "page_down",
            arrow_up => "arrow_up",
            arrow_down => "arrow_down",
            arrow_left => "arrow_left",
            arrow_right => "arrow_right",

            ctrl_arrow_up => "ctrl+arrow_up",
            ctrl_arrow_down => "ctrl+arrow_down",
            ctrl_arrow_left => "ctrl+arrow_left",
            ctrl_arrow_right => "ctrl+arrow_right",

            shift_arrow_up => "shift+arrow_up",
            shift_arrow_down => "shift+arrow_down",
            shift_arrow_left => "shift+arrow_left",
            shift_arrow_right => "shift+arrow_right",

            ctrl_a => "ctrl+a",
            ctrl_b => "ctrl+b",
            ctrl_c => "ctrl+c",
            ctrl_d => "ctrl+d",
            ctrl_e => "ctrl+e",
            ctrl_f => "ctrl+f",
            ctrl_g => "ctrl+g",
            ctrl_j => "ctrl+j",
            ctrl_k => "ctrl+k",
            ctrl_l => "ctrl+l",
            ctrl_n => "ctrl+n",
            ctrl_o => "ctrl+o",
            ctrl_p => "ctrl+p",
            ctrl_q => "ctrl+q",
            ctrl_r => "ctrl+r",
            ctrl_s => "ctrl+s",
            ctrl_t => "ctrl+t",
            ctrl_u => "ctrl+u",
            ctrl_v => "ctrl+v",
            ctrl_w => "ctrl+w",
            ctrl_x => "ctrl+x",
            ctrl_y => "ctrl+y",
            ctrl_z => "ctrl+z",

            ctrl_2 => switch (pick) {
                .NotCtrl, .CtrlAlphaNum => "ctrl+2",
                else => "ctrl+~",
            },

            ctrl_4 => switch (pick) {
                .NotCtrl, .CtrlAlphaNum => "ctrl+4",
                else => "ctrl+\\",
            },
            ctrl_5 => switch (pick) {
                .NotCtrl, .CtrlAlphaNum => "ctrl+5",
                else => "ctrl+???", // TODO: ctrl_rsq_bracket
            },
            ctrl_6 => "ctrl+6",
            ctrl_7 => switch (pick) {
                .NotCtrl, .CtrlAlphaNum => "ctrl+7",
                .CtrlSpecial1 => "ctrl+/",
                .CtrlSpecial2 => "ctrl+_",
            },
            else => blk: {
                if ((key & 0xffffffff00000000) != 0)
                    break :blk "???";
                const codepoint = @intCast(u21, key & 0x00000000ffffffff);
                const len = unicode.utf8Encode(codepoint, &utf8_buf) catch unreachable;
                break :blk utf8_buf[0..len];
            },
        };

        var res = ("\x00" ** 32).*;
        mem.copy(u8, res[0..], modi_str);
        mem.copy(u8, res[modi_str.len..], key_str);
        return res;
    }
};

// TODO: this is not the exact escape keys for my terminal
const esc_keys = [_][]const u8{
    "\x1bOP",
    "\x1bOQ",
    "\x1bOR",
    "\x1bOS",
    "\x1b[15~",
    "\x1b[17~",
    "\x1b[18~",
    "\x1b[19~",
    "\x1b[20~",
    "\x1b[21~",
    "\x1b[23~",
    "\x1b[24~",
    "\x1b[2~",
    "\x1b[3~",
    "\x1b[H",
    "\x1b[F",
    "\x1b[5~",
    "\x1b[6~",
    "\x1b[A",
    "\x1b[B",
    "\x1b[D",
    "\x1b[C",
    "\x1b[1;5A",
    "\x1b[1;5B",
    "\x1b[1;5D",
    "\x1b[1;5C",
    "\x1b[1;2A",
    "\x1b[1;2B",
    "\x1b[1;2D",
    "\x1b[1;2C",
};

fn parseKey(key: []const u8) Key.Type {
    if (key.len == 1 and key[0] == '\x1b')
        return Key.escape;
    if (key[0] == '\x1b') {
        for (esc_keys) |esc_key, i| {
            if (mem.startsWith(u8, key, esc_key))
                return Key.f1 - i;
        }

        return Key.alt | parseKey(key[1..]);
    }

    if (key[0] <= (Key.space & ~@as(Key.Type, Key.ctrl)))
        return Key.ctrl | @as(Key.Type, key[0]);
    if (key[0] == (Key.backspace2 & ~@as(Key.Type, Key.ctrl)))
        return Key.ctrl | @as(Key.Type, key[0]);

    const len = unicode.utf8ByteSequenceLength(key[0]) catch return Key.unknown;
    if (key.len <= len)
        return unicode.utf8Decode(key[0..len]) catch return Key.unknown;

    return Key.unknown;
}

pub fn readKey(stdin: fs.File) !Key.Type {
    var buf: [10]u8 = undefined;
    var len: usize = 0;
    while (len == 0)
        len = try stdin.read(&buf);

    return parseKey(buf[0..len]);
}
