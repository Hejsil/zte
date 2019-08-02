pub const clipboard = @import("core/clipboard.zig");
const editor = @import("core/editor.zig");
const list = @import("core/list.zig");
const text = @import("core/text.zig");

pub const Cursor = text.Cursor;
pub const CustomList = list.CustomList;
pub const Editor = editor.Editor;
pub const List = list.List;
pub const Location = text.Location;
pub const NoAllocatorCustomList = list.NoAllocatorCustomList;
pub const NoAllocatorList = list.NoAllocatorList;
pub const Text = text.Text;

test "" {
    _ = clipboard;
    _ = editor;
    _ = list;
    _ = text;

    _ = @import("core/list_tests.zig");
    _ = @import("core/text_tests.zig");
}
