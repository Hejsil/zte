const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

const CustomList = @import("list.zig").CustomList;
const List = @import("list.zig").List;

test "List.foreach" {
    var buf: [1024 * 1024 * 5]u8 = undefined;
    const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;

    const l = try List(u8).fromSlice(allocator, "a" ** (1024 * 4));
    var i: usize = 0;
    while (i < l.len()) : (i += 1) {
        var j: usize = i;
        l.foreach(i, &j, struct {
            fn each(expect_i: *usize, actual_i: usize, c: u8) error{}!void {
                testing.expectEqual(expect_i.*, actual_i);
                testing.expectEqual(u8('a'), c);
                expect_i.* += 1;
            }
        }.each) catch {};
        testing.expectEqual(l.len(), j);
    }
}

test "fuzz case 3-128-2-580" {
    var buf: [1024 * 1024 * 5]u8 = undefined;
    const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
    var l = CustomList(u8, 3){ .allocator = allocator };
    var cmp = std.ArrayList(u8).init(allocator);

    l = try CustomList(u8, 3).fromSlice(allocator, "dvtusjjmqsiojhglereivjnhkdvyeqdjtcutufsezllzjrmupifivylniljdjyfioyboualnynwiygddjgtfpkod");
    try cmp.resize(0);
    try cmp.appendSlice("dvtusjjmqsiojhglereivjnhkdvyeqdjtcutufsezllzjrmupifivylniljdjyfioyboualnynwiygddjgtfpkod");
    try testList(l, cmp.toSlice());

    l = try l.insertSlice(17, "wvcgqeluuybbenuiunnnrcdyvoqrmdinfwffgyryebafzauyzpwwlzuoirkxlyjqboyvtkbehondfnqhzdrsrhqfexyindwoop");
    try cmp.insertSlice(17, "wvcgqeluuybbenuiunnnrcdyvoqrmdinfwffgyryebafzauyzpwwlzuoirkxlyjqboyvtkbehondfnqhzdrsrhqfexyindwoop");
    try testList(l, cmp.toSlice());
}

test "fuzz case 4-128-2-6313103345818793189" {
    var buf: [1024 * 1024 * 5]u8 = undefined;
    const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
    var l = CustomList(u8, 4){ .allocator = allocator };
    var cmp = std.ArrayList(u8).init(allocator);

    l = try CustomList(u8, 4).fromSlice(allocator, "wpwuuywcknijpuashmysojxckpleqgzjxyyqmzpmcpslwfuhmkiiicqmmzyupovmcnrticlqdwhgpvvjmjwfywokzqlmdsluhgdciylwbvpvuihvqwfixazxaialrp");
    try cmp.resize(0);
    try cmp.appendSlice("wpwuuywcknijpuashmysojxckpleqgzjxyyqmzpmcpslwfuhmkiiicqmmzyupovmcnrticlqdwhgpvvjmjwfywokzqlmdsluhgdciylwbvpvuihvqwfixazxaialrp");
    try testList(l, cmp.toSlice());

    l = try l.slice(101, 116);
    try cmp.appendSlice(cmp.toOwnedSlice()[101..116]);
    try testList(l, cmp.toSlice());
}

test "fuzz case 32-512-2-16721983880728474569" {
    var buf: [1024 * 1024 * 5]u8 = undefined;
    const allocator = &heap.FixedBufferAllocator.init(&buf).allocator;
    var l = CustomList(u8, 32){ .allocator = allocator };
    var cmp = std.ArrayList(u8).init(allocator);

    l = try CustomList(u8, 32).fromSlice(allocator, "szhvnwlwqlnnuhfzwmlgfrkgurzkvgzvkeddllruiclgelctkrxkdwkesiziqlixizgzymqziywesgynboiebfuichbgrsbalhiusqfijxrynbbrbnhnldgiqcxhaorlumiwfnyafcbtxegkcmpjtogfrjwaieiilfwnttrxecrxjfwfsugityqermenmrhfksbhkczpuynsyxxpstucjssktpeucceirjpqkkyczjorrhjhdocjqlxxdmcedekajxvspnmebeqxrpeqxrpiwtkaiafsylmzadlpswfrfvhxxrrkcrkjvnesnttukzeptcwwzywordolcgcnugexvlpsqbzdhilkfbzmnjwpldrfgsyqruxvkiodoqjwixscchabydtkpydhkxokuoxaaypscvhhphwnktvgpzmaskcazinmdbuloxfiymzxpwvndctgcjs");
    try cmp.resize(0);
    try cmp.appendSlice("szhvnwlwqlnnuhfzwmlgfrkgurzkvgzvkeddllruiclgelctkrxkdwkesiziqlixizgzymqziywesgynboiebfuichbgrsbalhiusqfijxrynbbrbnhnldgiqcxhaorlumiwfnyafcbtxegkcmpjtogfrjwaieiilfwnttrxecrxjfwfsugityqermenmrhfksbhkczpuynsyxxpstucjssktpeucceirjpqkkyczjorrhjhdocjqlxxdmcedekajxvspnmebeqxrpeqxrpiwtkaiafsylmzadlpswfrfvhxxrrkcrkjvnesnttukzeptcwwzywordolcgcnugexvlpsqbzdhilkfbzmnjwpldrfgsyqruxvkiodoqjwixscchabydtkpydhkxokuoxaaypscvhhphwnktvgpzmaskcazinmdbuloxfiymzxpwvndctgcjs");
    try testList(l, cmp.toSlice());

    l = try l.insertSlice(319, "xaafnronuwliclcbhwxfdqrrqefpgpmucbekimsiifchwynisfyyeueviedskhikojgsdseksrqooxwgwsmcjrojbpvqdpfvxovrhdmsrivopiqvmwxapbxdehiusoeivfqvyzjgrtcodeaxdygawenicgtzyrsxjzpzlefjdzdzsxxywelizqsryopwwyxsubonhumksihfacgqkzvpjdfhwdglpjevsaglcpxoumehtgwzwpfdpvhstlcodbkvekbxquvawokvycunsibglvczciauvowxkqkgtxpnkaxqxyxrsjvixkceuyitabaqgcwpoawagvqqiousoangktrzaordjzjevvkteqsesmrdhyvdqqxhdhunfqwyhgnqxakenymftnquphfekqtylsdakwmxwwsyxlmnmtqzkcqcufcjiwlsroeuketqysqspcedimrkhimtsbmauzajxcoqdovee");
    try cmp.insertSlice(319, "xaafnronuwliclcbhwxfdqrrqefpgpmucbekimsiifchwynisfyyeueviedskhikojgsdseksrqooxwgwsmcjrojbpvqdpfvxovrhdmsrivopiqvmwxapbxdehiusoeivfqvyzjgrtcodeaxdygawenicgtzyrsxjzpzlefjdzdzsxxywelizqsryopwwyxsubonhumksihfacgqkzvpjdfhwdglpjevsaglcpxoumehtgwzwpfdpvhstlcodbkvekbxquvawokvycunsibglvczciauvowxkqkgtxpnkaxqxyxrsjvixkceuyitabaqgcwpoawagvqqiousoangktrzaordjzjevvkteqsesmrdhyvdqqxhdhunfqwyhgnqxakenymftnquphfekqtylsdakwmxwwsyxlmnmtqzkcqcufcjiwlsroeuketqysqspcedimrkhimtsbmauzajxcoqdovee");
    try testList(l, cmp.toSlice());
}

pub fn testList(list: var, expect: []const u8) !void {
    const other = @typeOf(list).fromSlice(list.allocator, expect) catch unreachable;
    var it = list.iterator(0);
    try list.foreach(0, expect, struct {
        fn t(e: []const u8, i: usize, item: u8) !void {
            if (e[i] != item)
                return error.TestFailed;
        }
    }.t);
    for (expect) |c, i| {
        if (list.at(i) != c)
            return error.TestFailed;
        const item = it.next() orelse return error.TestFailed;
        if (item != c)
            return error.TestFailed;
    }
    if (it.next() != null)
        return error.TestFailed;
    if (!list.equal(other))
        return error.TestFailed;
}
