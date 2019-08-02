const std = @import("std");

const core = @import("core.zig");
const terminal = @import("terminal.zig");
const vt100 = @import("vt100.zig");

const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const unicode = std.unicode;

const Editor = core.Editor;
const Location = core.Location;

// TODO: This is just something i put together real quick. I was playing around
//       with having a gui tree without an allocations of dynamic dispatch.
//       It's not super clean, but it works. I think this idea could be refined.
//       I should probably replace this with a more proper gui solution.

pub const Size = struct {
    width: usize = 0,
    height: usize = 0,
};

pub const Range = struct {
    min: Size = Size{},
    max: Size = Size{},

    pub fn fixed(size: Size) Range {
        return Range{
            .min = size,
            .max = size,
        };
    }

    pub fn flexible(size: Size) Range {
        return Range{
            .min = size,
            .max = Size{
                .width = math.maxInt(usize),
                .height = math.maxInt(usize),
            },
        };
    }
};

pub const Orientation = enum {
    Horizontal,
    Vertical,
};

pub fn Stack(comptime Children: type) type {
    return struct {
        const Id = Children;

        orientation: Orientation,
        children: Children,

        pub fn range(s: @This()) Range {
            const children = switch (@typeInfo(Children)) {
                .Pointer => |ptr| @typeInfo(ptr.child_type).Struct.fields,
                .Struct => |str| str.fields,
                else => @compileError("TODO: Handle array and slice here too"),
            };

            var res = Range{};
            switch (s.orientation) {
                .Horizontal => {
                    inline for (children) |field| {
                        const child = &@field(s.children, field.name);
                        const child_range = child.range();
                        res.min.width = math.add(usize, res.min.width, child_range.min.width) catch math.maxInt(usize);
                        res.min.height = math.max(child_range.min.height, res.min.height);
                        res.max.width = math.add(usize, res.max.width, child_range.max.width) catch math.maxInt(usize);
                        res.max.height = math.max(child_range.max.height, res.max.height);
                    }
                },
                .Vertical => {
                    inline for (children) |field| {
                        const child = &@field(s.children, field.name);
                        const child_range = child.range();
                        res.min.height = math.add(usize, res.min.height, child_range.min.height) catch math.maxInt(usize);
                        res.min.width = math.max(child_range.min.width, res.min.width);
                        res.max.height = math.add(usize, res.max.height, child_range.max.height) catch math.maxInt(usize);
                        res.max.width = math.max(child_range.max.width, res.max.width);
                    }
                },
            }

            return res;
        }
    };
}

pub fn stack(orientation: Orientation, children: var) Stack(@typeOf(children)) {
    return Stack(@typeOf(children)){
        .orientation = orientation,
        .children = children,
    };
}

pub fn Float(comptime Children: type) type {
    return struct {
        const Id = Children;

        children: Children,

        pub fn range(s: @This()) Range {
            const children = switch (@typeInfo(Children)) {
                .Pointer => |ptr| @typeInfo(ptr.child_type).Struct.fields,
                .Struct => |str| str.fields,
                else => @compileError("TODO: Handle array and slice here too"),
            };

            var res = Range{};
            inline for (children) |field| {
                const child = &@field(s.children, field.name);
                const child_range = child.range();
                res.min.width = math.max(child_range.min.width, res.min.width);
                res.min.height = math.max(child_range.min.height, res.min.height);
                res.max.width = math.max(child_range.max.width, res.max.width);
                res.max.height = math.max(child_range.max.height, res.max.height);
            }

            return res;
        }
    };
}

pub fn float(children: var) Float(@typeOf(children)) {
    return Float(@typeOf(children)){
        .children = children,
    };
}

pub const Empty = struct {
    pub fn range(em: @This()) Range {
        return Range.flexible(Size{});
    }
};

pub const Label = struct {
    utf8: unicode.Utf8View,
    alignment: Alignment,

    pub const Alignment = enum {
        Left,
        Center,
        Right,
    };

    pub fn range(t: @This()) Range {
        var res = Size{};
        var it = mem.separate(t.utf8.bytes, "\n");
        while (it.next()) |line| : (res.height += 1) {
            var view = unicode.Utf8View.initUnchecked(line);
            var line_it = view.iterator();
            var line_len: usize = 0;
            while (line_it.nextCodepointSlice()) |_| : (line_len += 1) {}
            res.width = math.max(res.width, line_len);
        }

        return Range.fixed(res);
    }
};

pub fn label(alignment: Label.Alignment, str: []const u8) !Label {
    return Label{
        .alignment = alignment,
        .utf8 = try unicode.Utf8View.init(str),
    };
}

pub const IntFormat = struct {
    Int: type,
    format: []const u8,
};

pub fn Int(comptime format: IntFormat) type {
    return struct {
        const int_format = format;

        int: int_format.Int,

        pub fn range(i: @This()) Range {
            var cos = io.CountingOutStream(io.NullOutStream.Error).init(io.null_out_stream);
            cos.stream.print("{" ++ int_format.format ++ "}", i.int) catch unreachable;
            return Range.fixed(Size{
                .height = 1,
                .width = cos.bytes_written,
            });
        }
    };
}

pub fn int(comptime format: []const u8, i: var) Int(IntFormat{
    .Int = @typeOf(i),
    .format = format,
}) {
    return Int(IntFormat{ .Int = @typeOf(i), .format = format }){
        .int = i,
    };
}

pub const ValueFormat = struct {
    Type: type,
    format: []const u8,
};

pub fn Value(comptime format: ValueFormat) type {
    return struct {
        const value_format = format;

        value: value_format.Type,

        pub fn range(v: @This()) Range {
            var buf: [1024 * 8]u8 = undefined;
            const str = fmt.bufPrint(&buf, "{" ++ value_format.format ++ "}", v.value) catch unreachable;
            const label_view = label(.Left, str) catch unreachable;
            return label_view.range();
        }
    };
}

pub fn value(comptime format: []const u8, v: var) Value(ValueFormat{ .Type = @typeOf(v), .format = format }) {
    return Value(ValueFormat{ .Type = @typeOf(v), .format = format }){
        .value = v,
    };
}

pub fn Center(comptime Child: type) type {
    return struct {
        const Id = Child;

        child: Child,

        pub fn range(c: @This()) Range {
            return Range.flexible(c.child.range().min);
        }
    };
}

pub fn center(child: var) Center(@typeOf(child)) {
    return Center(@typeOf(child)){ .child = child };
}

fn RightResult(comptime T: type) type {
    return Stack(struct {
        _0: CustomRange(Empty),
        child: T,
    });
}

pub fn right(child: var) RightResult(@typeOf(child)) {
    const Result = RightResult(@typeOf(child));

    var range = Range.flexible(Size{});
    range.max.height = 0;
    return stack(.Horizontal, Result.Id{
        ._0 = customRange(range, Empty{}),
        .child = child,
    });
}

pub fn Background(comptime Child: type) type {
    return struct {
        const Id = Child;

        child: Child,
        background: Terminal.Color,

        pub fn range(b: @This()) Range {
            return b.child.range();
        }
    };
}

pub fn background(color: Terminal.Color, child: var) Background(@typeOf(child)) {
    return Background(@typeOf(child)){
        .child = child,
        .background = color,
    };
}

pub fn Foreground(comptime Child: type) type {
    return struct {
        const Id = Child;

        child: Child,
        foreground: Terminal.Color,

        pub fn range(b: @This()) Range {
            return b.child.range();
        }
    };
}

pub fn foreground(color: Terminal.Color, child: var) Foreground(@typeOf(child)) {
    return Foreground(@typeOf(child)){
        .child = child,
        .foreground = color,
    };
}

pub fn Attributes(comptime Child: type) type {
    return struct {
        const Id = Child;

        child: Child,
        attributes: Terminal.Attribute,

        pub fn range(b: @This()) Range {
            return b.child.range();
        }
    };
}

pub fn attributes(attr: Terminal.Attribute, child: var) Attributes(@typeOf(child)) {
    return Attributes(@typeOf(child)){
        .child = child,
        .attributes = attr,
    };
}

pub fn Clear(comptime Child: type) type {
    return struct {
        const Id = Child;

        child: Child,

        pub fn range(b: @This()) Range {
            return b.child.range();
        }
    };
}

pub fn clear(child: var) Clear(@typeOf(child)) {
    return Clear(@typeOf(child)){
        .child = child,
    };
}

pub const Visibility = enum {
    Show,
    Hide,
};

pub fn Visible(comptime Child: type) type {
    return struct {
        const Id = Child;

        visibility: Visibility,
        child: Child,

        pub fn range(v: @This()) Range {
            return switch (v.visibility) {
                .Show => v.child.range(),
                .Hide => Range{},
            };
        }
    };
}

pub fn visible(visibility: Visibility, child: var) Visible(@typeOf(child)) {
    return Visible(@typeOf(child)){
        .visibility = visibility,
        .child = child,
    };
}

pub fn Box(comptime Child: type) type {
    return struct {
        const Id = Child;

        child: Child,

        pub fn range(b: @This()) Range {
            var res = b.child.range();
            res.min.width = math.add(usize, res.min.width, 2) catch math.maxInt(usize);
            res.min.height = math.add(usize, res.min.height, 2) catch math.maxInt(usize);
            res.max.width = math.add(usize, res.max.width, 2) catch math.maxInt(usize);
            res.max.height = math.add(usize, res.max.height, 2) catch math.maxInt(usize);
            return res;
        }
    };
}

pub fn box(child: var) Box(@typeOf(child)) {
    return Box(@typeOf(child)){
        .child = child,
    };
}

pub fn CustomRange(comptime Child: type) type {
    return struct {
        const Id = Child;

        r: Range,
        child: Child,

        pub fn range(f: @This()) Range {
            return f.r;
        }
    };
}

pub fn customRange(range: Range, child: var) CustomRange(@typeOf(child)) {
    return CustomRange(@typeOf(child)){
        .r = range,
        .child = child,
    };
}

pub const TextView = struct {
    line_loc: Location = Location{},
    column: usize = 0,
    line_numbers: bool,

    text: core.Text,

    pub fn update(view: *TextView, text_size: Size) void {
        const content = view.text.content;
        const main_cursor_loc = view.text.mainCursor().index;

        // If cursor moved out of the left of the screen, adjust screen
        // left to the cursors column.
        view.column = math.min(view.column, main_cursor_loc.column);

        // If cursor moved out of the right of the screen, adjust screen
        // right until cursor is on the last visable column.
        const last_visable_column = math.sub(usize, text_size.width, 1) catch 0;
        const new_start_column = math.sub(usize, main_cursor_loc.column, last_visable_column) catch 0;
        view.column = math.max(view.column, new_start_column);

        // If cursor moved out of the top of the screen, adjust screen
        // up to the cursors line.
        var line = view.line_loc.line;
        line = math.min(line, main_cursor_loc.line);

        // If cursor moved out of the buttom of the screen, adjust screen
        // down until cursor is on the last visable line.
        const last_visable_line = math.sub(usize, text_size.height, 1) catch 0;
        const new_start_line = math.sub(usize, main_cursor_loc.line, last_visable_line) catch 0;
        line = math.max(line, new_start_line);

        // Get the new line location of the screen.
        view.line_loc = main_cursor_loc.moveToLine(line, content);
        view.line_loc.index = view.line_loc.lineStart();
        view.line_loc.column = 0;
    }

    pub fn range(t: @This()) Range {
        return Range.flexible(Size{});
    }
};

pub fn textView(line_numbers: bool, text: core.Text) TextView {
    return TextView{ .line_numbers = line_numbers, .text = text };
}

fn digits(n: var) usize {
    var tmp = n;
    var res: usize = 1;
    while (tmp >= 10) : (res += 1)
        tmp /= 10;

    return res;
}

test "digits" {
    testing.expectEqual(usize(1), digits(usize(0)));
    testing.expectEqual(usize(1), digits(usize(9)));
    testing.expectEqual(usize(2), digits(usize(10)));
    testing.expectEqual(usize(2), digits(usize(99)));
    testing.expectEqual(usize(3), digits(usize(100)));
    testing.expectEqual(usize(3), digits(usize(999)));
}

pub const Terminal = struct {
    const Pos = struct {
        x: usize = 0,
        y: usize = 0,
    };

    cells: []Cell = ([*]Cell)(undefined)[0..0],
    cell_size: Size = Size{},
    allocator: *mem.Allocator,
    top_left: Pos = Pos{},
    bot_right: Pos = Pos{},

    const Cell = struct {
        char: u32 = ' ',
        foreground: Color = .Reset,
        background: Color = .Reset,
        attributes: Attribute = .Reset,
    };

    const Color = enum(u8) {
        Reset,
        Black,
        Red,
        Green,
        Yellow,
        Blue,
        Magenta,
        Cyan,
        White,
        BrightBlack,
        BrightRed,
        BrightGreen,
        BrightYellow,
        BrightBlue,
        BrightMagenta,
        BrightCyan,
        BrightWhite,
    };

    const Attribute = enum(u8) {
        Reset,
        Bold,
        Underscore,
        Blink,
        Negative,
    };

    pub fn deinit(term: *Terminal) void {
        term.allocator.free(term.cells);
        term.* = undefined;
    }

    pub fn update(term: *Terminal, new_size: Size) !void {
        const cells = new_size.width * new_size.height;
        if (term.cells.len < cells) {
            // We we don't have enough space to represent the new terminal size, then
            // we need to reallocate
            term.cells = try term.allocator.realloc(term.cells, cells);
        }

        mem.set(Cell, term.cells, Cell{});
        term.cell_size = new_size;
        term.bot_right = Pos{
            .x = new_size.width,
            .y = new_size.height,
        };
    }

    pub fn draw(term: Terminal, view: var) void {
        const V = @typeOf(view).Child;
        const term_size = term.size();
        const view_range = view.range();
        var new = term;
        new.bot_right = Pos{
            .x = new.top_left.x + math.min(term_size.width, view_range.max.width),
            .y = new.top_left.y + math.min(term_size.height, view_range.max.height),
        };

        if (V == Empty)
            return;
        if (V == Label)
            return new.drawLabel(view.*);
        if (V == TextView)
            return new.drawText(view);
        if (@hasDecl(V, "Id")) {
            const Id = V.Id;
            if (Stack(Id) == V)
                return new.drawStack(view);
            if (Float(Id) == V)
                return new.drawFloat(view);
            if (Center(Id) == V)
                return new.drawCenter(view);
            if (CustomRange(Id) == V)
                return new.draw(&view.child);
            if (Background(Id) == V)
                return new.drawBackground(view);
            if (Foreground(Id) == V)
                return new.drawForeground(view);
            if (Attributes(Id) == V)
                return new.drawAttributes(view);
            if (Clear(Id) == V)
                return new.drawClear(view);
            if (Visible(Id) == V)
                return new.drawVisible(view);
            if (Box(Id) == V)
                return new.drawBox(view);
        }
        if (@hasDecl(V, "int_format")) {
            const int_format = V.int_format;
            if (Int(int_format) == V)
                return new.drawInt(view.*);
        }
        if (@hasDecl(V, "value_format")) {
            const value_format = V.value_format;
            if (Value(value_format) == V)
                return new.drawValue(view.*);
        }

        @compileError("Unsupported view: " ++ @typeName(V));
    }

    fn drawLabel(term: Terminal, view: Label) void {
        const term_size = term.size();
        var l: usize = 0;
        var it = mem.separate(view.utf8.bytes, "\n");
        while (it.next()) |line_str| : (l += 1) {
            if (term_size.height <= l)
                break;

            var line_view = unicode.Utf8View.initUnchecked(line_str);
            var line_it = line_view.iterator();
            var line_len: usize = 0;
            while (line_it.nextCodepointSlice()) |_| : (line_len += 1) {}

            var c: usize = switch (view.alignment) {
                .Left => 0,
                .Center => (math.sub(usize, term_size.width, line_len) catch 0) / 2,
                .Right => math.sub(usize, term_size.width, line_len) catch 0,
            };
            var skip: usize = switch (view.alignment) {
                .Left => 0,
                .Center => (math.sub(usize, line_len, term_size.width) catch 0) / 2,
                .Right => math.sub(usize, line_len, term_size.width) catch 0,
            };
            line_it = line_view.iterator();
            while (skip != 0) : (skip -= 1)
                _ = line_it.nextCodepointSlice();
            while (line_it.nextCodepoint()) |char| : (c += 1) {
                if (term_size.width <= c)
                    break;
                const cells = term.line(l);
                cells[c].char = char;
            }
        }
    }

    fn drawInt(term: Terminal, view: var) void {
        var buf: [1024]u8 = undefined;
        const str = fmt.bufPrint(&buf, "{" ++ @typeOf(view).int_format.format ++ "}", view.int) catch unreachable;
        const label_view = label(.Left, str) catch unreachable;
        term.draw(&label_view);
    }

    fn drawValue(term: Terminal, view: var) void {
        var buf: [1024 * 8]u8 = undefined;
        const str = fmt.bufPrint(&buf, "{" ++ @typeOf(view).value_format.format ++ "}", view.value) catch unreachable;
        const label_view = label(.Left, str) catch unreachable;
        term.draw(&label_view);
    }

    fn drawStack(term: Terminal, view: var) void {
        switch (view.orientation) {
            .Horizontal => term.drawStackHelper(view, .Horizontal),
            .Vertical => term.drawStackHelper(view, .Vertical),
        }
    }

    fn drawStackHelper(term: Terminal, view: var, comptime orientation: Orientation) void {
        const children = switch (@typeInfo(@typeOf(view).Child.Id)) {
            .Pointer => |ptr| @typeInfo(ptr.child_type).Struct.fields,
            .Struct => |s| s.fields,
            else => @compileError("TODO: Handle array and slice here too"),
        };

        const x_or_y = switch (orientation) {
            .Horizontal => "x",
            .Vertical => "y",
        };

        const w_or_h = switch (orientation) {
            .Horizontal => "width",
            .Vertical => "height",
        };

        const term_size = @field(term.size(), w_or_h);
        var total_size: usize = 0;
        var sizes: [children.len]usize = undefined;
        inline for (children) |field, i| {
            const child = @field(view.children, field.name);
            const min = @field(child.range().min, w_or_h);
            sizes[i] = min;
            total_size += sizes[i];
        }

        {
            comptime var i: usize = sizes.len;
            inline while (i != 0) : (i -= 1) {
                const j = i - 1;
                if (total_size < term_size) {
                    const child = @field(view.children, children[j].name);
                    const max = @field(child.range().max, w_or_h);
                    total_size -= sizes[j];
                    sizes[j] = math.min(term_size - total_size, max);
                    total_size += sizes[j];
                }
            }
        }

        var new_term = term;
        inline for (children) |field, i| {
            const child = &@field(view.children, field.name);
            const term_bot_right = @field(term.bot_right, x_or_y);
            const new_term_top_left = @field(new_term.top_left, x_or_y);
            @field(new_term.bot_right, x_or_y) = math.min(term_bot_right, new_term_top_left + sizes[i]);
            new_term.draw(child);
            @field(new_term.top_left, x_or_y) = @field(new_term.bot_right, x_or_y);
        }
    }

    fn drawFloat(term: Terminal, view: var) void {
        const children = switch (@typeInfo(@typeOf(view).Child.Id)) {
            .Pointer => |ptr| @typeInfo(ptr.child_type).Struct.fields,
            .Struct => |s| s.fields,
            else => @compileError("TODO: Handle array and slice here too"),
        };

        inline for (children) |field, i| {
            const child = &@field(view.children, field.name);
            term.draw(child);
        }
    }

    fn drawCenter(term: Terminal, view: var) void {
        const term_size = term.size();
        const view_range = view.range();
        const pad = Size{
            .width = (math.sub(usize, term_size.width, view_range.min.width) catch 0) / 2,
            .height = (math.sub(usize, term_size.height, view_range.min.height) catch 0) / 2,
        };

        var new = term;
        new.top_left.x += pad.width;
        new.top_left.y += pad.height;
        new.bot_right.x = new.top_left.x + view_range.min.width;
        new.bot_right.y = new.top_left.y + view_range.min.height;
        new.draw(&view.child);
    }

    fn drawBackground(term: Terminal, view: var) void {
        const term_size = term.size();
        var i: usize = 0;
        while (i < term_size.height) : (i += 1) {
            const cells = term.line(i);
            for (cells) |*cell|
                cell.background = view.background;
        }

        term.draw(&view.child);
    }

    fn drawForeground(term: Terminal, view: var) void {
        const term_size = term.size();
        var i: usize = 0;
        while (i < term_size.height) : (i += 1) {
            const cells = term.line(i);
            for (cells) |*cell|
                cell.foreground = view.foreground;
        }

        term.draw(&view.child);
    }

    fn drawAttributes(term: Terminal, view: var) void {
        const term_size = term.size();
        var i: usize = 0;
        while (i < term_size.height) : (i += 1) {
            const cells = term.line(i);
            for (cells) |*cell|
                cell.attributes = view.attributes;
        }

        term.draw(&view.child);
    }

    fn drawClear(term: Terminal, view: var) void {
        const term_size = term.size();
        var i: usize = 0;
        while (i < term_size.height) : (i += 1) {
            const cells = term.line(i);
            for (cells) |*cell|
                cell.* = Cell{};
        }

        term.draw(&view.child);
    }

    fn drawVisible(term: Terminal, view: var) void {
        switch (view.visibility) {
            .Show => term.draw(&view.child),
            .Hide => {},
        }
    }

    fn drawBox(term: Terminal, view: var) void {
        const term_size = term.size();
        var y: usize = 0;
        while (y < term_size.height) : (y += 1) {
            const cells = term.line(y);
            for (cells) |*cell, x| {
                if (x == 0 and y == 0) {
                    cell.char = comptime unicode.utf8Decode("┏") catch unreachable;
                } else if (x == 0 and y == term_size.height - 1) {
                    cell.char = comptime unicode.utf8Decode("┗") catch unreachable;
                } else if (x == term_size.width - 1 and y == term_size.height - 1) {
                    cell.char = comptime unicode.utf8Decode("┛") catch unreachable;
                } else if (x == term_size.width - 1 and y == 0) {
                    cell.char = comptime unicode.utf8Decode("┓") catch unreachable;
                } else if (x == 0) {
                    cell.char = comptime unicode.utf8Decode("┃") catch unreachable;
                } else if (x == term_size.width - 1) {
                    cell.char = comptime unicode.utf8Decode("┃") catch unreachable;
                } else if (y == 0) {
                    cell.char = comptime unicode.utf8Decode("━") catch unreachable;
                } else if (y == term_size.height - 1) {
                    cell.char = comptime unicode.utf8Decode("━") catch unreachable;
                }
            }
        }

        var new_term = term;
        new_term.top_left.x += 1;
        new_term.top_left.y += 1;
        new_term.draw(&view.child);
    }

    fn drawText(term: Terminal, view: *TextView) void {
        // First, we update with this terms size so that the line
        // numbers will start at the correct place
        var new_term = term;
        view.update(new_term.size());

        if (view.line_numbers) {
            const term_size = new_term.size();
            const last = view.line_loc.line + term_size.height;
            const width = digits(last);
            new_term.bot_right.x = new_term.top_left.x + width;

            var i: usize = 0;
            while (i < term_size.height) : (i += 1) {
                const digit = view.line_loc.line + i + 1;
                const line_num = foreground(.BrightBlack, right(int("", digit)));
                new_term.top_left.y = term.top_left.y + i;
                new_term.bot_right.y = new_term.top_left.y + 1;
                new_term.draw(&line_num);
            }

            new_term = term;
            new_term.top_left.x += width + 1;
        }

        // Later, we then update again so that we take into account
        // the missing space line numbers take up.
        const term_size = new_term.size();
        view.update(term_size);

        const text = view.text;
        const first_line = view.line_loc;
        var curr_line = first_line;
        outer: while (curr_line.line - first_line.line < term_size.height) : (curr_line = curr_line.nextLine(text.content)) {
            const i = curr_line.line - first_line.line;
            const move_to = math.min(curr_line.index + view.column, text.content.len());
            const start = curr_line.moveForwardTo(move_to, text.content);
            if (start.line != curr_line.line)
                continue;

            const cells = new_term.line(i);
            var it = text.content.iterator(start.index);
            var j: usize = 0;
            inner: while (j < cells.len) : (j += 1) {
                const c = it.next() orelse {
                    curr_line.line += 1;
                    break :outer;
                };
                if (c == '\n')
                    continue :outer;

                cells[j].char = c;
            }
        }

        // If we still have space on the screen after drawing all lines, then
        // we just output '~' to indicate that this is not part of the file.
        var i = curr_line.line - first_line.line;
        while (i < term_size.height) : (i += 1) {
            const cells = new_term.line(i);
            cells[0].char = '~';
            cells[0].foreground = .BrightBlack;
        }

        var cursors = text.cursors.iterator(0);
        while (cursors.next()) |curs| {
            const loc_start = curs.start();
            const loc_end = curs.end();

            if (loc_start.index == loc_end.index) {
                // Draw an '_' if the cursor does not select anything.
                const l = math.sub(usize, loc_start.line, view.line_loc.line) catch continue;
                const c = math.sub(usize, loc_start.column, view.column) catch continue;
                if (term_size.height <= l or term_size.width <= c)
                    continue;

                const cells = new_term.line(l);
                cells[c].attributes = .Underscore;
            } else {
                var line_loc = if (loc_start.index < view.line_loc.index) view.line_loc else loc_start;
                while (line_loc.line <= loc_end.line and line_loc.index < loc_end.index) : (line_loc = line_loc.nextLine(text.content)) {
                    const l = math.sub(usize, line_loc.line, view.line_loc.line) catch continue;
                    if (term_size.height <= l)
                        break;

                    // Draw selection to end of line if we are not one the same
                    // line as loc_end
                    const loc_end_column = if (line_loc.line == loc_end.line)
                        loc_end.column
                    else
                        line_loc.lineLen(text.content) + 1;
                    const start = math.sub(usize, line_loc.column, view.column) catch 0;
                    const end = math.sub(usize, loc_end_column, view.column) catch 0;

                    const real_end = math.min(term_size.width, end);
                    const cells = new_term.line(l);
                    for (cells[start..real_end]) |*cell|
                        cell.attributes = .Negative;
                }
            }
        }
    }

    fn size(term: Terminal) Size {
        return Size{
            .width = term.bot_right.x - term.top_left.x,
            .height = term.bot_right.y - term.top_left.y,
        };
    }

    fn line(term: Terminal, l: usize) []Cell {
        const real = term.top_left.y + l;
        debug.assert(real < term.bot_right.y);
        return term.cells[real * term.cell_size.width ..][term.top_left.x..term.bot_right.x];
    }

    pub fn output(term: Terminal, stream: var) !void {
        var i: usize = 0;
        var last_cell: Cell = Cell{};
        while (i < term.cell_size.height) : (i += 1) {
            const cells = term.line(i);
            for (cells) |cell, j| {
                // Only when color or attributes change do we have to set them.
                // Setting them for each character would be overkill.
                if (last_cell.foreground != cell.foreground or
                    last_cell.background != cell.background or
                    last_cell.attributes != cell.attributes)
                {
                    last_cell = cell;
                    try setAttr(stream, last_cell.attributes);
                    try setForeground(stream, last_cell.foreground);
                    try setBackground(stream, last_cell.background);
                }

                var buf: [4]u8 = undefined;
                const len = try unicode.utf8Encode(cell.char, &buf);
                try stream.write(buf[0..len]);
            }

            // Don't output a newline on the last line. That would create and empty
            // line at the buttom of the terminal
            if (i + 1 != term.cell_size.height)
                try stream.write("\r\n");
        }

        try setAttr(stream, .Reset);
        try setForeground(stream, .Reset);
        try setBackground(stream, .Reset);
    }

    fn setForeground(stream: var, color: Color) !void {
        switch (color) {
            .Reset => try stream.write(vt100.selectGraphicRendition("39")),
            .Black => try stream.write(vt100.selectGraphicRendition("30")),
            .Red => try stream.write(vt100.selectGraphicRendition("31")),
            .Green => try stream.write(vt100.selectGraphicRendition("32")),
            .Yellow => try stream.write(vt100.selectGraphicRendition("33")),
            .Blue => try stream.write(vt100.selectGraphicRendition("34")),
            .Magenta => try stream.write(vt100.selectGraphicRendition("35")),
            .Cyan => try stream.write(vt100.selectGraphicRendition("36")),
            .White => try stream.write(vt100.selectGraphicRendition("37")),
            .BrightBlack => try stream.write(vt100.selectGraphicRendition("90")),
            .BrightRed => try stream.write(vt100.selectGraphicRendition("91")),
            .BrightGreen => try stream.write(vt100.selectGraphicRendition("92")),
            .BrightYellow => try stream.write(vt100.selectGraphicRendition("93")),
            .BrightBlue => try stream.write(vt100.selectGraphicRendition("94")),
            .BrightMagenta => try stream.write(vt100.selectGraphicRendition("95")),
            .BrightCyan => try stream.write(vt100.selectGraphicRendition("96")),
            .BrightWhite => try stream.write(vt100.selectGraphicRendition("97")),
        }
    }

    fn setBackground(stream: var, color: Color) !void {
        switch (color) {
            .Reset => try stream.write(vt100.selectGraphicRendition("49")),
            .Black => try stream.write(vt100.selectGraphicRendition("40")),
            .Red => try stream.write(vt100.selectGraphicRendition("41")),
            .Green => try stream.write(vt100.selectGraphicRendition("42")),
            .Yellow => try stream.write(vt100.selectGraphicRendition("43")),
            .Blue => try stream.write(vt100.selectGraphicRendition("44")),
            .Magenta => try stream.write(vt100.selectGraphicRendition("45")),
            .Cyan => try stream.write(vt100.selectGraphicRendition("46")),
            .White => try stream.write(vt100.selectGraphicRendition("47")),
            .BrightBlack => try stream.write(vt100.selectGraphicRendition("100")),
            .BrightRed => try stream.write(vt100.selectGraphicRendition("101")),
            .BrightGreen => try stream.write(vt100.selectGraphicRendition("102")),
            .BrightYellow => try stream.write(vt100.selectGraphicRendition("103")),
            .BrightBlue => try stream.write(vt100.selectGraphicRendition("104")),
            .BrightMagenta => try stream.write(vt100.selectGraphicRendition("105")),
            .BrightCyan => try stream.write(vt100.selectGraphicRendition("106")),
            .BrightWhite => try stream.write(vt100.selectGraphicRendition("107")),
        }
    }

    fn setAttr(stream: var, attr: Attribute) !void {
        switch (attr) {
            .Reset => try stream.write(vt100.selectGraphicRendition("0")),
            .Bold => try stream.write(vt100.selectGraphicRendition("1")),
            .Underscore => try stream.write(vt100.selectGraphicRendition("4")),
            .Blink => try stream.write(vt100.selectGraphicRendition("5")),
            .Negative => try stream.write(vt100.selectGraphicRendition("7")),
        }
    }
};

const full_reset = vt100.selectGraphicRendition("0") ++
    vt100.selectGraphicRendition("39") ++
    vt100.selectGraphicRendition("49");

// zig fmt: off
test "label" {
    testDraw(
        "Hello World!                            \r\n" ++
        "Bye World!                              \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &try label(.Left, "Hello World!\nBye World!"),
    );
    testDraw(
        "Hello World!                            \r\n" ++
        " Bye World!                             \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &try label(.Center, "Hello World!\nBye World!"),
    );
    testDraw(
        "Hello World!                            \r\n" ++
        "  Bye World!                            \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &try label(.Right, "Hello World!\nBye World!"),
    );
    testDraw(
        "Hello World! Hello World! Hello World! H\r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &try label(.Left, "Hello World! Hello World! Hello World! Hello World!"),
    );
    testDraw(
        "! Hello World! Hello World! Hello World!\r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &try label(.Right, "Hello World! Hello World! Hello World! Hello World!"),
    );
    testDraw(
        " World! Hello World! Hello World! Hello \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &try label(.Center, "Hello World! Hello World! Hello World! Hello World!"),
    );
}

test "int" {
    testDraw(
        "10                                      \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &int("", isize(10)),
    );
    testDraw(
        "-10                                     \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &int("", isize(-10)),
    );
    testDraw(
        "1MB                                     \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &int("B", usize(1000 * 1000)),
    );
}

test "value" {
    const S = struct {
        a: usize,
        b: usize,

        pub fn format(
            self: @This(),
            comptime form: []const u8,
            comptime options: std.fmt.FormatOptions,
            context: var,
            comptime Errors: type,
            output: fn (@typeOf(context), []const u8) Errors!void,
        ) Errors!void {
            return std.fmt.format(
                context,
                Errors,
                output,
                "{}  {}",
                self.a,
                self.b,
            );
        }
    };

    testDraw(
        "10  12                                  \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &value("", S{ .a = 10, .b = 12 }),
    );
}

test "stack" {
    // TODO: When/If Zig gets anonymous array/struct init, then making a stack
    //       will look a lot cleaner: stack(.Vertical, .{ view_a, view_b });
    //       One could even use names: stack(.Vertical, .{ .top = view_a, .bot = view_b });
    testDraw(
        "HelloWorld!                             \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &stack(.Horizontal, struct {
            _0: Label = label(.Left, "Hello") catch unreachable,
            _1: Label = label(.Left, "World!") catch unreachable,
        }{}),
    );
    testDraw(
        "Hello                                   \r\n" ++
        "World!                                  \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &stack(.Vertical, struct {
            _0: Label = label(.Left, "Hello") catch unreachable,
            _1: Label = label(.Left, "World!") catch unreachable,
        }{}),
    );
}

test "float" {
    testDraw(
        "11CD                                    \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &float(struct {
            _0: Label = label(.Left, "ABCD") catch unreachable,
            _1: Label = label(.Left, "11") catch unreachable,
        }{}),
    );
}

test "center" {
    testDraw(
        "                                        \r\n" ++
        "                                        \r\n" ++
        "              Hello World!              \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &center(try label(.Left, "Hello World!")),
    );
}

test "right" {
    testDraw(
        "                            Hello World!\r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &right(try label(.Left, "Hello World!")),
    );
    testDraw(
        "                                       2\r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &right(int("", usize(2))),
    );
}

test "visible" {
    testDraw(
        "1MB                                     \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &visible(.Show, int("B", usize(1000 * 1000))),
    );
    testDraw(
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &visible(.Hide, int("B", usize(1000 * 1000))),
    );
}

test "box" {
    testDraw(
        "┏━━━━┓                                  \r\n" ++
        "┃1000┃                                  \r\n" ++
        "┗━━━━┛                                  \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &box(int("", usize(1000))),
    );
}

// zig fmt: on
fn backgStart(comptime num: []const u8) []const u8 {
    return vt100.selectGraphicRendition("0") ++
        vt100.selectGraphicRendition("39") ++
        vt100.selectGraphicRendition(num);
}

fn backg(comptime num: []const u8, comptime str: []const u8) []const u8 {
    return backgStart(num) ++ str ++ full_reset;
}

fn foregStart(comptime num: []const u8) []const u8 {
    return vt100.selectGraphicRendition("0") ++
        vt100.selectGraphicRendition(num) ++
        vt100.selectGraphicRendition("49");
}

fn foreg(comptime num: []const u8, comptime str: []const u8) []const u8 {
    return foregStart(num) ++ str ++ full_reset;
}

fn attriStart(comptime num: []const u8) []const u8 {
    return vt100.selectGraphicRendition(num) ++
        vt100.selectGraphicRendition("39") ++
        vt100.selectGraphicRendition("49");
}

fn attri(comptime num: []const u8, comptime str: []const u8) []const u8 {
    return attriStart(num) ++ str ++ full_reset;
}

// zig fmt: off
test "background" {
    testDraw(
        backg("47", "Hello World") ++ "                             \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &background(.White, label(.Left, "Hello World") catch unreachable),
    );
    testDraw(
        backg("47", "Hello") ++ "World!                             \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &stack(.Horizontal, struct {
            _0: Background(Label) = background(.White, label(.Left, "Hello") catch unreachable),
            _1: Label = label(.Left, "World!") catch unreachable,
        }{}),
    );
}

test "foreground" {
    testDraw(
        foreg("31", "Hello World") ++ "                             \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &foreground(.Red, label(.Left, "Hello World") catch unreachable),
    );
    testDraw(
        foreg("31", "Hello") ++ "World!                             \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &stack(.Horizontal, struct {
            _0: Foreground(Label) = foreground(.Red, label(.Left, "Hello") catch unreachable),
            _1: Label = label(.Left, "World!") catch unreachable,
        }{}),
    );
}

test "attributes" {
    testDraw(
        attri("4", "Hello World") ++ "                             \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &attributes(.Underscore, label(.Left, "Hello World") catch unreachable),
    );
    testDraw(
        attri("4", "Hello") ++ "World!                             \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &stack(.Horizontal, struct {
            _0: Attributes(Label) = attributes(.Underscore, label(.Left, "Hello") catch unreachable),
            _1: Label = label(.Left, "World!") catch unreachable,
        }{}),
    );
}

test "float" {
    const blank = comptime clear(customRange(Range.fixed(Size{ .width = 2, .height = 1 }), Empty{}));
    testDraw(
        "  CD                                    \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        "                                        " ++ full_reset,
        &float(struct {
            _0: Label = label(.Left, "ABCD") catch unreachable,
            _1: @typeOf(blank) = blank,
        }{}),
    );
}

test "textView" {
    var buf: [1024 * 2]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);
    var text = try core.Text.fromString(&fba.allocator, "A\nB\nC\nD\nE\nF\nG\nH\nI\nJ\nK\nL\n");
    testDraw(
        attri("4", "A") ++ "                                       \r\n" ++
        "B                                       \r\n" ++
        "C                                       \r\n" ++
        "D                                       \r\n" ++
        "E                                       \r\n" ++
        "F                                       " ++ full_reset,
        &textView(false, text),
    );
    testDraw(
        foreg("90", "1") ++ " " ++ attri("4", "A") ++ "                                     \r\n" ++
        foreg("90", "2") ++ " B                                     \r\n" ++
        foreg("90", "3") ++ " C                                     \r\n" ++
        foreg("90", "4") ++ " D                                     \r\n" ++
        foreg("90", "5") ++ " E                                     \r\n" ++
        foreg("90", "6") ++ " F                                     " ++ full_reset,
        &textView(true, text),
    );

    text = try text.moveCursors(9, .Both, .Down);
    testDraw(
        "E                                       \r\n" ++
        "F                                       \r\n" ++
        "G                                       \r\n" ++
        "H                                       \r\n" ++
        "I                                       \r\n" ++
        attri("4", "J") ++ "                                       " ++ full_reset,
        &textView(false, text),
    );
    testDraw(
        foreg("90", " 5") ++ " E                                    \r\n" ++
        foreg("90", " 6") ++ " F                                    \r\n" ++
        foreg("90", " 7") ++ " G                                    \r\n" ++
        foreg("90", " 8") ++ " H                                    \r\n" ++
        foreg("90", " 9") ++ " I                                    \r\n" ++
        foreg("90", "10") ++ " " ++ attri("4", "J") ++ "                                    " ++ full_reset,
        &textView(true, text),
    );

    text = try core.Text.fromString(&fba.allocator, "ABCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklmnopqrstuvwyz\n:\n");
    testDraw(
        attri("4", "A") ++ "BCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklmno\r\n" ++
        ":                                       \r\n" ++
        "                                        \r\n" ++
        foreg("90", "~") ++ "                                       \r\n" ++
        foreg("90", "~") ++ "                                       \r\n" ++
        foreg("90", "~") ++ "                                       " ++ full_reset,
        &textView(false, text),
    );
    testDraw(
        foreg("90", "1") ++ " " ++ attri("4", "A") ++ "BCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklm\r\n" ++
        foreg("90", "2") ++ " :                                     \r\n" ++
        foreg("90", "3") ++ "                                       \r\n" ++
        foreg("90", "4") ++ " " ++ foreg("90", "~") ++ "                                     \r\n" ++
        foreg("90", "5") ++ " " ++ foreg("90", "~") ++ "                                     \r\n" ++
        foreg("90", "6") ++ " " ++ foreg("90", "~") ++ "                                     " ++ full_reset,
        &textView(true, text),
    );
    
    text = try text.moveCursors(40, .Both, .Right); 
    testDraw(
        "BCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklmno" ++ attri("4", "p\r\n") ++
        "                                        \r\n" ++
        "                                        \r\n" ++
        foreg("90", "~") ++ "                                       \r\n" ++
        foreg("90", "~") ++ "                                       \r\n" ++
        foreg("90", "~") ++ "                                       " ++ full_reset,
        &textView(false, text),
    );
    testDraw(
        foreg("90", "1") ++ " DEFGHIJKLMNOPQRSTUVWYZabcdefghijklmno" ++ attriStart("4") ++ "p\r\n" ++
        foreg("90", "2") ++ "                                       \r\n" ++
        foreg("90", "3") ++ "                                       \r\n" ++
        foreg("90", "4") ++ " " ++ foreg("90", "~") ++ "                                     \r\n" ++
        foreg("90", "5") ++ " " ++ foreg("90", "~") ++ "                                     \r\n" ++
        foreg("90", "6") ++ " " ++ foreg("90", "~") ++ "                                     " ++ full_reset,
        &textView(true, text),
    );
    
    
    text = try text.moveCursors(40, .Both, .Left);
    text = try text.moveCursors(1, .Index, .Down);
    testDraw(
        attri("7", "ABCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklmno\r\n") ++
        ":                                       \r\n" ++
        "                                        \r\n" ++
        foreg("90", "~") ++ "                                       \r\n" ++
        foreg("90", "~") ++ "                                       \r\n" ++
        foreg("90", "~") ++ "                                       " ++ full_reset,
        &textView(false, text),
    );
    testDraw(
        foreg("90", "1") ++ " " ++ attriStart("7") ++ "ABCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklm\r\n" ++
        foreg("90", "2") ++ " :                                     \r\n" ++
        foreg("90", "3") ++ "                                       \r\n" ++
        foreg("90", "4") ++ " " ++ foreg("90", "~") ++ "                                     \r\n" ++
        foreg("90", "5") ++ " " ++ foreg("90", "~") ++ "                                     \r\n" ++
        foreg("90", "6") ++ " " ++ foreg("90", "~") ++ "                                     " ++ full_reset,
        &textView(true, text),
    );
}

// zig fmt: on
fn escape(allocator: *mem.Allocator, str: []const u8) ![]u8 {
    var buffer = try std.Buffer.initSize(allocator, str.len);
    var bos = std.io.BufferOutStream.init(&buffer);
    defer buffer.deinit();

    for (str) |c| {
        if (std.ascii.isPrint(c) or std.ascii.isSpace(c)) {
            try bos.stream.writeByte(c);
        } else {
            try bos.stream.print("\\x{x}", c);
        }
    }

    return buffer.toOwnedSlice();
}

fn testDraw(expect: []const u8, view: var) void {
    var buf: [1024 * 8]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);
    var term = Terminal{ .allocator = &fba.allocator };
    term.update(Size{ .width = 40, .height = 6 }) catch unreachable;
    term.draw(view);

    var buf2: [1024 * 2]u8 = undefined;
    var sos = io.SliceOutStream.init(&buf2);
    term.output(&sos.stream) catch unreachable;

    if (!mem.eql(u8, expect, sos.getWritten())) {
        debug.warn("\n######## Expected ########\n");
        debug.warn("len: {}\n", expect.len);
        debug.warn("{}", expect);
        debug.warn("\n######## Actual ########\n");
        debug.warn("len: {}\n", sos.getWritten().len);
        debug.warn("{}\n", sos.getWritten());

        debug.warn("######## Expected (escaped) ########\n");
        debug.warn("{}\n", escape(&fba.allocator, expect) catch unreachable);
        debug.warn("######## Actual (escaped) ########\n");
        debug.warn("{}\n", escape(&fba.allocator, sos.getWritten()) catch unreachable);
        testing.expect(false);
    }
}
