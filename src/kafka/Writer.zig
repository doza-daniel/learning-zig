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
    try self.writeUvarint(alloc, @intCast(val.len + 1));
    try self.buf.appendSlice(alloc, val);
}

pub fn writeCompactNullableString(self: *Writer, alloc: mem.Allocator, val: ?[]const u8) !void {
    if (val) |str| {
        try self.writeCompactString(alloc, str);
    } else {
        try self.writeUvarint(alloc, 0);
    }
}

pub fn writeUuid(self: *Writer, alloc: mem.Allocator, val: [16]u8) !void {
    try self.buf.appendSlice(alloc, &val);
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

test "writeNullableString" {
    const table = .{
        .{ .input = null, .expect = [_]u8{ 0xff, 0xff } },
        .{ .input = "", .expect = [_]u8{ 0x00, 0x00 } },
        .{ .input = "a", .expect = [_]u8{ 0x00, 0x01, 'a' } },
        .{ .input = "aa", .expect = [_]u8{ 0x00, 0x02, 'a', 'a' } },
        .{ .input = "a" ** 256, .expect = [_]u8{ 0x01, 0x00 } ++ [_]u8{'a'} ** 256 },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(std.testing.allocator);

        try w.writeNullableString(std.testing.allocator, case.input);

        var expect = case.expect;
        try std.testing.expectEqualDeep(&expect, w.buf.items);
    }
}

test "writeCompactString" {
    const table = .{
        .{ .input = "", .expect = [_]u8{0x01} },
        .{ .input = "a", .expect = [_]u8{ 0x02, 'a' } },
        .{ .input = "aa", .expect = [_]u8{ 0x03, 'a', 'a' } },
        .{ .input = "aaa", .expect = [_]u8{ 0x04, 'a', 'a', 'a' } },
        .{ .input = "a" ** 130, .expect = [_]u8{ 0x83, 0x01 } ++ [_]u8{'a'} ** 130 },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(std.testing.allocator);

        try w.writeCompactString(std.testing.allocator, case.input);

        var expect = case.expect;
        try std.testing.expectEqualDeep(&expect, w.buf.items);
    }
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
