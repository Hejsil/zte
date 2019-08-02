const std = @import("std");

const text = @import("text.zig");

const debug = std.debug;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

const Content = Text.Content;
const Cursor = text.Cursor;
const Cursors = Text.Cursors;
const Location = text.Location;
const Text = text.Text;

test "moveCursors" {
    var buf: [1024 * 1024]u8 = undefined;

    const TestCast = struct {
        amount: usize,
        to_move: Cursor.ToMove,
        dir: Cursor.Direction,
        before: []const u8,
        after: []const u8,

        fn init(amount: usize, to_move: Cursor.ToMove, dir: Cursor.Direction, before: []const u8, after: []const u8) @This() {
            return @This(){
                .amount = amount,
                .to_move = to_move,
                .dir = dir,
                .before = before,
                .after = after,
            };
        }
    };
    inline for (comptime [_]TestCast{
        TestCast.init(1, .Both, .Left, "[]a[]b[c]d[ef]", "[]ab[]cde[]f"),
        TestCast.init(1, .Index, .Left, "[]a[]b[c]d[ef]", "[a]b[]cd[e]f"),
        TestCast.init(1, .Selection, .Left, "[]a[]b[c]d[ef]", "[abcdef]"),
        TestCast.init(1, .Both, .Right, "[]a[]b[c]d[ef]", "a[]b[]cd[]ef[]"),
        TestCast.init(1, .Index, .Right, "[]a[]b[c]d[ef]", "[abcdef]"),
        TestCast.init(1, .Selection, .Right, "[]a[]b[c]d[ef]", "[ab]c[]de[f]"),
        TestCast.init(1, .Both, .Down,
            \\a[]bc
            \\def[g]
            \\[]h
        ,
            \\abc
            \\d[]efg
            \\h[]
        ),
        TestCast.init(1, .Index, .Down,
            \\a[]bc
            \\def[g]
            \\[]h
        ,
            \\a[bc
            \\d]ef[g
            \\h]
        ),
        TestCast.init(1, .Selection, .Down,
            \\a[]bc
            \\def[g]
            \\[]h
        ,
            \\a[bc
            \\d]efg[
            \\h]
        ),
        TestCast.init(1, .Both, .Up,
            \\a[]bc
            \\def[g]
            \\[]h
        ,
            \\[]abc[]
            \\[]defg
            \\h
        ),
        TestCast.init(1, .Index, .Up,
            \\a[]bc
            \\def[g]
            \\[]h
        ,
            \\[a]bc[
            \\defg
            \\]h
        ),
        TestCast.init(1, .Selection, .Up,
            \\a[]bc
            \\def[g]
            \\[]h
        ,
            \\[a]bc[
            \\defg
            \\]h
        ),
    }) |case| {
        const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
        const t = try makeText(allocator, case.before).moveCursors(case.amount, case.to_move, case.dir);
        expect(t, case.after);
    }
}

test "spawnCursor" {
    var buf: [1024 * 1024]u8 = undefined;

    const TestCast = struct {
        dir: Cursor.Direction,
        before: []const u8,
        after: []const u8,

        fn init(dir: Cursor.Direction, before: []const u8, after: []const u8) @This() {
            return @This(){
                .dir = dir,
                .before = before,
                .after = after,
            };
        }
    };
    inline for (comptime [_]TestCast{
        TestCast.init(.Left, "a[]b[]d[ef]", "[]a[]b[]d[ef]"),
        TestCast.init(.Left, "[]a[]b[]d[ef]", "[]a[]b[]d[ef]"),
        TestCast.init(.Right, "a[]b[]d[e]f", "a[]b[]d[e]f[]"),
        TestCast.init(.Right, "a[]b[]d[e]f[]", "a[]b[]d[e]f[]"),
        TestCast.init(.Up,
            \\abc
            \\defg[]
            \\[]h
        ,
            \\abc[]
            \\defg[]
            \\[]h
        ),
        TestCast.init(.Up,
            \\abc[]
            \\defg
            \\[]h
        ,
            \\[]abc[]
            \\defg
            \\[]h
        ),
        TestCast.init(.Up,
            \\[]abc[]
            \\defg
            \\[]h
        ,
            \\[]abc[]
            \\defg
            \\[]h
        ),
        TestCast.init(.Down,
            \\[]abc
            \\defg[]
            \\h
        ,
            \\[]abc
            \\defg[]
            \\h[]
        ),
        TestCast.init(.Down,
            \\[]abc
            \\defg[]
            \\[]h
        ,
            \\[]abc
            \\defg[]
            \\[]h[]
        ),
        TestCast.init(.Down,
            \\[]abc
            \\defg[]
            \\h[]
        ,
            \\[]abc
            \\defg[]
            \\h[]
        ),
    }) |case| {
        const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
        const t = try makeText(allocator, case.before).spawnCursor(case.dir);
        expect(t, case.after);
    }
}

test "removeAllButMainCursor" {
    var buf: [1024 * 1024]u8 = undefined;
    const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;

    const t = makeText(allocator,
        \\a[]bc
        \\[]ab[]cd[]e
        \\fgh[]i
    ).removeAllButMainCursor();
    expect(t,
        \\abc
        \\abcde
        \\fgh[]i
    );
}

test "delete" {
    var buf: [1024 * 1024]u8 = undefined;

    const TestCast = struct {
        dir: Text.DeleteDir,
        before: []const u8,
        after: []const u8,

        fn init(dir: Text.DeleteDir, before: []const u8, after: []const u8) @This() {
            return @This(){
                .dir = dir,
                .before = before,
                .after = after,
            };
        }
    };
    inline for (comptime [_]TestCast{
        TestCast.init(.Left, "a[]b[]d[ef]", "[]d[]"),
        TestCast.init(.Right, "a[]b[]d[ef]", "a[]"),
    }) |case| {
        const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
        const t = try makeText(allocator, case.before).delete(case.dir);
        expect(t, case.after);
    }
}

test "insert" {
    var buf: [1024 * 1024]u8 = undefined;

    const TestCast = struct {
        str: []const u8,
        before: []const u8,
        after: []const u8,

        fn init(str: []const u8, before: []const u8, after: []const u8) @This() {
            return @This(){
                .str = str,
                .before = before,
                .after = after,
            };
        }
    };
    inline for (comptime [_]TestCast{
        TestCast.init("a", "a[]b[]d[ef]", "aa[]ba[]da[]"),
        TestCast.init("aabbcc", "a[]b[]d[ef]", "aaabbcc[]baabbcc[]daabbcc[]"),
    }) |case| {
        const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
        const t = try makeText(allocator, case.before).insert(case.str);
        expect(t, case.after);
    }
}

test "insertText" {
    var buf: [1024 * 1024]u8 = undefined;

    const TestCase = struct {
        text: []const u8,
        before: []const u8,
        after: []const u8,

        fn init(t: []const u8, before: []const u8, after: []const u8) @This() {
            return @This(){
                .text = t,
                .before = before,
                .after = after,
            };
        }
    };
    inline for (comptime [_]TestCase{
        TestCase.init("[ab]", "a[]b[]d[ef]", "aab[]bab[]dab[]"),
        TestCase.init("[a]a[c]b[e]", "a[]b[]d[ef]", "aace[]bace[]dace[]"),
        TestCase.init("[]", "a[]b[]d[ef]", "a[]b[]d[]"),
    }) |case| {
        const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
        const t = try makeText(allocator, case.before).insertText(makeText(allocator, case.text));
        expect(t, case.after);
    }
}

test "pasteText" {
    var buf: [1024 * 1024]u8 = undefined;

    const TestCase = struct {
        text: []const u8,
        before: []const u8,
        after: []const u8,

        fn init(t: []const u8, before: []const u8, after: []const u8) @This() {
            return @This(){
                .text = t,
                .before = before,
                .after = after,
            };
        }
    };
    inline for (comptime [_]TestCase{
        TestCase.init("[ab]", "a[]b[]d[ef]", "aab[]bab[]dab[]"),
        TestCase.init("[a]a[c]b[e]", "a[]b[]d[ef]", "aa[]bc[]de[]"),
        TestCase.init("[]", "a[]b[]d[ef]", "a[]b[]d[]"),
    }) |case| {
        const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
        const t = try makeText(allocator, case.before).pasteText(makeText(allocator, case.text));
        expect(t, case.after);
    }
}

fn expect(found: Text, e: []const u8) void {
    var buf: [1024 * 1024]u8 = undefined;
    var sos = io.SliceOutStream.init(&buf);
    printText(&sos.stream, found);

    if (!mem.eql(u8, e, sos.getWritten())) {
        debug.warn("\nTest failed!!!\n");
        debug.warn("########## Expect ##########\n{}\n", e);
        debug.warn("########## Actual ##########\n{}\n", sos.getWritten());
        @panic("");
    }
}

fn printText(stream: var, t: Text) void {
    var buf: [1024 * 1024]u8 = undefined;
    const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
    const content = t.content.toSlice(allocator) catch unreachable;
    const cursors = t.cursors.toSlice(allocator) catch unreachable;
    var offset: usize = 0;
    for (cursors) |cursor| {
        const start = cursor.start().index;
        const end = cursor.end().index;
        stream.print("{}[{}]", content[offset..start], content[start..end]) catch unreachable;
        offset = end;
    }
    stream.print("{}", content[offset..]) catch unreachable;
}

// Creates 'Text' from a template string. '[' and ']' are used
// to mark the start and end of cursors
fn makeText(allocator: *mem.Allocator, comptime str: []const u8) Text {
    const Indexs = struct {
        start: usize,
        end: usize,
    };
    comptime var t: []const u8 = "";
    comptime var cursor_indexs: []const Indexs = [_]Indexs{};
    comptime {
        var offset: usize = 0;
        var tmp = str;
        while (mem.indexOfScalar(u8, tmp, '[')) |start| {
            t = t ++ tmp[0..start];
            tmp = tmp[start + 1 ..];
            const len = mem.indexOfScalar(u8, tmp, ']') orelse @compileError("Unmatched cursor");
            t = t ++ tmp[0..len];
            tmp = tmp[len + 1 ..];
            cursor_indexs = cursor_indexs ++ [_]Indexs{Indexs{
                .start = offset + start,
                .end = offset + start + len,
            }};
            offset += len + start;
        }

        t = t ++ tmp;
    }

    const content = Content.fromSlice(allocator, t) catch unreachable;
    var cursors: [cursor_indexs.len]Cursor = undefined;
    for (cursor_indexs) |indexs, i| {
        cursors[i] = Cursor{
            .selection = Location.fromIndex(indexs.start, content),
            .index = Location.fromIndex(indexs.end, content),
        };
    }

    return Text{
        .allocator = allocator,
        .content = content,
        .cursors = Cursors.fromSlice(allocator, cursors) catch unreachable,
    };
}
