const std = @import("std");

const debug = std.debug;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

pub fn defaultLeafSize(comptime T: type) comptime_int {
    return math.max(1, 256 / @sizeOf(T));
}

pub fn List(comptime T: type) type {
    return CustomList(T, defaultLeafSize(T));
}

pub fn CustomList(comptime T: type, comptime leaf_size: comptime_int) type {
    return struct {
        pub const Iterator = L.Iterator;
        pub const BlockIterator = L.BlockIterator;
        const L = NoAllocatorCustomList(T, leaf_size);
        list: L = L{},
        allocator: *mem.Allocator,

        pub fn fromSlice(allocator: *mem.Allocator, items: []const T) !@This() {
            return @This(){
                .list = try L.fromSlice(allocator, items),
                .allocator = allocator,
            };
        }

        pub fn fromSliceSmall(allocator: *mem.Allocator, items: []const T) @This() {
            return @This(){
                .list = L.fromSliceSmall(items),
                .allocator = allocator,
            };
        }

        pub fn len(list: @This()) usize {
            return list.list.len();
        }

        pub fn iterator(list: *const @This(), start: usize) Iterator {
            return list.list.iterator(start);
        }

        pub fn blockIterator(list: *const @This(), start: usize) BlockIterator {
            return list.list.blockIterator(start);
        }

        pub fn foreach(list: @This(), start: usize, context: var, func: var) @TypeOf(func).ReturnType {
            return list.list.foreach(start, context, func);
        }

        pub fn at(list: @This(), i: usize) T {
            return list.list.at(i);
        }

        pub fn append(list: @This(), item: T) !@This() {
            return @This(){
                .list = try list.list.append(list.allocator, item),
                .allocator = list.allocator,
            };
        }

        pub fn appendMut(list: *@This(), item: T) !void {
            try list.list.appendMut(list.allocator, item);
        }

        pub fn appendSlice(list: @This(), items: []const T) !@This() {
            return @This(){
                .list = try list.list.appendSlice(list.allocator, items),
                .allocator = list.allocator,
            };
        }

        pub fn appendSliceMut(list: *@This(), items: []const T) !void {
            try list.list.appendSliceMut(list.allocator, items);
        }

        pub fn appendList(list: @This(), other: @This()) !@This() {
            return @This(){
                .list = try list.list.appendList(list.allocator, other.list),
                .allocator = list.allocator,
            };
        }

        pub fn insert(list: @This(), i: usize, item: T) !@This() {
            return @This(){
                .list = try list.list.insert(list.allocator, i, item),
                .allocator = list.allocator,
            };
        }

        pub fn insertSlice(list: @This(), i: usize, items: []const T) !@This() {
            return @This(){
                .list = try list.list.insertSlice(list.allocator, i, items),
                .allocator = list.allocator,
            };
        }

        pub fn insertList(list: @This(), i: usize, other: @This()) !@This() {
            return @This(){
                .list = try list.list.insertList(list.allocator, i, other),
                .allocator = list.allocator,
            };
        }

        pub fn remove(list: @This(), i: usize) !@This() {
            return @This(){
                .list = try list.list.remove(list.allocator, i),
                .allocator = list.allocator,
            };
        }

        pub fn removeItems(list: @This(), i: usize, length: usize) !@This() {
            return @This(){
                .list = try list.list.removeItems(list.allocator, i, length),
                .allocator = list.allocator,
            };
        }

        pub fn slice(list: @This(), start: usize, end: usize) !@This() {
            return @This(){
                .list = try list.list.slice(list.allocator, start, end),
                .allocator = list.allocator,
            };
        }

        pub fn toSlice(list: @This(), allocator: *mem.Allocator) ![]T {
            return list.list.items(list.allocator);
        }

        pub fn equal(a: @This(), b: @This()) bool {
            return L.equal(a.list, b.list);
        }

        pub fn dump(list: @This(), stream: var) @TypeOf(stream.writeFn).ReturnType {
            return list.list.dump(stream);
        }
    };
}

pub fn NoAllocatorList(comptime T: type) type {
    return NoAllocatorCustomList(T, defaultLeafSize(T));
}

pub fn NoAllocatorCustomList(comptime T: type, comptime leaf_size: comptime_int) type {
    debug.assert(leaf_size >= 1);
    return struct {
        const node_size = math.max((@sizeOf(T) * leaf_size) / @sizeOf(usize), 2);

        length: usize = 0,
        depth: usize = 0,
        data: Data = Data{ .leaf = undefined },

        const Data = union {
            node: Node,
            leaf: Leaf,
        };

        const Leaf = struct {
            items: [leaf_size]T = undefined,
        };

        const L = @This();
        const Node = struct {
            length: usize = 0,
            children: [node_size]*L = undefined,
        };

        /// Creates a new list from a slice of items.
        pub fn fromSlice(allocator: *mem.Allocator, items: []const T) !@This() {
            if (items.len <= leaf_size) {
                var res = @This(){ .length = items.len };
                mem.copy(T, &res.data.leaf.items, items);
                return res;
            }

            var nodes = try allocator.alloc(@This(), divCeil(items.len, leaf_size));
            for (nodes) |*node, i| {
                const children = items[i * leaf_size ..];
                const length = math.min(children.len, leaf_size);
                node.* = fromSliceSmall(children[0..length]);
            }

            return try fromChildren(allocator, nodes);
        }

        pub fn fromSliceSmall(items: []const T) @This() {
            debug.assert(items.len <= leaf_size);
            var res = @This(){ .length = items.len };
            mem.copy(T, &res.data.leaf.items, items);
            return res;
        }

        /// Creates a new list from a slice of children.
        fn fromChildren(allocator: *mem.Allocator, children: []@This()) mem.Allocator.Error!@This() {
            if (children.len == 0)
                return @This(){};
            if (children.len <= node_size)
                return fromChildrenSmall(children);

            const nodes = try allocator.alloc(@This(), divCeil(children.len, node_size));
            for (nodes) |*node, i| {
                const c = children[i * node_size ..];
                node.* = fromChildrenSmall(c[0..math.min(c.len, node_size)]);
            }

            return fromChildren(allocator, nodes);
        }

        /// Creates a new list from a slice of children without needing any allocations.
        /// The slice length must be less than node_size.
        fn fromChildrenSmall(children: []@This()) @This() {
            if (children.len == 0)
                return @This(){};

            debug.assert(children.len <= node_size);
            const child_depth = children[0].depth;
            var res = @This(){
                .depth = child_depth + 1,
                .data = Data{ .node = undefined },
            };
            res.data.node.length = children.len;
            for (children) |*child, i| {
                debug.assert(child.depth == child_depth);
                res.length += child.length;
                res.data.node.children[i] = child;
            }

            return res;
        }

        /// Creates a new list from a slice of children without needing any allocations.
        /// The slice length must be less than node_size.
        fn fromChildrenPointersSmall(children: []const *@This()) @This() {
            if (children.len == 0)
                return @This(){};

            debug.assert(children.len <= node_size);
            const child_depth = children[0].depth;
            var res = @This(){
                .depth = child_depth + 1,
                .data = Data{ .node = undefined },
            };
            res.data.node.length = children.len;
            for (children) |child, i| {
                debug.assert(child.depth == child_depth);
                res.length += child.length;
                res.data.node.children[i] = child;
            }

            return res;
        }

        /// The number of items in the list.
        /// O(1)
        pub fn len(list: @This()) usize {
            return list.length;
        }

        /// Get an iterator that can effectivly iterate over all items in the
        /// list. The list pointer must outlive the iterator itself.
        /// O(1)
        pub fn iterator(list: *const @This(), start: usize) Iterator {
            return Iterator.init(list, start);
        }

        /// Get an iterator that can effectivly iterate over all items in the
        /// list. This iterator returns blocks of items instead of one item
        /// at the time. The list pointer must outlive the iterator itself.
        /// O(1)
        pub fn blockIterator(list: *const @This(), start: usize) BlockIterator {
            return BlockIterator.init(list, start);
        }

        /// Iterate over all items in the list, calling 'func' with each item in order.
        /// O(length * O(func))
        pub fn foreach(list: @This(), start: usize, context: var, func: var) @TypeOf(func).ReturnType {
            try list.foreachHelper(start, 0, context, func);
        }

        fn foreachHelper(list: @This(), start: usize, offset: usize, context: var, func: var) @TypeOf(func).ReturnType {
            if (list.depth == 0) {
                for (list.data.leaf.items[start..list.length]) |item, i|
                    try func(context, start + i + offset, item);
            } else {
                var new_start = start;
                var new_offset = offset;
                for (list.nodeChildren()) |child| {
                    if (child.length <= new_start) {
                        new_start -= child.length;
                        new_offset += child.length;
                        continue;
                    }

                    try child.foreachHelper(new_start, new_offset, context, func);
                    new_offset += child.length;
                    new_start = 0;
                }
            }
        }

        /// Iterate over all items in the list, calling 'func' with each item in order.
        /// O(length * O(func))
        pub fn foreachBlock(list: @This(), start: usize, context: var, func: var) @TypeOf(func).ReturnType {
            try list.foreachHelper(start, 0, context, func);
        }

        fn foreachBlockHelper(list: @This(), start: usize, offset: usize, context: var, func: var) @TypeOf(func).ReturnType {
            if (list.depth == 0) {
                try func(context, start + i + offset, ist.data.leaf.items[start..list.length]);
            } else {
                var new_start = start;
                var new_offset = offset;
                for (list.nodeChildren()) |child| {
                    if (child.length <= new_start) {
                        new_start -= child.length;
                        new_offset += child.length;
                        continue;
                    }

                    try child.foreachHelper(new_start, new_offset, context, func);
                    new_offset += child.length;
                    new_start = 0;
                }
            }
        }

        /// Iterate over all items in the list, calling 'func' with each block of items in order.
        /// O(depth) TODO: More accurate
        pub fn at(list: @This(), i: usize) T {
            debug.assert(i < list.length);
            if (list.depth == 0) {
                return list.data.leaf.items[i];
            } else {
                const sub_i = list.subIndex(i);
                return list.data.node.children[sub_i.node_i].at(sub_i.i);
            }
        }

        /// Creates a clone of the list which is safe to do mutations on.
        /// O(depth) TODO: More accurate
        pub fn mut(list: @This(), allocator: *mem.Allocator) mem.Allocator.Error!@This() {
            var res = list;
            if (res.depth == 0)
                return res;

            // TODO: mut should expect that the user is going to append at least on item.
            //       It should therefor make room for this one item when doing the dupe.
            res.lastNodePtr().* = try (try res.lastNode().mut(allocator)).dupe(allocator);
            return res;
        }

        /// Returns a new list which has 'item' appended to the end.
        /// O(depth) TODO: More accurate
        pub fn append(list: @This(), allocator: *mem.Allocator, item: T) !@This() {
            var res = try list.mut(allocator);
            try res.appendMut(allocator, item);
            return res;
        }

        /// Appends an item to the end of the list.
        /// O(depth) TODO: More accurate
        /// Warning: This method mutates the list. One should ensure that the mutated
        ///          part of the list is not shared with any other lists as this will
        ///          mutate those lists as well. The best way to ensure this is safe,
        ///          is to call 'mut' before using this method.
        pub fn appendMut(list: *@This(), allocator: *mem.Allocator, item: T) !void {
            return list.appendSliceMut(allocator, &[_]T{item});
        }

        /// Returns a new list which has 'items' appended to the end.
        /// O(depth + items.len) TODO: More accurate
        pub fn appendSlice(list: @This(), allocator: *mem.Allocator, items: []const T) !@This() {
            var res = try list.mut(allocator);
            try res.appendSliceMut(allocator, items);
            return res;
        }

        /// Appends items to the end of the list.
        /// O(depth + items.len) TODO: More accurate
        /// Warning: This method mutates the list. One should ensure that the mutated
        ///          part of the list is not shared with any other lists as this will
        ///          mutate those lists as well. The best way to ensure this is safe,
        ///          is to call 'mut' before using this method.
        pub fn appendSliceMut(list: *@This(), allocator: *mem.Allocator, items: []const T) !void {
            var i: usize = 0;
            while (i < items.len) {
                const space = try list.requestSpace(allocator, items[i..].len);
                mem.copy(T, space, items[i..][0..space.len]);
                i += space.len;
            }
        }

        /// Request new space from the end of the list. This will increase the lists size
        /// but the new items in the list will be 'undefined'. The new items added to the
        /// list will be returned. This function can return N items, where 0 < N <= 'space'.
        /// If N < 'space' and you really need 'space', then you can call this function
        /// again with 'space' - N.
        /// O(depth) TODO: More accurate
        /// Warning: This method mutates the list. One should ensure that the mutated part
        ///          of the list is not shared with any other lists as this will mutate
        ///          those lists as well. The best way to ensure this is safe, is to call
        ///          'mut' before using this method.
        pub fn requestSpace(list: *@This(), allocator: *mem.Allocator, space: usize) ![]T {
            const s = try list.requestSpaceHelper(allocator, space);
            if (s.len != 0)
                return s;

            if (list.depth == 0 or list.data.node.length == node_size) {
                const end = try (try createWithDepth(allocator, list.depth)).dupe(allocator);
                const old = try list.dupe(allocator);
                list.* = @This(){
                    .depth = old.depth + 1,
                    .length = old.length,
                    .data = Data{ .node = Node{ .length = 2 } },
                };
                list.data.node.children[0] = old;
                list.data.node.children[1] = end;
            } else {
                const end = try (try createWithDepth(allocator, list.depth - 1)).dupe(allocator);
                list.lastNodePtr().* = end;
                list.data.node.length += 1;
            }

            const res = try list.lastNode().requestSpaceHelper(allocator, space);
            debug.assert(res.len != 0);
            list.length += res.len;
            return res;
        }

        fn requestSpaceHelper(list: *@This(), allocator: *mem.Allocator, space: usize) mem.Allocator.Error![]T {
            if (list.depth == 0) {
                const length = math.min(space, leaf_size - list.length);
                defer list.length += length;
                return list.data.leaf.items[list.length..][0..length];
            }

            const s = try list.lastNode().requestSpaceHelper(allocator, space);
            if (s.len != 0) {
                list.length += s.len;
                return s;
            }

            if (list.data.node.length != node_size) {
                const end = try (try createWithDepth(allocator, list.depth - 1)).dupe(allocator);
                list.data.node.length += 1;
                list.lastNodePtr().* = end;

                const res = try end.requestSpaceHelper(allocator, space);
                debug.assert(res.len != 0);
                list.length += res.len;
                return res;
            }

            return s;
        }

        /// Returns a new list which has 'other' appended to the end.
        /// O(depth) TODO: More accurate
        pub fn appendList(list: @This(), allocator: *mem.Allocator, other: @This()) mem.Allocator.Error!@This() {
            if (other.length == 0)
                return list;
            if (list.length == 0)
                return other;

            // If the other list is small, then let's just append the items
            // of that list to this one.
            // TODO: What is a good small size???
            if (other.length <= leaf_size * 2) {
                var res = try list.mut(allocator);
                var it = other.blockIterator(0);
                while (it.next()) |s|
                    try res.appendSliceMut(allocator, s);

                return res;
            }

            // Because we other.length here is now > leaf_size,
            // this means that other should never be 0 deep.
            debug.assert(other.depth != 0);
            if (other.depth == list.depth) {
                if (list.data.node.length + other.data.node.length <= node_size) {
                    // Depth is the same and a new root node with the same depth
                    // can contain the children of 'list' and 'other'
                    // *->a   *->c   *->a
                    // *->b   *->d   *->b
                    // #      *->e   *->c
                    // #    + #    = *->d
                    // #      #      *->e
                    // #      #      #
                    var res = list;
                    mem.copy(*@This(), res.data.node.children[res.data.node.length..], other.nodeChildren());
                    res.data.node.length += other.data.node.length;
                    res.length += other.length;
                    return res;
                }

                // Depth is the same but a new root node does not have space for
                // 'list' and 'other'. We therefor need a new root which has depth
                // + 1
                // *->a   *->e   *------->*->g
                // *->b   *->f   *->*->a  *->h
                // *->c   *->g   #  *->b  #
                // *->d + *->h = #  *->c  #
                // #      #      #  *->d  #
                // #      #      #  *->e  #
                //                  *->f
                const children = try allocator.create([2]@This());
                children.* = [_]@This(){
                    list,
                    other,
                };
                const left = &children[0];
                const right = &children[1];
                const to_copy = node_size - left.data.node.length;
                mem.copy(*@This(), left.data.node.children[left.data.node.length..], right.nodeChildren()[0..to_copy]);
                left.data.node.length = node_size;
                left.length = left.calcLen();

                mem.copy(*@This(), &right.data.node.children, right.data.node.children[to_copy..]);
                right.data.node.length = other.data.node.length - to_copy;
                right.length = right.calcLen();
                return fromChildrenSmall(children);
            }
            if (other.depth < list.depth) {
                // If 'list.depth' is greater, then we pop the last
                // node and append 'other' to this node.
                var left = list;
                const last = left.lastNode();
                left.data.node.length -= 1;
                left.length -= last.length;

                var right = try last.appendList(allocator, other);
                if (left.depth != right.depth) {
                    // 'right.depth' is 'left.depth' - 1. We can therefore just put
                    // 'right' back where we popped a node further up.
                    // list:          left:   | last:  other: right: | result:
                    // *------->*->a  *->*->a | *->b   *->c   *->b   | *------->*->a
                    // *->*->b  #     #  #    | #      #      *->c   | *->*->b  #
                    // #  #     #     #  #    | #      #      #      | #  *->c  #
                    // #  #     #     #  #    | #    + #    = #      | #  #     #
                    // #  #     #     #  #    | #      #      #      | #  #     #
                    // #  #     #     #  #    | #      #      #      | #  #     #
                    //    #                   |                      | #
                    debug.assert(right.depth < left.depth);
                    right = try right.makeDeep(allocator, left.depth - 1);

                    left.data.node.length += 1;
                    left.lastNodePtr().* = try right.dupe(allocator);
                    left.length += right.length;
                    return left;
                }

                // Depth of 'left' and 'right' are now the same. Recall append
                // to hit the 'other.depth == list.depth' case above.
                return try left.appendList(allocator, right);
            }

            // If 'other.depth' is greater, then we pop the first
            // node and append 'list' to this node.
            var right = other;
            const first = right.firstNode();
            var left = try list.appendList(allocator, first.*);
            if (right.depth != left.depth) {
                // other:        | list:  first: left: | result:
                // *------->*->a | *->c   *->a   *->c  | *------->*->c
                // *->*->b  #    | #      #      *->a  | *->*->b  *->a
                // #  #     #    | #      #      #     | #  #     #
                // #  #     #    | #    + #    = #     | #  #     #
                // #  #     #    | #      #      #     | #  #     #
                // #  #     #    | #      #      #     | #  #     #
                //    #          |                     | #
                debug.assert(left.depth < right.depth);
                left = try left.makeDeep(allocator, right.depth - 1);

                right.length -= first.length;
                right.firstNodePtr().* = try left.dupe(allocator);
                right.length += left.length;
                return right;
            }

            // Depth of 'left' and 'right' are now the same. Recall append
            // to hit the 'other.depth == list.depth' case above.
            mem.copy(*@This(), &right.data.node.children, right.nodeChildren()[1..]);
            right.data.node.length -= 1;
            right.length -= first.length;
            return try left.appendList(allocator, right);
        }

        /// Returns list that has 'item' inserted a 'i'
        /// O(depth) TODO: More accurate
        pub fn insert(list: @This(), allocator: *mem.Allocator, i: usize, item: T) !@This() {
            return list.insertSlice(allocator, i, &[_]T{item});
        }

        /// Returns list that has 'item' inserted a 'i'
        /// O(depth) TODO: More accurate
        pub fn insertSlice(list: @This(), allocator: *mem.Allocator, i: usize, items: []const T) !@This() {
            // TODO: Figure out why the layout when inserting at i = 0 is weird
            //|-- length: 2047 depth: 2
            //||-- length: 722 depth: 1
            //||103|102|101|100|99|98|... length: 264
            //||103|102|101|100|99|98|... length: 264
            //||103|102|101|100|99|98|... length: 194
            //||--
            //|--
            //||-- length: 264 depth: 1
            //||101|100|99|98|97|104|... length: 264
            //||--
            //|--
            //||-- length: 1 depth: 1
            //||101 length: 1
            //||--
            //|--
            //||-- length: 264 depth: 1
            //||100|99|98|97|104|103|... length: 264
            //||--
            //|--
            //||-- length: 1 depth: 1
            //||100 length: 1
            //||--
            //|--
            //||-- length: 264 depth: 1
            //||99|98|97|104|103|102|... length: 264
            //||--
            //|--
            //||-- length: 1 depth: 1
            //||99 length: 1
            //||--
            //|--
            //||-- length: 530 depth: 1
            //||98|97|104|103|102|101|... length: 264
            //||98|97|104|103|102|101|... length: 264
            //||98|97 length: 2
            //||--
            //|--

            // TODO: Most of the time, 'slice' reallocs nodes in a way that would
            //       make mutating it actually safe. We should detect this, and not
            //       call 'mut' here if it is true.
            var first = try (try list.slice(allocator, 0, i)).mut(allocator);
            try first.appendSliceMut(allocator, items);
            return try first.appendList(allocator, try list.slice(allocator, i, list.length));
        }

        pub fn insertList(list: @This(), allocator: *mem.Allocator, i: usize, other: @This()) !@This() {
            var res = try list.slice(allocator, 0, i);
            res = try res.appendList(allocator, other);
            return try res.appendList(allocator, try list.slice(allocator, i, list.length));
        }

        /// Returns list that has the item at 'i' removed
        /// O(depth) TODO: More accurate
        pub fn remove(list: @This(), allocator: *mem.Allocator, i: usize) !@This() {
            return list.removeItems(allocator, i, 1);
        }

        /// Returns list that has the items from 'i' to 'i + len' (exclusive) removed.
        /// O(depth) TODO: More accurate
        pub fn removeItems(list: @This(), allocator: *mem.Allocator, i: usize, length: usize) !@This() {
            if (length == 0)
                return list;

            var res = try list.slice(allocator, 0, i);
            return res.appendList(allocator, try list.slice(allocator, i + length, list.length));
        }

        /// Slices the 'list' returning a new list containing the elements from start to end (exclusive)
        /// O(depth) TODO: More accurate
        pub fn slice(list: @This(), allocator: *mem.Allocator, start: usize, end: usize) mem.Allocator.Error!@This() {
            debug.assert(start <= end);
            debug.assert(end <= list.length);
            if (start == list.length)
                return @This(){};
            if (start == end)
                return @This(){};
            if (start == 0 and end == list.length)
                return list;

            if (list.depth == 0) {
                var res = @This(){};
                mem.copy(T, &res.data.leaf.items, list.data.leaf.items[start..end]);
                res.length = end - start;
                return res;
            }

            // Find first node inside slice
            var node_start: usize = 0;
            var first: usize = 0;
            var first_list: @This() = undefined;
            const children = list.nodeChildren();
            for (children) |child, i| {
                if (node_start <= start and start < node_start + child.length) {
                    // If both start and end are within this node, then we just slice the
                    // child and return
                    if (node_start < end and end <= node_start + child.length)
                        return child.slice(allocator, start - node_start, end - node_start);

                    first = i;
                    first_list = try child.slice(allocator, start - node_start, child.length);
                    node_start += child.length;
                    break;
                }

                node_start += child.length;
            } else unreachable;

            // Find last node inside slice
            var last: usize = first;
            var last_list: @This() = undefined;
            for (children[first + 1 ..]) |child, i| {
                if (node_start < end and end <= node_start + child.length) {
                    last = first + i + 1;
                    last_list = try child.slice(allocator, 0, end - node_start);
                    break;
                }

                node_start += child.length;
            } else unreachable;

            const mid_nodes = list.data.node.children[first + 1 .. last];
            const mid = fromChildrenPointersSmall(mid_nodes);
            var res = try first_list.appendList(allocator, mid);
            return try res.appendList(allocator, last_list);
        }

        /// Converts the list to a slice.
        /// O(length)
        pub fn toSlice(list: @This(), allocator: *mem.Allocator) ![]T {
            var res = try allocator.alloc(T, list.len());
            list.foreach(0, res, struct {
                fn each(s: []T, i: usize, item: T) error{}!void {
                    s[i] = item;
                }
            }.each) catch unreachable;
            return res;
        }

        /// Compare two lists for equallity.
        /// Note: Function is really fast when lists share large portions
        ///       of their nodes with eachother as we can then do a few
        ///       pointer comparisons instead of comparing the content itself.
        /// worst case: O(length^2)
        /// best case: O(1) (when lists share all nodes, or lengths differ)
        pub fn equal(a: @This(), b: @This()) bool {
            if (a.length != b.length)
                return false;

            if (a.depth == 0 and b.depth == 0) {
                for (a.data.leaf.items) |a_item, i| {
                    const b_item = b.data.leaf.items[i];
                    if (!std.meta.eql(a_item, b_item))
                        return false;
                }

                return true;
            }
            if (a.depth < b.depth)
                return equal(b, a);
            if (b.depth < a.depth) {
                if (a.data.node.length == 1)
                    return equal(a.lastNode().*, b);
            }

            const a_nodes = a.nodeChildren();
            const b_nodes = b.nodeChildren();
            return equalOnEachCommonLength(a_nodes, b_nodes);
        }

        fn equalOnEachCommonLength(a: []const *@This(), b: []const *@This()) bool {
            var a_len: usize = a[0].length;
            var b_len: usize = b[0].length;
            var a_start: usize = 0;
            var b_start: usize = 0;
            var a_i: usize = 0;
            var b_i: usize = 0;
            while (true) {
                const a_node = a[a_i];
                const b_node = b[b_i];
                if (a_len == b_len) {
                    if (!commonLengthEqual(a[a_start .. a_i + 1], b[b_start .. b_i + 1]))
                        return false;

                    a_i += 1;
                    b_i += 1;
                    a_start = a_i;
                    b_start = b_i;
                    if (a_start == a.len) {
                        debug.assert(b_start == b.len);
                        return true;
                    }
                    debug.assert(a_start != a.len and b_start != b.len);
                    a_len = a[a_i].length;
                    b_len = b[b_i].length;
                } else if (a_len < b_len) {
                    a_i += 1;
                    a_len += a[a_i].length;
                } else if (b_len < a_len) {
                    b_i += 1;
                    b_len += b[b_i].length;
                }
            }
        }

        fn commonLengthEqual(a: []const *@This(), b: []const *@This()) bool {
            if (a.len == 1 and b.len == 1) {
                debug.assert(a[0].length == b[0].length);
                return a[0] == b[0] or equal(a[0].*, b[0].*);
            }
            if (a.len == 1 and a[0].depth != 0)
                return equalOnEachCommonLength(a[0].nodeChildren(), b);
            if (b.len == 1 and b[0].depth != 0)
                return equalOnEachCommonLength(b[0].nodeChildren(), a);

            var a_list = fromChildrenPointersSmall(a);
            var b_list = fromChildrenPointersSmall(b);
            debug.assert(a_list.length == b_list.length);

            return itEqual(&a_list.iterator(0), &b_list.iterator(0));
        }

        fn itEqual(a: *Iterator, b: *Iterator) bool {
            while (true) {
                const a_i = a.next() orelse break;
                const b_i = b.next().?;
                if (!std.meta.eql(a_i, b_i))
                    return false;
            }

            return true;
        }

        pub fn dump(list: @This(), stream: var) @TypeOf(stream.writeFn).ReturnType {
            if (list.depth == 0) {
                const max_items = 6;
                for (list.data.leaf.items[0..math.min(list.length, max_items)]) |item, i| {
                    if (i != 0)
                        try stream.writeAll("|");
                    try stream.print("{}", item);
                }
                if (max_items < list.length)
                    try stream.print("|...");
                try stream.print(" length: {}", list.length);
            } else {
                var lps = try LinePrependStream(@TypeOf(stream.writeFn).ReturnType.ErrorSet).init("|", stream);
                try lps.stream.print("-- length: {} depth: {}", list.length, list.depth);
                for (list.nodeChildren()) |child, i| {
                    try lps.stream.write("\n");
                    try child.dump(&lps.stream);
                    if (child.depth != 0 or i + 1 == list.nodeChildren().len)
                        try lps.stream.write("\n--");
                }
            }
        }

        fn LinePrependStream(comptime WriteError: type) type {
            return struct {
                const Error = WriteError;
                const Stream = std.io.OutStream(Error);

                stream: Stream,
                child_stream: *Stream,
                prefix: []const u8,

                fn init(prefix: []const u8, child_stream: *Stream) !@This() {
                    try child_stream.write(prefix);
                    return @This(){
                        .stream = Stream{ .writeFn = writeFn },
                        .child_stream = child_stream,
                        .prefix = prefix,
                    };
                }

                fn writeFn(out_stream: *Stream, bytes: []const u8) Error!void {
                    const self = @fieldParentPtr(@This(), "stream", out_stream);
                    var tmp = bytes;
                    while (mem.indexOfScalar(u8, tmp, '\n')) |i| {
                        try self.child_stream.write(tmp[0..i]);
                        try self.child_stream.write("\n");
                        try self.child_stream.write(self.prefix);
                        tmp = tmp[i + 1 ..];
                    }
                    try self.child_stream.write(tmp);
                }
            };
        }

        const SubIndex = struct {
            node_i: usize,
            i: usize,
        };

        fn subIndex(list: @This(), i: usize) SubIndex {
            debug.assert(list.depth != 0);
            debug.assert(i <= list.length);
            if (i == list.length) {
                return SubIndex{
                    .node_i = list.data.node.length - 1,
                    .i = list.lastNode().length,
                };
            }

            var new_i = i;
            for (list.nodeChildren()) |child, j| {
                if (new_i < child.length) {
                    return SubIndex{
                        .node_i = j,
                        .i = new_i,
                    };
                }

                new_i -= child.length;
            }

            unreachable;
        }

        fn lastNode(list: @This()) *@This() {
            return list.lastNodePtr().*;
        }

        fn lastNodePtr(list: var) @TypeOf(&list.data.node.children[0]) {
            debug.assert(list.depth != 0);
            return &list.data.node.children[list.data.node.length - 1];
        }

        fn firstNode(list: @This()) *@This() {
            return list.firstNodePtr().*;
        }

        fn firstNodePtr(list: var) @TypeOf(&list.data.node.children[0]) {
            debug.assert(list.depth != 0);
            return &list.data.node.children[0];
        }

        fn nodeChildren(list: @This()) []const *@This() {
            debug.assert(list.depth != 0);
            return list.data.node.children[0..list.data.node.length];
        }

        fn createWithDepth(allocator: *mem.Allocator, depth: usize) !@This() {
            return try (@This(){}).makeDeep(allocator, depth);
        }

        fn calcLen(list: @This()) usize {
            var res: usize = 0;
            for (list.nodeChildren()) |child|
                res += child.length;

            return res;
        }

        fn makeDeep(list: @This(), allocator: *mem.Allocator, depth: usize) !@This() {
            var res = list;
            while (res.depth < depth)
                res = try fromChildren(allocator, @as(*[1]@This(), try res.dupe(allocator)));

            return res;
        }

        fn dupe(list: @This(), allocator: *mem.Allocator) !*@This() {
            const res = try allocator.create(@This());
            res.* = list;
            return res;
        }

        pub const BlockIterator = struct {
            const Item = struct {
                curr: usize = 0,
                list: *const L,
            };

            // TODO: Calc max depth for list that "fills" the entier addr space
            stack: [32]Item = undefined,
            stack_len: usize = 0,

            fn init(list: *const L, start: usize) BlockIterator {
                var res = BlockIterator{};
                if (list.len() == 0)
                    return res;
                if (list.len() <= start)
                    return res;

                var new_start = start;
                var curr = list;
                while (true) {
                    if (curr.depth == 0) {
                        res.push(Item{ .curr = new_start, .list = curr });
                        break;
                    }

                    const i = curr.subIndex(new_start);
                    res.push(Item{ .curr = i.node_i, .list = curr });
                    new_start = i.i;
                    curr = curr.nodeChildren()[i.node_i];
                }

                return res;
            }

            fn pop(it: *BlockIterator) void {
                it.stack_len -= 1;
            }

            fn push(it: *BlockIterator, item: Item) void {
                defer it.stack_len += 1;
                it.stack[it.stack_len] = item;
            }

            fn lastItem(it: *BlockIterator) ?*Item {
                if (it.stack_len == 0)
                    return null;
                return &it.stack[it.stack_len - 1];
            }

            pub fn next(it: *BlockIterator) ?[]const T {
                const curr = it.lastItem() orelse return null;
                debug.assert(curr.curr < curr.list.len());
                debug.assert(curr.list.depth == 0);

                const res = curr.list.data.leaf.items[curr.curr..curr.list.length];
                while (true) {
                    it.pop();
                    const l = it.lastItem() orelse break;
                    l.curr += 1;
                    if (l.curr < l.list.data.node.length)
                        break;
                }
                while (true) {
                    const l = it.lastItem() orelse break;
                    if (l.list.depth == 0)
                        break;

                    it.push(Item{ .list = l.list.data.node.children[l.curr] });
                }

                return res;
            }
        };

        pub const Iterator = struct {
            inner: BlockIterator,
            curr: []const T = &[_]T{},
            curr_i: usize = 0,

            fn init(list: *const L, start: usize) Iterator {
                return Iterator{
                    .inner = BlockIterator.init(list, start),
                };
            }

            pub fn next(it: *Iterator) ?T {
                while (it.curr.len <= it.curr_i) {
                    it.curr = it.inner.next() orelse return null;
                    it.curr_i = 0;
                }

                defer it.curr_i += 1;
                return it.curr[it.curr_i];
            }
        };
    };
}

fn divCeil(a: var, b: var) @TypeOf(a / b) {
    return (a + (b - 1)) / b;
}

test "divCeil" {
    testing.expectEqual(@as(u64, 0), divCeil(0, 5));
    testing.expectEqual(@as(u64, 1), divCeil(1, 5));
    testing.expectEqual(@as(u64, 1), divCeil(5, 5));
    testing.expectEqual(@as(u64, 2), divCeil(6, 5));
    testing.expectEqual(@as(u64, 2), divCeil(10, 5));
    testing.expectEqual(@as(u64, 3), divCeil(11, 5));
    testing.expectEqual(@as(u64, 3), divCeil(15, 5));
}
