pub usingnamespace @import("handle.zig");
const std = @import("std");
const mem = std.mem;

pub fn HandleGenerator(comptime HandleType: type) type {
    return struct {
        const Self = @This();
        valid_generations: std.ArrayList(HandleType.Generation),
        discarded_handle_indices: std.ArrayList(HandleType.Index),

        pub fn init(allocator: *mem.Allocator) Self {
            return Self{
                .valid_generations = std.ArrayList(HandleType.Generation).init(allocator),
                .discarded_handle_indices = std.ArrayList(HandleType.Index).init(allocator),
            };
        }

        pub fn deinit(self: Self) void {
            self.discarded_handle_indices.deinit();
            self.valid_generations.deinit();
        }

        pub fn newHandle(self: *Self) !HandleType {
            if (self.discarded_handle_indices.popOrNull()) |index| {
                return HandleType{ .index = index, .generation = self.valid_generations.items[index] };
            }
            const index = @intCast(HandleType.Index, self.valid_generations.items.len);
            try self.valid_generations.append(0);
            return HandleType{ .generation = 0, .index = index };
        }

        pub fn newHandles(self: *Self, handles: []HandleType) !void {
            const reuse_handle_count = std.math.min(self.discarded_handle_indices.items.len, handles.len);
            for (handles[0..reuse_handle_count]) |*handle, i| {
                const index = self.discarded_handle_indices.items[i];
                handle.* = .{ .index = index, .generation = self.valid_generations.items[index] };
            }
            self.discarded_handle_indices.items.len = self.discarded_handle_indices.items.len - reuse_handle_count;
            const index_start = self.valid_generations.items.len;
            try self.valid_generations.appendNTimes(0, index_start + (handles.len - reuse_handle_count));
            for (handles[reuse_handle_count..]) |*handle, i| {
                handle.* = .{ .index = @intCast(HandleType.Index, index_start + i), .generation = 0 };
            }
        }

        pub fn discard(self: *Self, handle: HandleType) !void {
            try self.discarded_handle_indices.append(handle.index);
            std.debug.assert(self.valid_generations.items[handle.index] == handle.generation);
            self.valid_generations.items[handle.index] = handle.generation +% 1;
        }

        pub fn discardMultiple(self: *Self, handles: []HandleType) !void {
            try self.discarded_handle_indices.ensureCapacity(self.discarded_handle_indices.items.len + handles.len);
            for (handles) |handle| {
                std.debug.assert(self.valid_generations.items[handle.index] == handle.generation);
            }
            for (handles) |handle| {
                self.valid_generations.items[handle.index] = handle.generation +% 1;
            }
            for (handles) |handle| {
                self.discarded_handle_indices.appendAssumeCapacity(handle.index);
            }
        }

        pub fn isValid(self: Self, handle: HandleType) bool {
            return self.valid_generations.items[handle.index] == handle.generation;
        }
    };
}

const testing = std.testing;
const TestObject = struct {};
const TestHandle = Handle(TestObject);
const TestHandleGenerator = HandleGenerator(TestHandle);

test "creating new handles should return different handles" {
    var generator = TestHandleGenerator.init(testing.allocator);
    defer generator.deinit();
    const handle1 = try generator.newHandle();
    const handle2 = try generator.newHandle();
    testing.expect(!std.meta.eql(handle1, handle2));
    var handles: [2]TestHandle = undefined;
    try generator.newHandles(&handles);
    testing.expect(!std.meta.eql(handles[0], handles[1]));
}

test "discarding one handle should make creating a new handle return the same index with an incremented generation" {
    var generator = TestHandleGenerator.init(testing.allocator);
    defer generator.deinit();
    const handle1 = try generator.newHandle();
    try generator.discard(handle1);
    const handle2 = try generator.newHandle();
    testing.expectEqual(handle1.index, handle2.index);
    testing.expect(handle1.generation + 1 == handle2.generation);
}

test "creating a new handles after discarding should return different handles" {
    var generator = TestHandleGenerator.init(testing.allocator);
    defer generator.deinit();
    try generator.discard(try generator.newHandle());
    const handle1 = try generator.newHandle();
    const handle2 = try generator.newHandle();
    testing.expect(!std.meta.eql(handle1, handle2));
}

test "discarding multiple handles should result in all of them being re-used with incremented generations " {
    var generator = TestHandleGenerator.init(testing.allocator);
    defer generator.deinit();
    var handle1 = try generator.newHandle();
    var handle2 = try generator.newHandle();
    try generator.discardMultiple(&[_]TestHandle{ handle1, handle2 });

    handle1.generation += 1;
    handle2.generation += 1;
    const handle3 = try generator.newHandle();
    const handle4 = try generator.newHandle();
    testing.expect(std.meta.eql(handle1, handle3) or std.meta.eql(handle2, handle3));
    testing.expect(std.meta.eql(handle1, handle4) or std.meta.eql(handle2, handle4));
}

test "new handles should be valid" {
    var generator = TestHandleGenerator.init(testing.allocator);
    defer generator.deinit();
    testing.expect(generator.isValid(try generator.newHandle()));
}

test "discarded handles should not be valid" {
    var generator = TestHandleGenerator.init(testing.allocator);
    defer generator.deinit();
    const handle = try generator.newHandle();
    try generator.discard(handle);
    testing.expect(!generator.isValid(handle));
}
