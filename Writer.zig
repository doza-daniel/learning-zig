const std = @import("std");

const mem = std.mem;

const Writer = @This();

buf: []u8 = &[_]u8{},
offset: usize = 0,
max_size: usize = 10 * 1024 * 1024 * 1024, // 10 MiB

pub fn writeInt(self: *Writer, alloc: mem.Allocator, comptime T: type, val: T) !void {
    try self.resizeIfNeeded(alloc, @sizeOf(T));
    const b = self.buf[self.offset..][0..@sizeOf(T)];
    mem.writeInt(T, b, val, .big);
    self.offset += @sizeOf(T);
}

pub fn writeUvarint(self: *Writer, alloc: mem.Allocator, val: u32) !void {
    _ = self;
    var al: std.ArrayList(u8) = .empty;
    defer al.deinit(alloc);

    var tmp = val;
    while (true) {
        if (al.items.len > 0) {
            al.items[al.items.len - 1] |= 0x80; // set continuation bit
        }
        try al.append(alloc, @as(u8, @truncate(tmp)) & 0x7F);
        tmp >>= 7;
        if (tmp == 0) {
            break;
        }
    }
    std.debug.print("{x}\n", .{al.items});
}

pub fn writeString() !void {}

pub fn writeCompactString() !void {}

pub fn deinit(self: *Writer, alloc: mem.Allocator) void {
    alloc.free(self.buf);
}

fn resizeIfNeeded(self: *Writer, alloc: mem.Allocator, want: usize) !void {
    const need = self.offset + want;
    if (self.buf.len >= need) {
        return;
    }
    if (need > self.max_size) {
        return error.BufferOutOfSpace;
    }
    const resized = try alloc.alloc(u8, need);
    @memcpy(resized[0..self.buf.len], self.buf);
    alloc.free(self.buf);
    self.buf = resized;
}

test "writeInt" {
    var w = Writer{};
    try w.writeInt(std.testing.allocator, u8, 15);
    try w.writeInt(std.testing.allocator, u16, 15603);
    try w.writeInt(std.testing.allocator, u32, 1560312312);
    defer w.deinit(std.testing.allocator);
    const expect = [_]u8{
        0x0F, // 15
        0x3C, 0xF3, // 15603
        0x5D, 0x00, 0x79, 0xF8, // 1560312312
    };
    try std.testing.expect(mem.eql(u8, &expect, w.buf));
}

test "writeInt:out_of_space" {
    const max_size: usize = 10;
    const mock = try std.testing.allocator.alloc(u8, max_size - 1);
    defer std.testing.allocator.free(mock);
    var w = Writer{
        .buf = mock,
        .offset = max_size - 1,
        .max_size = max_size,
    };
    w.writeInt(std.testing.allocator, u16, 15603) catch |err| {
        try std.testing.expectEqual(error.BufferOutOfSpace, err);
        return;
    };
    try std.testing.expect(false);
}

test "writeInt:no_resize" {
    var buf = [_]u8{0};
    var w = Writer{
        .buf = &buf,
    };
    try w.writeInt(std.testing.failing_allocator, u8, 15);
    const expect = [_]u8{0x0F};
    try std.testing.expect(mem.eql(u8, &expect, w.buf));
}

test "writeUvarint" {
    var w = Writer{};
    try w.writeUvarint(std.testing.allocator, 0xffffffff);
}
