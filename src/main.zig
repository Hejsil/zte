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
const mem = std.mem;
const process = std.process;

const Editor = core.Editor;
const Key = input.Key;

var keys_pressed: std.ArrayList(Key.Type) = undefined;

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

    for (keys_pressed.toSlice()) |key|
        debug.warn("{s}\n", ([*]const u8)(&Key.toStr(key, .NotCtrl)));

    const first_trace_addr = @returnAddress();
    std.debug.panicExtra(error_return_trace, first_trace_addr, "{}", msg);
}

const modified_view = draw.visible(.Hide, draw.label(.Left, "(modified) "));
const file_name_view = draw.stack(.Horizontal, struct {
    modified: @typeOf(modified_view) = modified_view,
    file_name: draw.Label = draw.label(.Left, ""),
}{});

const info_view = draw.right(draw.value("", struct {
    hint: []const u8 = default_hint,
    key: Key.Type = Key.space,
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
            "{}{} ('{s}') ({},{}) (t:{B:2} a:{B:2} f:{B:2})",
            if (self.hint.len != 0) " " else "",
            self.hint,
            ([*]const u8)(&Key.toStr(self.key, .NotCtrl)),
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

const goto_prompt_bar = draw.visible(.Hide, draw.attributes(.Negative, draw.customRange(draw.Range{
    .min = draw.Size{ .width = 0, .height = 1 },
    .max = draw.Size{ .width = math.maxInt(usize), .height = 1 },
}, draw.stack(.Horizontal, struct {
    label: draw.Label = draw.label(.Left, "goto: "),
    text: draw.TextView = draw.textView(false, core.Text{ .allocator = undefined }), // We init this in main
}{}))));

const editor_view = draw.stack(.Vertical, struct {
    text: draw.TextView = draw.textView(true, core.Text{ .allocator = undefined }), // We init this in main
    goto_prompt_bar: @typeOf(goto_prompt_bar) = goto_prompt_bar,
    status_bar: @typeOf(status_bar) = status_bar,
}{});

const help_popup = blk: {
    @setEvalBranchQuota(10000);
    break :blk draw.visible(.Hide, draw.center(draw.clear(draw.attributes(.Negative, draw.box(draw.label(
        .Left,
        "'" ++ mem.toSliceConst(u8, &Key.toStr(quit_key, .NotCtrl)) ++ "': quit\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(save_key, .NotCtrl)) ++ "': save\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(undo_key, .NotCtrl)) ++ "': undo\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(copy_key, .NotCtrl)) ++ "': copy\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(paste_key, .NotCtrl)) ++ "': paste\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(select_all_key, .NotCtrl)) ++ "': select all\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(jump_key, .NotCtrl)) ++ "': jump to line\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(help_key, .CtrlAlphaNum)) ++ "': hide or show this message\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(reset_key, .NotCtrl)) ++ "': general key to cancel/reset/stop the current action\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(delete_left_key, .NotCtrl)) ++ "': delete letter to the left of cursors\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(delete_right_key, .NotCtrl)) ++ "': delete letter to the right of cursors\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_page_up_key, .NotCtrl)) ++ "': move cursors up one screen\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_page_down_key, .NotCtrl)) ++ "': move cursors down one screen\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_start_key, .NotCtrl)) ++ "': move cursors to start of file\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_end_key, .NotCtrl)) ++ "': move cursors to end of file\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_up_key, .NotCtrl)) ++ "': move cursors up\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_down_key, .NotCtrl)) ++ "': move cursors down\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_left_key, .NotCtrl)) ++ "': move cursors left\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_right_key, .NotCtrl)) ++ "': move cursors right\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_select_up_key, .NotCtrl)) ++ "': move selections up\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_select_down_key, .NotCtrl)) ++ "': move selections down\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_select_left_key, .NotCtrl)) ++ "': move selections left\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(move_select_right_key, .NotCtrl)) ++ "': move selections right\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(spawn_cursor_up_key, .NotCtrl)) ++ "': spawn a cursor above the main cursor\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(spawn_cursor_down_key, .NotCtrl)) ++ "': spawn a cursor below the main cursor\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(spawn_cursor_left_key, .NotCtrl)) ++ "': spawn a cursor to the left of the main cursor\n" ++
            "'" ++ mem.toSliceConst(u8, &Key.toStr(spawn_cursor_right_key, .NotCtrl)) ++ "': spawn a cursor to the right of the main cursor",
    ))))));
};

const quit_popup = blk: {
    @setEvalBranchQuota(10000);
    break :blk draw.visible(.Hide, draw.center(draw.clear(draw.attributes(.Negative, draw.box(draw.label(
        .Center,
        "Warning!\n" ++
            "You have unsaved changes.\n" ++
            "Press '" ++ mem.toSliceConst(u8, &Key.toStr(quit_key, .NotCtrl)) ++ "' to forcefully quit",
    ))))));
};

const window_view = draw.float(struct {
    editor: @typeOf(editor_view) = editor_view,
    help_popup: @typeOf(help_popup) = help_popup,
    quit_popup: @typeOf(quit_popup) = quit_popup,
}{});

pub fn main() !void {
    var failing = debug.FailingAllocator.init(heap.direct_allocator, math.maxInt(usize));
    var arena = heap.ArenaAllocator.init(&failing.allocator);
    const allocator = &arena.allocator;

    const stdin = try io.getStdIn();
    const stdout = try io.getStdOut();
    const stdout_stream = &stdout.outStream().stream;
    var stdout_buf = io.BufferedOutStreamCustom(std.mem.page_size * 40, fs.File.WriteError).init(stdout_stream);

    const args = try process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len <= 1)
        return error.NoFileFound;

    keys_pressed = std.ArrayList(Key.Type).init(allocator);
    var app = App{
        .editor = try Editor.fromFile(allocator, args[1]),
        .view = window_view,
    };
    app.view.children.editor.children.goto_prompt_bar.child.child.child.children.text = draw.textView(false, try core.Text.fromString(allocator, ""));

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
            draw.label(.Left, file.path)
        else
            draw.label(.Left, "???");

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
        try keys_pressed.append(key);
        info.key = key;
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

const reset_key = Key.escape;

const help_key = Key.alt | Key.ctrl_h;
const quit_key = Key.ctrl_q;
const save_key = Key.ctrl_s;
const undo_key = Key.ctrl_z;
const copy_key = Key.ctrl_c;
const paste_key = Key.ctrl_v;
const select_all_key = Key.ctrl_a;
const jump_key = Key.ctrl_j;

const delete_left_key = Key.backspace;
const delete_left2_key = Key.backspace2;
const delete_right_key = Key.delete;

const move_page_up_key = Key.page_up;
const move_page_down_key = Key.page_down;
const move_start_key = Key.home;
const move_end_key = Key.end;

const move_up_key = Key.arrow_up;
const move_down_key = Key.arrow_down;
const move_left_key = Key.arrow_left;
const move_right_key = Key.arrow_right;
const move_select_up_key = Key.shift_arrow_up;
const move_select_down_key = Key.shift_arrow_down;
const move_select_left_key = Key.shift_arrow_left;
const move_select_right_key = Key.shift_arrow_right;
const spawn_cursor_up_key = Key.ctrl_arrow_up;
const spawn_cursor_down_key = Key.ctrl_arrow_down;
const spawn_cursor_left_key = Key.ctrl_arrow_left;
const spawn_cursor_right_key = Key.ctrl_arrow_right;

const default_hint = "'" ++ mem.toSliceConst(u8, &Key.toStr(help_key, .CtrlAlphaNum)) ++ "' for help";

fn handleInput(app: App, key: Key.Type) !?App {
    var editor = app.editor;
    var view = app.view;
    var text = editor.current();

    if (view.children.editor.children.goto_prompt_bar.visibility == .Show) {
        const prompt = &view.children.editor.children.goto_prompt_bar;
        const prompt_text = &prompt.child.child.child.children.text.text;
        switch (key) {
            Key.enter, jump_key, reset_key => {
                prompt.visibility = .Hide;
                prompt_text.* = try core.Text.fromString(prompt_text.allocator, "");
            },

            select_all_key => {
                prompt_text.* = try prompt_text.moveCursors(math.maxInt(usize), .Selection, .Left);
                prompt_text.* = try prompt_text.moveCursors(math.maxInt(usize), .Index, .Right);
            },

            // Simple move keys. Moves all cursors start and end locations
            move_left_key => prompt_text.* = try prompt_text.moveCursors(1, .Both, .Left),
            move_right_key => prompt_text.* = try prompt_text.moveCursors(1, .Both, .Right),

            // Select move keys. Moves only all cursors end location
            move_select_left_key => prompt_text.* = try prompt_text.*.moveCursors(1, .Index, .Left),
            move_select_right_key => prompt_text.* = try prompt_text.*.moveCursors(1, .Index, .Right),

            // Delete
            delete_left_key, delete_left2_key => prompt_text.* = try prompt_text.delete(.Left),
            delete_right_key => prompt_text.* = try prompt_text.delete(.Right),

            else => {
                if (ascii.isDigit(math.cast(u8, key) catch 0))
                    prompt_text.* = try prompt_text.insert([_]u8{@intCast(u8, key)});
            },
        }

        if (prompt_text.content.len() != 0) {
            var buf: [128]u8 = undefined;
            var fba = heap.FixedBufferAllocator.init(&buf);
            const line = if (prompt_text.content.toSlice(&fba.allocator)) |line|
                std.fmt.parseUnsigned(usize, line, 10) catch math.maxInt(usize)
            else |_|
                math.maxInt(usize);

            var cursor = text.mainCursor();
            cursor.index = cursor.index.moveToLine(math.sub(usize, line, 1) catch 0, text.content);
            cursor.selection = cursor.index;
            text.cursors = core.Text.Cursors.fromSliceSmall([_]core.Cursor{cursor});
        }

        // Add new undo point.
        editor = try editor.addUndo(text);
        return App{
            .editor = editor,
            .view = view,
        };
    }

    // clear then "You have unsaved changes popup
    const quit_popup_is_show = view.children.quit_popup.visibility;
    view.children.quit_popup.visibility = .Hide;

    //debug.warn("{}\n", Key.toStr(key));
    switch (key) {
        reset_key => {
            text = text.removeAllButMainCursor();
            view.children.help_popup.visibility = .Hide;
        },

        help_key => view.children.help_popup.visibility = switch (view.children.help_popup.visibility) {
            .Show => draw.Visibility.Hide,
            .Hide => draw.Visibility.Show,
        },

        // Quit. If there are unsaved changes, then you have to press the quit bottons
        // twice.
        quit_key => if (editor.dirty() and quit_popup_is_show != .Show) {
            view.children.quit_popup.visibility = .Show;
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
        delete_left_key, delete_left2_key => text = try text.delete(.Left),
        delete_right_key => text = try text.delete(.Right),

        jump_key => view.children.editor.children.goto_prompt_bar.visibility = .Show,

        Key.enter => text = try text.insert("\n"),
        Key.space => text = try text.insert(" "),
        Key.tab => text = try text.indent(' ', 4),

        // Every other key is inserted if they are printable ascii
        else => {
            if (ascii.isPrint(math.cast(u8, key) catch 0))
                text = try text.insert([_]u8{@intCast(u8, key)});
        },
    }

    // Add new undo point.
    editor = try editor.addUndo(text);
    return App{
        .editor = editor,
        .view = view,
    };
}
