const builtin = @import("builtin");
const std = @import("std");

const core = @import("core.zig");
const draw = @import("draw.zig");
const input = @import("input.zig");
const terminal = @import("terminal.zig");
const vt100 = @import("vt100.zig");

const ascii = std.ascii;
const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const process = std.process;

const Editor = core.Editor;
const Key = input.Key;

// TODO: Our custom panic handler does not get called when the program
//       segfaults and Zig tries to dump a stacktrace from the segfault
//       point. This means, that our terminal wont be restored and the
//       segfault stacktrace wont be printed corrently :(
pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    // If we panic, then we should restore the terminal settings like
    // we closed the program.
    if (io.getStdIn()) |stdin| {
        terminal.deinit(stdin) catch {};
        terminal.clear(&stdin.outStream().stream) catch {};
        stdin.write(vt100.cursor.show) catch {};
    } else |_| {}

    const first_trace_addr = @returnAddress();
    std.debug.panicExtra(error_return_trace, first_trace_addr, "{}", msg);
}

const modified_view = draw.visible(.Hide, draw.label(.Left, "(modified) ") catch unreachable);
const file_name_view = draw.stack(.Horizontal, struct {
    modified: @typeOf(modified_view) = modified_view,
    file_name: draw.Label = draw.label(.Left, "") catch unreachable,
}{});

const info_view = draw.right(draw.value("", struct {
    hint: []const u8 = default_hint,
    location: core.Location = core.Location{},
    allocated_bytes: usize = 0,
    freed_bytes: usize = 0,
    text_size: usize = 0,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        comptime options: std.fmt.FormatOptions,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        return std.fmt.format(
            context,
            Errors,
            output,
            "{}{} ({},{}) (t:{B:2} a:{B:2} f:{B:2})",
            if (self.hint.len != 0) " " else "",
            self.hint,
            self.location.line + 1,
            self.location.column + 1,
            self.text_size,
            self.allocated_bytes,
            self.freed_bytes,
        );
    }
}{}));

const status_bar = draw.attributes(.Negative, draw.float(struct {
    file_name: @typeOf(file_name_view) = file_name_view,
    info: @typeOf(info_view) = info_view,
}{}));

const editor_view = draw.stack(.Vertical, struct {
    text: draw.TextView = draw.textView(true, core.Text{ .allocator = undefined }),
    status_bar: @typeOf(status_bar) = status_bar,
}{});

const help_popup = blk: {
    @setEvalBranchQuota(10000);
    break :blk draw.visible(.Hide, draw.center(draw.clear(draw.attributes(.Negative, draw.box(draw.label(
        .Left,
        "'" ++ Key.toStr(help_key) ++ "': hide or show this message\n" ++
            "'" ++ Key.toStr(quit_key) ++ "': quit\n" ++
            "'" ++ Key.toStr(save_key) ++ "': save\n" ++
            "'" ++ Key.toStr(undo_key) ++ "': undo\n" ++
            "'" ++ Key.toStr(copy_key) ++ "': copy\n" ++
            "'" ++ Key.toStr(paste_key) ++ "': paste\n" ++
            "'" ++ Key.toStr(select_all_key) ++ "': select all\n" ++
            "'" ++ Key.toStr(move_up_key) ++ "': move cursors up\n" ++
            "'" ++ Key.toStr(move_down_key) ++ "': move cursors down\n" ++
            "'" ++ Key.toStr(move_left_key) ++ "': move cursors left\n" ++
            "'" ++ Key.toStr(move_right_key) ++ "': move cursors right\n" ++
            "'" ++ Key.toStr(move_page_up_key) ++ "': move cursors up one screen\n" ++
            "'" ++ Key.toStr(move_page_down_key) ++ "': move cursors down one screen\n" ++
            "'" ++ Key.toStr(move_start_key) ++ "': move cursors to start of file\n" ++
            "'" ++ Key.toStr(move_end_key) ++ "': move cursors to end of file\n" ++
            "'" ++ Key.toStr(move_select_up_key) ++ "': move selections up\n" ++
            "'" ++ Key.toStr(move_select_down_key) ++ "': move selections down\n" ++
            "'" ++ Key.toStr(move_select_left_key) ++ "': move selections left\n" ++
            "'" ++ Key.toStr(move_select_right_key) ++ "': move selections right\n" ++
            "'" ++ Key.toStr(spawn_cursor_up_key) ++ "': spawn a cursor above the main cursor\n" ++
            "'" ++ Key.toStr(spawn_cursor_down_key) ++ "': spawn a cursor below the main cursor\n" ++
            "'" ++ Key.toStr(spawn_cursor_left_key) ++ "': spawn a cursor to the left of the main cursor\n" ++
            "'" ++ Key.toStr(spawn_cursor_right_key) ++ "': spawn a cursor to the right of the main cursor\n" ++
            "'" ++ Key.toStr(delete_left_key) ++ "': delete letter to the left of cursors\n" ++
            "'" ++ Key.toStr(delete_right_key) ++ "': delete letter to the right of cursors\n" ++
            "'" ++ Key.toStr(reset_key) ++ "': general key to cancel/reset/stop the current action",
    ) catch unreachable)))));
};

const quit_popup = blk: {
    @setEvalBranchQuota(10000);
    break :blk draw.visible(.Hide, draw.center(draw.clear(draw.attributes(.Negative, draw.box(draw.label(
        .Center,
        "Warning!\n" ++
            "You have unsaved changes.\n" ++
            "Press '" ++ Key.toStr(quit_key) ++ "' to forcefully quit",
    ) catch unreachable)))));
};

const window_view = draw.float(struct {
    editor: @typeOf(editor_view) = editor_view,
    help_popup: @typeOf(help_popup) = help_popup,
    quit_popup: @typeOf(quit_popup) = quit_popup,
}{});

pub fn main() !void {
    var failing = debug.FailingAllocator.init(heap.direct_allocator, math.maxInt(usize));
    const allocator = &failing.allocator;

    const stdin = try io.getStdIn();
    const stdout = try io.getStdOut();
    const stdout_stream = &stdout.outStream().stream;
    var stdout_buf = io.BufferedOutStreamCustom(std.mem.page_size * 40, fs.File.WriteError).init(stdout_stream);

    const args = try process.argsAlloc(allocator);
    defer allocator.free(args);

    var app = App{
        .editor = if (args.len <= 1)
            try Editor.fromString(allocator, "")
        else
            try Editor.fromFile(allocator, args[1]),
        .view = window_view,
    };

    var term = draw.Terminal{ .allocator = allocator };

    try terminal.init(stdin);
    defer terminal.deinit(stdin) catch {};

    while (true) {
        const text = app.editor.current();
        const bar = &app.view.children.editor.children.status_bar.child.children;
        const info = &bar.info.children.child.value;
        info.location = text.mainCursor().index;
        info.allocated_bytes = failing.allocated_bytes;
        info.freed_bytes = failing.freed_bytes;
        info.text_size = text.content.len();
        app.view.children.editor.children.text.text = text;
        bar.file_name.children.modified.visibility = if (app.editor.dirty()) draw.Visibility.Show else draw.Visibility.Hide;
        bar.file_name.children.file_name = if (app.editor.file) |file|
            try draw.label(.Left, file.path)
        else
            try draw.label(.Left, "???");

        const size = try terminal.size(stdout, stdin);
        try term.update(draw.Size{
            .width = size.columns,
            .height = size.rows,
        });
        term.draw(&app.view);
        try terminal.clear(&stdout_buf.stream);
        try term.output(&stdout_buf.stream);
        try stdout_buf.flush();

        const key = try input.readKey(stdin);
        app = (try handleInput(app, key)) orelse break;
    }

    try terminal.clear(&stdout_buf.stream);
    try stdout_buf.stream.write(vt100.cursor.show);
    try stdout_buf.flush();
}

const App = struct {
    editor: core.Editor,
    view: @typeOf(window_view),
};

const help_key = Key.ctrl | Key.alt | 'h';
const quit_key = Key.ctrl | 'q';
const save_key = Key.ctrl | 's';
const undo_key = Key.ctrl | 'z';
const copy_key = Key.ctrl | 'c';
const paste_key = Key.ctrl | 'v';
const select_all_key = Key.ctrl | 'a';
const move_up_key = Key.arrow_up;
const move_down_key = Key.arrow_down;
const move_left_key = Key.arrow_left;
const move_right_key = Key.arrow_right;
const move_page_up_key = Key.page_up;
const move_page_down_key = Key.page_down;
const move_start_key = Key.home;
const move_end_key = Key.end;
const move_select_up_key = Key.shift | Key.arrow_up;
const move_select_down_key = Key.shift | Key.arrow_down;
const move_select_left_key = Key.shift | Key.arrow_left;
const move_select_right_key = Key.shift | Key.arrow_right;
const spawn_cursor_up_key = Key.ctrl | Key.arrow_up;
const spawn_cursor_down_key = Key.ctrl | Key.arrow_down;
const spawn_cursor_left_key = Key.ctrl | Key.arrow_left;
const spawn_cursor_right_key = Key.ctrl | Key.arrow_right;
const delete_left_key = Key.backspace;
const delete_right_key = Key.delete;
const reset_key = Key.esc;

const default_hint = "'" ++ Key.toStr(help_key) ++ "' for help";

fn handleInput(app: App, key: Key.Type) !?App {
    const Static = struct {
        var last_key_pressed = Key.unknown;
    };
    defer Static.last_key_pressed = if (key != Key.unknown) key else Static.last_key_pressed;

    // For some reason, using 'Static.last_key_pressed' directly doesn't work. It
    // compares wrongly against 'key'. If I copy it to a local variable, everything
    // does work.
    const last_key_pressed = Static.last_key_pressed;

    var editor = app.editor;
    var view = app.view;
    var text = editor.current();

    //debug.warn("{}\n", Key.toStr(key));
    switch (key) {
        reset_key => {
            text = text.removeAllButMainCursor();
        },

        help_key => view.children.help_popup.visibility = switch (view.children.help_popup.visibility) {
            .Show => draw.Visibility.Hide,
            .Hide => draw.Visibility.Show,
        },

        // Quit. If there are unsaved changes, then you have to press the quit bottons
        // twice.
        quit_key => if (editor.dirty()) switch (last_key_pressed) {
            quit_key => return null,
            else => view.children.quit_popup.visibility = .Show,
        } else {
            return null;
        },
        save_key => editor = try editor.save(),
        undo_key => {
            editor = try editor.undo();
            text = editor.current();
        },
        copy_key => try editor.copyClipboard(),
        paste_key => {
            editor = try editor.pasteClipboard();
            text = editor.current();
        },
        select_all_key => {
            // It is faster to manually delete all cursors first
            // instead of letting the editor logic merge the cursors
            // for us.
            text = text.removeAllButMainCursor();
            text = try text.moveCursors(math.maxInt(usize), .Selection, .Left);
            text = try text.moveCursors(math.maxInt(usize), .Index, .Right);
        },

        // Simple move keys. Moves all cursors start and end locations
        move_up_key => text = try text.moveCursors(1, .Both, .Up),
        move_down_key => text = try text.moveCursors(1, .Both, .Down),
        move_left_key => text = try text.moveCursors(1, .Both, .Left),
        move_right_key => text = try text.moveCursors(1, .Both, .Right),
        move_page_up_key => text = try text.moveCursors(50, .Both, .Up),
        move_page_down_key => text = try text.moveCursors(50, .Both, .Down),
        move_start_key => text = try text.moveCursors(math.maxInt(usize), .Both, .Left),
        move_end_key => text = try text.moveCursors(math.maxInt(usize), .Both, .Right),

        // Select move keys. Moves only all cursors end location
        move_select_up_key => text = try text.moveCursors(1, .Index, .Up),
        move_select_down_key => text = try text.moveCursors(1, .Index, .Down),
        move_select_left_key => text = try text.moveCursors(1, .Index, .Left),
        move_select_right_key => text = try text.moveCursors(1, .Index, .Right),

        // Spawn cursor keys
        spawn_cursor_up_key => text = try text.spawnCursor(.Up),
        spawn_cursor_down_key => text = try text.spawnCursor(.Down),
        spawn_cursor_left_key => text = try text.spawnCursor(.Left),
        spawn_cursor_right_key => text = try text.spawnCursor(.Right),

        // Delete
        delete_left_key => text = try text.delete(.Left),
        delete_right_key => text = try text.delete(.Right),

        Key.enter => text = try text.insert("\n"),

        // Every other key is inserted if they are printable ascii
        else => {
            if (ascii.isPrint(math.cast(u8, key) catch 0))
                text = try text.insert([_]u8{@intCast(u8, key)});
        },
    }
    switch (last_key_pressed) {
        // This will clear the "you have unsaved changes" msg
        quit_key => view.children.quit_popup.visibility = .Hide,
        else => {},
    }

    // Add new undo point.
    editor = try editor.addUndo(text);
    return App{
        .editor = editor,
        .view = view,
    };
}
