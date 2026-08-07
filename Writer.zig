const std = @import("std");

const mem = std.mem;

const Writer = @This();

buf: std.ArrayList(u8) = .empty,

pub fn writeInt(self: *Writer, alloc: mem.Allocator, comptime T: type, val: T) !void {
    var buffer = [_]u8{0} ** @sizeOf(T);
    mem.writeInt(T, &buffer, val, .big);
    try self.buf.appendSlice(alloc, &buffer);
}

pub fn writeUvarint(self: *Writer, alloc: mem.Allocator, val: u32) !void {
    var tmp = val;
    var buffer = [_]u8{0} ** 5;
    var i: u8 = 0;
    while (i < buffer.len) : (i += 1) {
        if (i > 0) {
            buffer[i - 1] |= 0x80; // set continuation bit
        }
        buffer[i] = @as(u8, @truncate(tmp)) & 0x7F;
        tmp >>= 7;
        if (tmp == 0) {
            break;
        }
    }
    try self.buf.appendSlice(alloc, buffer[0 .. i + 1]);
}

pub fn writeString() !void {}

pub fn writeCompactString() !void {}

pub fn deinit(self: *Writer, alloc: mem.Allocator) void {
    self.buf.deinit(alloc);
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
    try std.testing.expect(mem.eql(u8, &expect, w.buf.items));
}

test "writeUvarint" {
    var w = Writer{};
    const expect: u32 = 0xffff;
    try w.writeUvarint(std.testing.allocator, expect);
    const Reader = @import("Reader.zig");
    var x: Reader = .{ .src = w.buf.items };
    const got = try x.readUvarint();
    try std.testing.expectEqual(got, expect);
    w.deinit(std.testing.allocator);
}
