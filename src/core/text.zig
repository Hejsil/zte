const std = @import("std");

const core = @import("../core.zig");

const debug = std.debug;
const math = std.math;
const mem = std.mem;

// TODO: Currently we are using this location abstraction to get line, column from a
//       Cursor. Think about replacing this with the Cursor being a line, column pair,
//       and text being a list of lines (imut.List(Content)).
//
//  Pros: - No need to find the location when we move.
//
//  Cons: - Currently, we can mmap a file and call List(u8).fromSlice on it. This takes
//          2-3 seconds on a 4.5 Gig file. This is a really fast load speed for such
//          a large file.
pub const Location = struct {
    line: usize = 0,
    column: usize = 0,
    index: usize = 0,

    pub fn equal(a: Location, b: Location) bool {
        if (a.index == b.index) {
            debug.assert(a.column == b.column);
            debug.assert(a.line == b.line);
            return true;
        }
        return false;
    }

    /// Get the location of an index in some text.
    pub fn fromIndex(index: usize, text: Text.Content) Location {
        var res = Location{};
        return res.moveForwardTo(index, text);
    }

    /// Get the location of an index in some text. This function starts
    /// at 'loc' and goes forward/backward until it hits 'index'. This
    /// can be faster than 'fromIndex', when 'index' is close to 'loc'.
    pub fn moveTo(loc: Location, index: usize, text: Text.Content) Location {
        if (loc.index <= index) {
            return loc.moveForwardTo(index, text);
        } else {
            return loc.moveBackwardTo(index, text);
        }
    }

    /// Get the location of an index in some text. This function starts
    /// at 'loc' and goes backward until it hits 'index'. This can be
    /// faster than 'fromIndex', when 'index' is close to 'loc'.
    /// Requirements:
    /// - 'index' must be located before 'loc'.
    pub fn moveBackwardTo(loc: Location, index: usize, text: Text.Content) Location {
        debug.assert(index <= text.len());
        debug.assert(index <= loc.index);
        const half = loc.index / 2;
        if (index <= half)
            return fromIndex(index, text);

        var res = loc;
        while (res.index != index) : (res.index -= 1) {
            const c = text.at(res.index - 1);
            if (c == '\n')
                res.line -= 1;
        }
        var i: usize = res.index;
        while (i != 0) : (i -= 1) {
            const c = text.at(i - 1);
            if (c == '\n')
                break;
        }

        res.column = res.index - i;
        return res;
    }

    /// Get the location of an index in some text. This function starts
    /// at 'loc' and goes forward until it hits 'index'. This can be
    /// faster than 'fromIndex', when 'index' is close to 'loc'.
    /// Requirements:
    /// - 'index' must be located after 'loc'.
    pub fn moveForwardTo(location: Location, index: usize, text: Text.Content) Location {
        debug.assert(index <= text.len());
        debug.assert(location.index <= index);

        const ForeachContext = struct {
            index: usize,
            loc: *Location,
        };

        // This foreach impl is about 2 seconds faster than the iterator version
        // on 4.5 Gig file, when cursor is at the end. Look at assembly to figure
        // out why. Do more profiling.
        var res = location;
        res.index = res.lineStart();
        res.column = 0;
        text.foreach(res.index, ForeachContext{ .index = index, .loc = &res }, struct {
            fn each(context: ForeachContext, i: usize, c: u8) error{Break}!void {
                const loc = context.loc;
                if (i == context.index)
                    return error.Break;
                if (c == '\n') {
                    loc.line += 1;
                    loc.index = i + 1;
                }
            }
        }.each) catch {};

        res.column = index - res.index;
        res.index = index;
        return res;
    }

    /// Get the location of 'line'. If 'loc.line == line' then 'loc' will
    /// be returned. If the end of the text is reached before we reached
    /// the desired line, then the location returned will be at the end
    /// of the 'loc.text'. Otherwise the location returned with always be
    /// at the start of the line it moved to.
    pub fn moveToLine(loc: Location, line: usize, text: Text.Content) Location {
        if (loc.line <= line) {
            return loc.moveForwardToLine(line, text);
        } else {
            return loc.moveBackwardToLine(line, text);
        }
    }

    /// Get the location of 'line'. If 'loc.line == line' then 'loc' will
    /// be returned. If the end of the text is reached before we reached
    /// the desired line, then the location returned will be at the end
    /// of the 'loc.text'. Otherwise the location returned with always be
    /// at the start of the line it moved to.
    /// Requirements:
    /// - 'line' must be located after 'loc'.
    pub fn moveForwardToLine(loc: Location, line: usize, text: Text.Content) Location {
        debug.assert(loc.line <= line);
        var res = loc;
        while (res.line < line and res.index != text.len())
            res = res.nextLine(text);

        return res;
    }

    /// Get the location of 'line'. If 'loc.line == line' then 'loc' will
    /// be returned. Otherwise the location returned with always be at
    /// the start of the line it moved to.
    /// Requirements:
    /// - 'line' must be located before 'loc'.
    pub fn moveBackwardToLine(loc: Location, line: usize, text: Text.Content) Location {
        debug.assert(line <= loc.line);
        var res = loc;
        while (line < res.line) : (res.index -= 1) {
            const c = text.at(res.index - 1);
            if (c == '\n')
                res.line -= 1;
        }
        while (res.index != 0) : (res.index -= 1) {
            const c = text.at(res.index - 1);
            if (c == '\n')
                break;
        }

        res.column = 0;
        return res;
    }

    /// Get the location of the line after 'loc'. If the end of the text
    /// is reached, then the location returned will be at the end of
    /// 'loc.text'.
    pub fn nextLine(location: Location, text: Text.Content) Location {
        var res = location;
        res.index = res.lineStart();
        res.column = 0;
        text.foreach(res.index, &res, struct {
            fn each(loc: *Location, i: usize, c: u8) error{Break}!void {
                if (c == '\n') {
                    loc.line += 1;
                    loc.index = i + 1;
                    return error.Break;
                }
            }
        }.each) catch {
            return res;
        };

        res.column = text.len() - res.index;
        res.index = text.len();
        return res.moveForwardTo(text.len(), text);
    }

    /// Get the index of the line this location is on.
    pub fn lineStart(loc: Location) usize {
        return loc.index - loc.column;
    }

    /// Get the length of the line this location is on.
    pub fn lineLen(loc: Location, text: Text.Content) usize {
        var res: usize = 0;
        var it = text.iterator(loc.lineStart());
        while (it.next()) |c| : (res += 1) {
            if (c == '\n')
                break;
        }

        return res;
    }
};

pub const Cursor = struct {
    // The primary location of the cursor. This should be treated
    // as the cursors location.
    index: Location = Location{},

    // The secondary location of the cursor. Represents where the
    // selection ends. Can be both before and after 'index'
    selection: Location = Location{},

    pub fn start(cursor: Cursor) Location {
        return if (cursor.index.index < cursor.selection.index) cursor.index else cursor.selection;
    }

    pub fn end(cursor: Cursor) Location {
        return if (cursor.index.index < cursor.selection.index) cursor.selection else cursor.index;
    }

    pub fn equal(a: Cursor, b: Cursor) bool {
        return Location.equal(a.start(), b.start()) and Location.equal(a.end(), b.end());
    }

    pub const ToMove = enum {
        Index,
        Selection,
        Both,
    };

    pub const Direction = enum {
        Up,
        Down,
        Left,
        Right,
    };

    pub fn move(cursor: Cursor, text: Text.Content, amount: usize, to_move: ToMove, dir: Direction) Cursor {
        debug.assert(cursor.index.index <= text.len());
        debug.assert(cursor.selection.index <= text.len());
        if (amount == 0)
            return cursor;

        var res = cursor;
        var ptr: *Location = undefined;
        var other_ptr: *Location = undefined;
        switch (to_move) {
            .Index => {
                ptr = &res.index;
                other_ptr = &res.index;
            },
            .Selection => {
                ptr = &res.selection;
                other_ptr = &res.selection;
            },
            .Both => {
                ptr = &res.index;
                other_ptr = &res.selection;
            },
        }

        switch (dir) {
            .Up => blk: {
                if (ptr.line < amount) {
                    ptr.* = Location{};
                    break :blk;
                }

                const col = ptr.column;
                ptr.* = ptr.moveBackwardToLine(ptr.line - amount, text);
                debug.assert(ptr.column == 0);

                ptr.column = math.min(ptr.lineLen(text), col);
                ptr.index += ptr.column;
            },
            .Down => blk: {
                const col = ptr.column;
                ptr.* = ptr.moveForwardToLine(ptr.line + amount, text);
                if (ptr.index == text.len())
                    break :blk;

                debug.assert(ptr.column == 0);
                ptr.column = math.min(ptr.lineLen(text), col);
                ptr.index += ptr.column;
            },
            .Left => ptr.* = ptr.moveBackwardTo(math.sub(usize, ptr.index, amount) catch 0, text),
            .Right => {
                const index = math.add(usize, ptr.index, amount) catch math.maxInt(usize);
                ptr.* = ptr.moveForwardTo(math.min(index, text.len()), text);
            },
        }
        other_ptr.* = ptr.*;
        return res;
    }

    fn toBefore(index: usize, text: Text.Content, find: u8) ?usize {
        var i: usize = index;
        while (i != 0) : (i -= 1) {
            const c = text.at(i - 1);
            if (c == '\n')
                return i - 1;
        }

        return null;
    }

    fn column(index: usize, text: Text.Content) usize {
        const before = toBefore(index, text, '\n') orelse return index;
        return index - (before + 1);
    }
};

pub const Text = struct {
    allocator: *mem.Allocator,
    content: Content = Content{},
    cursors: Cursors = Cursors.fromSliceSmall([_]Cursor{Cursor{}}),
    main_cursor: MainCursorIs = MainCursorIs.Last,

    pub const Content = core.NoAllocatorList(u8);
    pub const Cursors = core.NoAllocatorList(Cursor);

    const MainCursorIs = enum {
        First,
        Last,
    };

    pub const DeleteDir = enum {
        Left,
        Right,
    };

    pub fn fromString(allocator: *mem.Allocator, str: []const u8) !Text {
        return Text{
            .allocator = allocator,
            .content = try Content.fromSlice(allocator, str),
        };
    }

    pub fn equal(a: Text, b: Text) bool {
        return a.content.equal(b.content) and a.cursors.equal(b.cursors) and a.main_cursor == b.main_cursor;
    }

    pub fn spawnCursor(text: Text, dir: Cursor.Direction) !Text {
        var res = text;
        res.main_cursor = switch (dir) {
            .Left, .Up => MainCursorIs.First,
            .Right, .Down => MainCursorIs.Last,
        };

        const main = res.mainCursor();
        const new = main.move(text.content, 1, .Both, dir);
        switch (res.main_cursor) {
            .First => {
                if (mergeCursors(new, main) == null)
                    res.cursors = try res.cursors.insert(text.allocator, 0, new);
            },
            .Last => {
                if (mergeCursors(main, new) == null)
                    res.cursors = try res.cursors.append(text.allocator, new);
            },
        }

        return res;
    }

    pub fn mainCursor(text: Text) Cursor {
        debug.assert(text.cursors.len() != 0);
        switch (text.main_cursor) {
            .First => return text.cursors.at(0),
            .Last => return text.cursors.at(text.cursors.len() - 1),
        }
    }

    pub fn removeAllButMainCursor(text: Text) Text {
        var res = text;
        const main = res.mainCursor();
        res.cursors = Cursors.fromSliceSmall([_]Cursor{main});

        return res;
    }

    pub fn moveCursors(text: Text, amount: usize, to_move: Cursor.ToMove, dir: Cursor.Direction) !Text {
        const Args = struct {
            amount: usize,
            to_move: Cursor.ToMove,
            dir: Cursor.Direction,
        };
        return text.foreachCursor(Args{ .amount = amount, .to_move = to_move, .dir = dir }, struct {
            fn action(args: Args, allocator: *mem.Allocator, cc: CursorContent, i: usize) error{}!CursorContent {
                var res = cc;
                res.cursor = res.cursor.move(res.content, args.amount, args.to_move, args.dir);
                return res;
            }
        }.action);
    }

    pub fn delete(text: Text, direction: DeleteDir) !Text {
        return text.foreachCursor(direction, struct {
            fn action(dir: DeleteDir, allocator: *mem.Allocator, cc: CursorContent, i: usize) !CursorContent {
                var res = cc;
                if (Location.equal(res.cursor.index, res.cursor.selection)) {
                    switch (dir) {
                        .Left => {
                            if (res.cursor.index.index != 0) {
                                res.cursor = res.cursor.move(res.content, 1, .Both, .Left);
                                res.content = try res.content.remove(allocator, res.cursor.index.index);
                            }
                        },
                        .Right => {
                            if (res.cursor.index.index != res.content.len())
                                res.content = try res.content.remove(allocator, res.cursor.index.index);
                        },
                    }
                } else {
                    const s = res.cursor.start();
                    const e = res.cursor.end();
                    res.cursor.index = s;
                    res.cursor.selection = s;
                    res.content = try res.content.removeItems(allocator, s.index, e.index - s.index);
                }

                return res;
            }
        }.action);
    }

    pub fn insert(text: Text, string: []const u8) !Text {
        return text.foreachCursor(string, struct {
            fn action(str: []const u8, allocator: *mem.Allocator, cc: CursorContent, i: usize) !CursorContent {
                var res = cc;
                const s = res.cursor.start();
                const e = res.cursor.end();
                res.cursor.index = s;
                res.cursor.selection = s;
                res.content = try res.content.removeItems(allocator, s.index, e.index - s.index);
                res.content = try res.content.insertSlice(allocator, s.index, str);
                res.cursor = res.cursor.move(res.content, str.len, .Both, .Right);
                return res;
            }
        }.action);
    }

    pub fn paste(text: Text, string: []const u8) !Text {
        var it = mem.separate(string, "\n");
        var lines: usize = 0;
        while (it.next()) |_| : (lines += 1) {}

        if (text.cursors.len() != lines)
            return insert(text, string);

        it = mem.separate(string, "\n");
        return text.foreachCursor(&it, struct {
            fn each(split: *mem.SplitIterator, allocator: *mem.Allocator, cc: CursorContent, i: usize) !CursorContent {
                var res = cc;
                const s = res.cursor.start();
                const e = res.cursor.end();
                res.cursor.index = s;
                res.cursor.selection = s;

                const line = split.next().?;
                res.content = try res.content.removeItems(allocator, s.index, e.index - s.index);
                res.content = try res.content.insertSlice(allocator, res.cursor.start().index, line);
                res.cursor = res.cursor.move(res.content, line.len, .Both, .Right);
                return res;
            }
        }.each);
    }

    pub fn insertText(text: Text, other: Text) !Text {
        return text.foreachCursor(other, struct {
            fn each(t: Text, allocator: *mem.Allocator, cc: CursorContent, i: usize) !CursorContent {
                var res = cc;
                const s = res.cursor.start();
                const e = res.cursor.end();
                res.cursor.index = s;
                res.cursor.selection = s;
                res.content = try res.content.removeItems(allocator, s.index, e.index - s.index);

                var it = t.cursors.iterator(0);
                while (it.next()) |cursor| {
                    const to_insert = try t.content.slice(allocator, cursor.start().index, cursor.end().index);
                    res.content = try res.content.insertList(allocator, res.cursor.start().index, to_insert);
                    res.cursor = res.cursor.move(res.content, to_insert.len(), .Both, .Right);
                }

                return res;
            }
        }.each);
    }

    /// Paste the selected text from 'other' into the selections
    /// of 'text'. If an equal number of cursors is present in both
    /// 'text' and 'other', then each cursor selection in 'other'
    /// will be pasted into each cursor selection of 'text' in order.
    /// Otherwise, the behavior will be the same as 'insertText'.
    pub fn pasteText(text: Text, other: Text) !Text {
        if (text.cursors.len() != other.cursors.len())
            return insertText(text, other);

        return text.foreachCursor(other, struct {
            fn each(t: Text, allocator: *mem.Allocator, cc: CursorContent, i: usize) !CursorContent {
                var res = cc;
                const s = res.cursor.start();
                const e = res.cursor.end();
                res.cursor.index = s;
                res.cursor.selection = s;

                const selection = t.cursors.at(i);
                const to_insert = try t.content.slice(allocator, selection.start().index, selection.end().index);
                res.content = try res.content.removeItems(allocator, s.index, e.index - s.index);
                res.content = try res.content.insertList(allocator, res.cursor.start().index, to_insert);
                res.cursor = res.cursor.move(res.content, to_insert.len(), .Both, .Right);
                return res;
            }
        }.each);
    }

    pub fn indent(text: Text, char: u8, num: usize) !Text {
        const Context = struct {
            char: u8,
            num: usize,
        };

        return text.foreachCursor(Context{
            .char = char,
            .num = num,
        }, struct {
            fn each(context: Context, allocator: *mem.Allocator, cc: CursorContent, _: usize) !CursorContent {
                var res = cc;
                const s = res.cursor.start();
                const e = res.cursor.end();
                res.cursor.index = s;
                res.cursor.selection = s;

                res.content = try res.content.removeItems(allocator, s.index, e.index - s.index);
                const to_insert = context.num - s.column % context.num;
                var i = to_insert;
                while (i != 0) : (i -= 1)
                    res.content = try res.content.insert(allocator, res.cursor.start().index, context.char);

                res.cursor = res.cursor.move(res.content, to_insert, .Both, .Right);
                return res;
            }
        }.each);
    }

    const CursorContent = struct {
        cursor: Cursor,
        content: Content,
    };

    // action: fn (@typeOf(content), CursorContent, usize) !CursorContent
    fn foreachCursor(text: Text, context: var, action: var) !Text {
        debug.assert(text.cursors.len() != 0);
        var res = text;
        res.cursors = Cursors{};

        var deleted: usize = 0;
        var added: usize = 0;
        var it = text.cursors.iterator(0);
        var i: usize = 0;
        var prev_loc: Location = text.cursors.at(0).start();
        var m_prev: ?Cursor = null;
        while (it.next()) |cursor| : (i += 1) {
            const index_index = (cursor.index.index + added) - deleted;
            const selection_index = (cursor.selection.index + added) - deleted;

            const old_len = res.content.len();
            const pair = try action(
                context,
                res.allocator,
                CursorContent{
                    .cursor = Cursor{
                        .index = prev_loc.moveTo(index_index, res.content),
                        .selection = prev_loc.moveTo(selection_index, res.content),
                    },
                    .content = res.content,
                },
                i,
            );
            res.content = pair.content;
            if (math.sub(usize, old_len, res.content.len())) |taken| {
                deleted += taken;
            } else |_| {
                added += res.content.len() - old_len;
            }

            prev_loc = pair.cursor.end();
            if (m_prev) |prev| {
                if (mergeCursors(prev, pair.cursor)) |merged| {
                    m_prev = merged;
                } else {
                    try res.cursors.appendMut(text.allocator, prev);
                    m_prev = pair.cursor;
                }
            } else {
                m_prev = pair.cursor;
            }
        }

        if (m_prev) |prev|
            try res.cursors.appendMut(text.allocator, prev);

        return res;
    }

    fn mergeCursors(left: Cursor, right: Cursor) ?Cursor {
        debug.assert(left.start().index <= right.start().index);
        if (left.end().index < right.start().index)
            return null;

        return Cursor{
            .selection = left.start(),
            .index = right.end(),
        };
    }
};
