const std = @import("std");

const core = @import("../core.zig");

const debug = std.debug;
const heap = std.heap;
const rand = std.rand;
const time = std.time;

test "bench" {
    const str = try heap.direct_allocator.alloc(u8, 1024 * 1024 * 1024);
    defer heap.direct_allocator.free(str);
    rand.DefaultPrng.init(0).random.bytes(str);

    const text = try core.Text.Content.fromSlice(heap.direct_allocator, str);
    var timer = try time.Timer.start();

    {
        debug.warn("\nLocation.fromIndex (list)\n");
        timer.reset();
        var result: core.Location = undefined;
        @ptrCast(*volatile core.Location, &result).* = core.Location.fromIndex(str.len, text);
        const t = timer.read();
        debug.warn("{} {}\n", result.line, result.column);
        debug.warn("{}ms ({}ns)\n", t / time.millisecond, t);
    }

    {
        debug.warn("Location.fromIndex (slice)\n");
        timer.reset();

        var result = core.Location{};
        for (str) |c, i| {
            if (str.len == i)
                break;
            if (c == '\n') {
                result.line += 1;
                result.index = i + 1;
            }
        }
        result.column = str.len - result.index;
        result.index = str.len;
        @ptrCast(*volatile core.Location, &result).* = result;
        const t = timer.read();
        debug.warn("{} {}\n", result.line, result.column);
        debug.warn("{}ms ({}ns)\n", t / time.millisecond, t);
    }

    {
        debug.warn("Count items (list)\n");
        timer.reset();
        var c: usize = 0;
        try text.foreach(0, &c, struct {
            fn each(count: *usize, i: usize, item: u8) error{}!void {
                count.* += 1;
            }
        }.each);
        @ptrCast(*volatile usize, &c).* = c;
        const t = timer.read();
        debug.warn("{}ms ({}ns)\n", t / time.millisecond, t);
    }

    {
        debug.warn("Count items (list)\n");
        timer.reset();
        var count: usize = 0;
        for (str) |c, i| {
            count += 1;
        }
        @ptrCast(*volatile usize, &count).* = count;
        const t = timer.read();
        debug.warn("{}ms ({}ns)\n", t / time.millisecond, t);
    }
}
