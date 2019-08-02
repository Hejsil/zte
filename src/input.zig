const std = @import("std");

const ascii = std.ascii;
const debug = std.debug;
const fs = std.fs;
const math = std.math;

// Key should really be a more close mapping to how the keys look that
// we get from stdin. We want "Key.ctrl | 'h'" and "Key.ctrl | Key.backspace"
// to actually conflict in a switch, because these are the same escape
// sequence.
pub const Key = struct {
    pub const Type = u32;

    pub const unknown: Type = 0b11111111111111111111111111111111;
    pub const esc: Type = '\x1b';

    pub const enter: Type = ctrl | 'm';
    pub const backspace: Type = '\x7f';

    pub const arrow_up: Type = 0x0100;
    pub const arrow_down: Type = 0x0200;
    pub const arrow_left: Type = 0x0300;
    pub const arrow_right: Type = 0x0400;
    pub const page_up: Type = 0x0500;
    pub const page_down: Type = 0x0600;
    pub const home: Type = 0x0700;
    pub const end: Type = 0x0800;
    pub const delete: Type = 0x0900;

    pub const ctrl: Type = 0b10000000000000000000000000000000;
    pub const alt: Type = 0b01000000000000000000000000000000;
    pub const shift: Type = 0b00100000000000000000000000000000;

    pub fn toStr(key: Key.Type) []const u8 {
        const key_no_modi = key & ~(ctrl | alt | shift);
        switch (key & (ctrl | alt | shift)) {
            ctrl => return toStrHelper(key_no_modi, "Ctrl+"),
            alt => return toStrHelper(key_no_modi, "Shift+"),
            shift => return toStrHelper(key_no_modi, "Ctrl+Alt+"),
            ctrl | alt => return toStrHelper(key_no_modi, "Ctrl+Alt+"),
            ctrl | shift => return toStrHelper(key_no_modi, "Ctrl+Shift+"),
            alt | shift => return toStrHelper(key_no_modi, "Alt+Shift+"),
            ctrl | alt | shift => return toStrHelper(key_no_modi, "Ctrl+Alt+Shift+"),
            else => return toStrHelper(key_no_modi, ""),
        }
    }

    // This will generate output a lot of strings to the binary. Is it ok?
    // I should measure the actual binary cost of doing this "no failure toStr"
    // function.
    // Update: Building with release small + --strip:
    // - toStr:    248K
    // - no toStr: 160K
    //
    // Hmm, let's calculate.
    // Printable chars: 95 * "Ctrl+".len + 95 * "Shift+".len + 95 * "Ctrl+Alt+".len
    //                  + "Ctrl+Shift+".len + 95 * "Alt+Shift+".len + 95 * "Ctrl+Alt+Shift+".len
    //                  + 95 = 4381
    //
    // I'm not gonna calc the rest (i think we hit around 8000 bytes). I'm not sure where the
    // 80K comes from...
    fn toStrHelper(key: Key.Type, comptime prefix: []const u8) []const u8 {
        debug.assert(key & (ctrl | alt | shift) == 0);
        switch (key) {
            esc => return prefix ++ "Esc",
            enter => return prefix ++ "Enter",
            backspace => return prefix ++ "Backspace",
            arrow_up => return prefix ++ "Up",
            arrow_down => return prefix ++ "Down",
            arrow_left => return prefix ++ "Left",
            arrow_right => return prefix ++ "Right",
            page_up => return prefix ++ "PageUp",
            page_down => return prefix ++ "PageUp",
            home => return prefix ++ "Home",
            end => return prefix ++ "End",
            delete => return prefix ++ "Delete",
            ' ' => return prefix ++ "Space",
            else => {
                const small = math.cast(u8, key) catch 0;
                if (!ascii.isPrint(small))
                    return prefix ++ "???";

                const printable = comptime blk: {
                    var res: [('~' - ' ') + 1]u8 = undefined;
                    for (res) |*c, i|
                        c.* = @intCast(u8, i + ' ');

                    break :blk res;
                };
                inline for (printable) |c| {
                    if (c == small)
                        return prefix ++ [_]u8{c};
                }

                unreachable;
            },
        }
    }
};

pub fn readKey(stdin: fs.File) !Key.Type {
    var buf: [10]u8 = undefined;
    var len: usize = 0;
    while (len == 0)
        len = try stdin.read(&buf);
    const key = buf[0..len];

    //debug.warn("------------\n");
    //for (key) |b| {
    //    if (ascii.isPrint(b)) {
    //        debug.warn("{} 0x{x:2} {b:8} '{c}'\n", b, b, b, b);
    //    } else {
    //        debug.warn("{} 0x{x:2} {b:8}\n", b, b, b);
    //    }
    //}
    switch (key.len) {
        1 => switch (key[0]) {
            '\x1b' => return Key.esc,
            '\x7f' => return Key.backspace,
            else => {
                if (ascii.isPrint(key[0]))
                    return key[0];
                if (ascii.isPrint(key[0] | 0b01100000))
                    return Key.ctrl | (key[0] | 0b01100000);

                return Key.unknown;
            },
        },
        2 => {
            if (key[0] != '\x1b')
                return Key.unknown;

            if (ascii.isPrint(key[1]))
                return Key.alt | key[1];
            if (ascii.isPrint(key[1] | 0b01100000))
                return Key.alt | Key.ctrl | (key[1] | 0b01100000);
        },
        3 => {
            if (key[0] != '\x1b')
                return Key.unknown;
            switch (key[1]) {
                '[' => switch (key[2]) {
                    'A' => return Key.arrow_up,
                    'B' => return Key.arrow_down,
                    'C' => return Key.arrow_right,
                    'D' => return Key.arrow_left,
                    'H' => return Key.home,
                    'F' => return Key.end,
                    else => {},
                },
                'O' => switch (key[2]) {
                    'H' => return Key.home,
                    'F' => return Key.end,
                    else => {},
                },
                else => {},
            }
        },
        4 => {
            if (key[0] != '\x1b')
                return Key.unknown;
            if (key[1] != '[')
                return Key.unknown;

            switch (key[3]) {
                '~' => switch (key[2]) {
                    '1' => return Key.home,
                    '3' => return Key.delete,
                    '4' => return Key.end,
                    '5' => return Key.page_up,
                    '6' => return Key.page_down,
                    '7' => return Key.home,
                    '8' => return Key.end,
                    else => {},
                },
                else => {},
            }
        },
        6 => {
            if (key[0] != '\x1b')
                return Key.unknown;
            if (key[1] != '[')
                return Key.unknown;
            if (key[2] != '1')
                return Key.unknown;
            if (key[3] != ';')
                return Key.unknown;
            const modifier = switch (key[4]) {
                '2' => Key.shift,
                '5' => Key.ctrl,
                else => return Key.unknown,
            };

            switch (key[5]) {
                'A' => return modifier | Key.arrow_up,
                'B' => return modifier | Key.arrow_down,
                'C' => return modifier | Key.arrow_right,
                'D' => return modifier | Key.arrow_left,
                else => {},
            }
        },
        else => {},
    }

    return Key.unknown;
}
