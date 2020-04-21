const std = @import("std");

const list_tests = @import("list_tests.zig");

const heap = std.heap;
const mem = std.mem;

const CustomList = @import("list.zig").CustomList;

const testList = list_tests.testList;

// How to fuzz 101:
// You have made changes to the list and want to fuzz it? Firstm run the
// fuzzer in release-safe mode:
// `zig test src/imut_test.zig --release-safe`
//
// We run in release fast, because fuzzing will take a while otherwise. If
// If this test pass, then you've made changes without breaking the list
// implementation.
// If a failure occured, you have a couple of options depending on the
// failure.
//
// # The test failed
// If the fuzz test failed, then it should automatically print the test
// case that broke. Just copy that test case into "list_testsz.zig",
// ensure that is passes and then run the fuzzer again.
//
// # Segfault or other unexpected exits
// If the implementation segfaults, then a test case wont be printed
// automatically. You'll have to play around with some of the option
// varibles in the fuzz test itself.
// * If it crases imidiatly, then you can set `print_only_on_failure` to
//   `false`. This will make the fuzzer print all test cases during execution.
//   Just wait for it to finish and copy up to the start of the last test
//   block into this file (the test cases might not have been printed
//   completely. Just fix any syntax errors when you paste). If your terminal
//   emulator prints test cases two slowly, consider piping the test
//   cases to a file (`zig test src/imut_test.zig --release-fast >dump`)
// * If crashing takes a while, then printing all test cases won't be an
//   option. In this case, try ajusting `fuzz_iterations`, `node_sizes`,
//   `max_slice_sizes` and `max_actions` to be smaller, so that you can
//   hit your failing test case faster. You can also try setting
//   `print_params` to `true`. This will only print the parameters passed
//   to the `fuzz` funtion. When you then hit you test case, just
//   go back, and run `fuzz` only with the parameters printed last.
test "fuzz" {
    // Set this to false and each fuzz test will be printed to stdout
    // regardless of wether the test passed or not. This is useful when
    // a test case segfaults.
    const print_only_on_failure = true;

    // This will print the parameters sent to fuzz
    const print_params = false;

    // The number of fuzz tests to be run for each configurations.
    // Each iteration is its own seed.
    const fuzz_iterations = 25;

    // The node sizes to test
    const node_sizes = [_]usize{ 2, 3, 4, 8, 16, 32, 64, 128 };

    // The maximum size of slices generated during fuzzing
    const max_slice_sizes = [_]usize{ 2, 8, 32, 128, 512, 2048, 4096 * 2 };

    // The maximum number of actions generated
    const max_actions = [_]usize{ 2, 4, 8, 16, 32, 64, 128 };

    const seeder = &std.rand.DefaultPrng.init(0).random;

    const alloc_buf = try heap.direct_allocator.alloc(u8, 1024 * 1024 * 512);
    defer heap.direct_allocator.free(alloc_buf);

    var buf: [1024 * 1024 * 2]u8 = undefined;
    const stdout = try std.io.getStdOut();

    for (max_actions) |max_act| {
        for (max_slice_sizes) |max_slice_size| {
            inline for (node_sizes) |node_size| {
                var fuzz_i: usize = 0;
                while (fuzz_i < fuzz_iterations) : (fuzz_i += 1) {
                    const allocator = &heap.FixedBufferAllocator.init(alloc_buf).allocator;
                    var sos = std.io.SliceOutStream.init(&buf);

                    const stream = if (print_only_on_failure) &sos.stream else &stdout.outStream().stream;
                    const seed = seeder.int(usize);
                    if (print_params)
                        debug.warn("{} {} {} {}\n", node_size, max_slice_size, max_act, seed);

                    fuzz(allocator, node_size, max_slice_size, max_act, seed, stream) catch |err| {
                        try stdout.write("\n");
                        try stdout.write(sos.getWritten());
                        return err;
                    };
                }
            }
        }
    }
}

const Action = union(enum) {
    FromSlice: []const u8,
    Append: u8,
    AppendSlice: []const u8,
    AppendList,
    Insert: Insert,
    InsertSlice: InsertSlice,
    //InsertList: usize,
    Remove: usize,
    RemoveItems: RemoveItems,
    Slice: Slice,

    const Insert = struct {
        index: usize,
        item: u8,
    };

    const InsertSlice = struct {
        index: usize,
        items: []const u8,
    };

    const RemoveItems = struct {
        i: usize,
        len: usize,
    };

    const Slice = struct {
        start: usize,
        end: usize,
    };
};

fn randSlice(allocator: *mem.Allocator, max: usize, rand: *std.rand.Random) ![]const u8 {
    const len = rand.uintLessThanBiased(usize, max + 1);
    const res = try allocator.alloc(u8, len);
    for (res) |*item| {
        item.* = rand.intRangeLessThanBiased(u8, 'a', 'z' + 1);
    }

    return res;
}

fn createActions(allocator: *mem.Allocator, max_slice_size: usize, max_actions: usize, seed: usize) ![]const Action {
    const rand = &std.rand.DefaultPrng.init(seed).random;
    const len = rand.intRangeLessThanBiased(usize, 1, max_actions + 1);
    const res = try allocator.alloc(Action, len);
    var curr_len: usize = 0;
    for (res) |*action| {
        try_again: while (true) {
            const Enum = @TagType(Action);
            const Tag = @TagType(Enum);
            const enum_info = @typeInfo(Enum);
            const kind_int = rand.uintLessThanBiased(usize, enum_info.Enum.fields.len);
            switch (@intToEnum(Enum, @intCast(Tag, kind_int))) {
                .FromSlice => {
                    const items = try randSlice(allocator, max_slice_size, rand);
                    action.* = Action{
                        .FromSlice = items,
                    };
                    curr_len = items.len;
                },
                .Append => {
                    action.* = Action{
                        .Append = rand.intRangeLessThanBiased(u8, 'a', 'z' + 1),
                    };
                    curr_len += 1;
                },
                .AppendSlice => {
                    const items = try randSlice(allocator, max_slice_size, rand);
                    action.* = Action{
                        .AppendSlice = items,
                    };
                    curr_len += items.len;
                },
                .AppendList => {
                    action.* = Action.AppendList;
                    curr_len += curr_len;
                },
                .Insert => {
                    action.* = Action{
                        .Insert = Action.Insert{
                            .index = rand.uintLessThanBiased(usize, curr_len + 1),
                            .item = rand.intRangeLessThanBiased(u8, 'a', 'z' + 1),
                        },
                    };
                    curr_len += 1;
                },
                .InsertSlice => {
                    const items = try randSlice(allocator, max_slice_size, rand);
                    action.* = Action{
                        .InsertSlice = Action.InsertSlice{
                            .index = rand.uintLessThanBiased(usize, curr_len + 1),
                            .items = items,
                        },
                    };
                    curr_len += items.len;
                },
                //.InsertList => {
                //    action.* = Action{
                //        .InsertList = rand.uintLessThanBiased(usize, curr_len + 1),
                //    };
                //    curr_len += curr_len;
                //},
                .Remove => {
                    if (curr_len == 0)
                        continue :try_again;
                    action.* = Action{
                        .Remove = rand.uintLessThanBiased(usize, curr_len),
                    };
                    curr_len -= 1;
                },
                .RemoveItems => {
                    if (curr_len == 0)
                        continue :try_again;

                    const i = rand.uintLessThanBiased(usize, curr_len);
                    const l = rand.intRangeLessThanBiased(usize, i, curr_len + 1) - i;
                    action.* = Action{
                        .RemoveItems = Action.RemoveItems{
                            .i = i,
                            .len = l,
                        },
                    };
                    curr_len -= l;
                },
                .Slice => {
                    const start = rand.uintLessThanBiased(usize, curr_len + 1);
                    const end = rand.intRangeLessThanBiased(usize, start, curr_len + 1);
                    action.* = Action{
                        .Slice = Action.Slice{
                            .start = start,
                            .end = end,
                        },
                    };
                    curr_len = end - start;
                },
            }
            break;
        }
    }

    return res;
}

fn fuzz(allocator: *mem.Allocator, comptime node_size: usize, max_slice_size: usize, max_actions: usize, seed: usize, stream: var) !void {
    const actions = try createActions(allocator, max_slice_size, max_actions, seed);
    var l = CustomList(u8, node_size){ .allocator = allocator };
    var cmp = std.ArrayList(u8).init(allocator);

    try stream.print("test \"fuzz case {}-{}-{}-{}\" {{\n", node_size, max_slice_size, max_actions, seed);
    defer stream.print("}}\n\n") catch {};

    try stream.print("    var buf: [1024 * 1024 * 5]u8 = undefined;\n");
    try stream.print("    const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;\n");
    try stream.print("    var l = CustomList(u8, {}){{ .allocator = allocator }};\n", node_size);
    try stream.print("    var cmp = std.ArrayList(u8).init(allocator);\n\n");
    for (actions) |action| {
        switch (action) {
            .FromSlice => |items| {
                try stream.print("    l = try CustomList(u8, {}).fromSlice(allocator, \"{}\");\n", node_size, items);
                try stream.print("    try cmp.resize(0);\n");
                try stream.print("    try cmp.appendSlice(\"{}\");\n", items);
                l = try CustomList(u8, node_size).fromSlice(allocator, items);
                try cmp.resize(0);
                try cmp.appendSlice(items);
            },
            .Append => |item| {
                try stream.print("    l = try l.append('{c}');\n", item);
                try stream.print("    try cmp.append('{c}');\n", item);
                l = try l.append(item);
                try cmp.append(item);
            },
            .AppendSlice => |items| {
                try stream.print("    l = try l.appendSlice(\"{}\");\n", items);
                try stream.print("    try cmp.appendSlice(\"{}\");\n", items);
                l = try l.appendSlice(items);
                try cmp.appendSlice(items);
            },
            .AppendList => {
                try stream.print("    l = try l.appendList(l);\n");
                try stream.print("    try cmp.appendSlice(cmp.items);\n");
                l = try l.appendList(l);
                try cmp.appendSlice(cmp.items);
            },
            .Insert => |insert| {
                try stream.print("    l = try l.insert({}, '{c}');\n", insert.index, insert.item);
                try stream.print("    try cmp.insert({}, '{c}');\n", insert.index, insert.item);
                l = try l.insert(insert.index, insert.item);
                try cmp.insert(insert.index, insert.item);
            },
            .InsertSlice => |insert| {
                try stream.print("    l = try l.insertSlice({}, \"{}\");\n", insert.index, insert.items);
                try stream.print("    try cmp.insertSlice({}, \"{}\");\n", insert.index, insert.items);
                l = try l.insertSlice(insert.index, insert.items);
                try cmp.insertSlice(insert.index, insert.items);
            },
            //.InsertList => |index| {
            //    l = try l.insertList(index, l);
            //    try cmp.insertSlice(index, cmp.items);
            //},
            .Remove => |remove| {
                try stream.print("    l = try l.remove({});\n", remove);
                try stream.print("    _ = cmp.orderedRemove({});\n", remove);
                l = try l.remove(remove);
                _ = cmp.orderedRemove(remove);
            },
            .RemoveItems => |remove| {
                try stream.print("    l = try l.removeItems({}, {});\n", remove.i, remove.len);
                try stream.print("    {{");
                try stream.print("        const slice = cmp.toOwnedSlice();");
                try stream.print("        const first = slice[0..{}];", remove.i);
                try stream.print("        const last = slice[{}..];", remove.i + remove.len);
                try stream.print("        try cmp.appendSlice(first);");
                try stream.print("        try cmp.appendSlice(last);");
                try stream.print("    }}");

                l = try l.removeItems(remove.i, remove.len);
                const slice = cmp.toOwnedSlice();
                const first = slice[0..remove.i];
                const last = slice[remove.i + remove.len ..];
                try cmp.appendSlice(first);
                try cmp.appendSlice(last);
            },
            .Slice => |slice| {
                try stream.print("    l = try l.slice({}, {});\n", slice.start, slice.end);
                try stream.print("    try cmp.appendSlice(cmp.toOwnedSlice()[{}..{}]);\n", slice.start, slice.end);
                l = try l.slice(slice.start, slice.end);
                try cmp.appendSlice(cmp.toOwnedSlice()[slice.start..slice.end]);
            },
        }

        try stream.print("    try testList(l, cmp.items);\n\n");
        try testList(l, cmp.items);
    }
}
