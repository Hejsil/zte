const std = @import("std");

const core = @import("../core.zig");

const debug = std.debug;
const fs = std.fs;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

pub const History = core.List(core.Text);

pub const File = struct {
    path: []const u8,
    stat: os.Stat,
};

pub const Editor = struct {
    history: History,
    history_pos: usize = 0,
    on_disk_pos: usize = 0,
    copy_pos: usize = 0,
    file: ?File = null,

    pub fn fromString(allocator: *mem.Allocator, str: []const u8) !Editor {
        var res = Editor{ .history = History{ .allocator = allocator } };
        const t = try core.Text.fromString(allocator, str);
        res.history = try res.history.append(t);
        return res;
    }

    pub fn fromFile(allocator: *mem.Allocator, path: []const u8) !Editor {
        const file = try fs.File.openRead(path);
        defer file.close();

        const stat = try os.fstat(file.handle);
        var res = if (stat.size == 0)
            try Editor.fromString(allocator, "")
        else blk: {
            const content = try os.mmap(null, @intCast(usize, stat.size), os.PROT_READ, os.MAP_PRIVATE, file.handle, 0);
            defer os.munmap(content);
            break :blk try Editor.fromString(allocator, content);
        };
        res.file = File{
            .path = path,
            .stat = stat,
        };

        return res;
    }

    pub fn save(editor: Editor) !Editor {
        if (!editor.dirty())
            return editor;

        const editor_file = editor.file orelse return error.NoFile;
        const file = try fs.File.openWrite(editor_file.path);
        defer file.close();

        const curr = editor.current();
        const out_stream = &file.outStream().stream;
        var buf_out_stream = io.BufferedOutStream(fs.File.WriteError).init(out_stream);
        try curr.content.foreach(0, &buf_out_stream.stream, struct {
            fn each(stream: *io.OutStream(fs.File.WriteError), i: usize, item: u8) !void {
                try stream.writeByte(item);
            }
        }.each);
        try buf_out_stream.flush();

        var res = editor;
        res.on_disk_pos = res.history_pos;
        return res;
    }

    pub fn addUndo(editor: Editor, t: core.Text) !Editor {
        if (t.equal(editor.current()))
            return editor;

        var res = editor;
        debug.assert(res.history_pos < res.history.len());
        res.history_pos = res.history.len();
        res.history = try res.history.append(t);
        return res;
    }

    pub fn current(editor: Editor) core.Text {
        return editor.history.at(editor.history_pos);
    }

    pub fn onDisk(editor: Editor) core.Text {
        return editor.history.at(editor.on_disk_pos);
    }

    pub fn copied(editor: Editor) core.Text {
        return editor.history.at(editor.copy_pos);
    }

    pub fn undo(editor: Editor) !Editor {
        const curr = editor.current();
        var res = editor;
        while (res.history_pos != 0) {
            res.history_pos -= 1;
            const prev = res.current();
            if (!curr.content.equal(prev.content))
                break;
        }

        res.history = try res.history.append(res.current());
        return res;
    }

    pub fn dirty(editor: Editor) bool {
        return !core.Text.Content.equal(editor.onDisk().content, editor.current().content);
    }

    pub fn copy(editor: Editor) Editor {
        var res = editor;
        res.copy_pos = res.history_pos;
        return res;
    }
};
