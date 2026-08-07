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
    var buffer = [_]u8{0} ** (@sizeOf(u32) + 1);
    var i: u8 = 0;
    while (i < buffer.len) : (i += 1) {
        if (i > 0) {
            buffer[i - 1] |= 0x80; // set continuation bit
        }
        buffer[i] = @as(u8, @truncate(tmp)) & 0x7F; // take first 7 bits
        tmp >>= 7;
        if (tmp == 0) {
            break;
        }
    }
    try self.buf.appendSlice(alloc, buffer[0 .. i + 1]);
}

pub fn writeBool(self: *Writer, alloc: mem.Allocator, val: bool) !void {
    if (val) {
        try self.buf.append(alloc, 1);
    } else {
        try self.buf.append(alloc, 0);
    }
}

pub fn writeNullableString(self: *Writer, alloc: mem.Allocator, val: ?[]const u8) !void {
    if (val) |str| {
        try self.writeInt(alloc, i16, @intCast(str.len));
        try self.buf.appendSlice(alloc, str);
    } else {
        try self.writeInt(alloc, i16, -1);
    }
}

pub fn writeCompactString(self: *Writer, alloc: mem.Allocator, val: []const u8) !void {
    try self.writeUvarint(alloc, @intCast(val.len));
    try self.buf.appendSlice(alloc, val);
}

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

test "writeNullableString:null" {
    var w: Writer = .{};
    defer w.deinit(std.testing.allocator);
    try w.writeNullableString(std.testing.allocator, null);
    try std.testing.expect(mem.eql(u8, w.buf.items, &.{ 0xFF, 0xFF }));
}

test "writeNullableString:empty" {
    var w: Writer = .{};
    defer w.deinit(std.testing.allocator);
    try w.writeNullableString(std.testing.allocator, "");
    try std.testing.expect(mem.eql(u8, w.buf.items, &.{ 0x00, 0x00 }));
}

test "writeNullableString:happy" {
    var w: Writer = .{};
    defer w.deinit(std.testing.allocator);
    try w.writeNullableString(std.testing.allocator, "happy");
    try std.testing.expect(mem.eql(u8, w.buf.items, &.{ 0x00, 0x05, 'h', 'a', 'p', 'p', 'y' }));
}

test "writeCompactString:empty" {
    var w: Writer = .{};
    defer w.deinit(std.testing.allocator);
    try w.writeCompactString(std.testing.allocator, "");
    try std.testing.expect(mem.eql(u8, w.buf.items, &.{0x00}));
}

test "writeCompactString:happy" {
    var w: Writer = .{};
    defer w.deinit(std.testing.allocator);
    try w.writeCompactString(std.testing.allocator, "happy");
    try std.testing.expect(mem.eql(u8, w.buf.items, &.{ 0x05, 'h', 'a', 'p', 'p', 'y' }));
}

test "writeBool:true" {
    var w: Writer = .{};
    defer w.deinit(std.testing.allocator);
    try w.writeBool(std.testing.allocator, true);
    try std.testing.expect(mem.eql(u8, w.buf.items, &.{0x01}));
}

test "writeBool:false" {
    var w: Writer = .{};
    defer w.deinit(std.testing.allocator);
    try w.writeBool(std.testing.allocator, false);
    try std.testing.expect(mem.eql(u8, w.buf.items, &.{0x00}));
}
