const std = @import("std");

const mem = std.mem;

const Reader = @This();

src: []u8,

pub fn readInt(self: *Reader, T: type) !T {
    if (self.src.len < @sizeOf(T)) {
        return error.UnexpectedEOF;
    }
    const result = mem.readInt(T, self.src[0..@sizeOf(T)], .big);
    self.src = self.src[@sizeOf(T)..];
    return result;
}

pub fn readUvarint(self: *Reader) !u32 {
    var result: u32 = 0;
    var shift: u5 = 0;
    for (self.src, 0..) |byte, i| {
        if (i == 4) {
            if (byte > 0x3F) {
                return error.Overflow;
            }
        }

        result |= @as(u32, byte & 0x7F) << shift;
        if (byte < 0x80) {
            self.src = self.src[i + 1 ..];
            return result;
        }

        shift += 7;
    }
    return error.UnexpectedEOF;
}

pub fn readNullableString(
    self: *Reader,
    alloc: mem.Allocator,
) !?[]const u8 {
    const num = try self.readInt(i16);
    if (num < 0) {
        return null;
    }

    const len = @as(usize, @intCast(num));

    if (self.src.len < len) {
        return error.UnexpectedEOF;
    }

    const str = try alloc.dupe(u8, self.src[0..len]);
    self.src = self.src[len..];
    return str;
}

pub fn readCompactString(self: *Reader, alloc: mem.Allocator) ![]const u8 {
    const len = try self.readUvarint();
    if (len <= 1) {
        return "";
    }
    if (self.src.len < len - 1) {
        return error.UnexpectedEOF;
    }
    const x = try alloc.dupe(u8, self.src[0 .. len - 1]);
    self.src = self.src[len - 1 ..];
    return x;
}

pub fn readUuid(self: *Reader) ![16]u8 {
    var result = [_]u8{0} ** 16;
    if (self.src.len < @sizeOf(@TypeOf(result))) {
        return error.UnexpectedEOF;
    }
    @memcpy(&result, self.src[0..16]);
    self.src = self.src[16..];
    return result;
}

pub fn readBool(self: *Reader) !bool {
    return try self.readInt(u8) > 0;
}

test "readUvarint:happy" {
    var in = [_]u8{ 0x96, 0x01 };
    const expect: u32 = 150;
    var x: Reader = .{ .src = &in };
    const got = try x.readUvarint();
    try std.testing.expect(got == expect);
}

test "readUvarint:overflow" {
    var in = [_]u8{ 0xff, 0xff, 0xff, 0xff, 0x4f };
    var x: Reader = .{ .src = &in };
    _ = x.readUvarint() catch |err| {
        try std.testing.expect(err == error.Overflow);
        return;
    };
    try std.testing.expect(false);
}

test "readUvarint:unexpected_eof" {
    var in = [_]u8{0xff};
    var x: Reader = .{ .src = &in };
    _ = x.readUvarint() catch |err| {
        try std.testing.expect(err == error.UnexpectedEOF);
        return;
    };
    try std.testing.expect(false);
}

test "readUvarint:max_u32" {
    var in = [_]u8{ 0xff, 0xff, 0xff, 0xff, 0x3f };
    var x: Reader = .{ .src = &in };
    const got = try x.readUvarint();
    try std.testing.expect(got == std.math.maxInt(u32));
}

test "readNullableString:null" {
    var in = [_]u8{ 0xff, 0xff };
    var x: Reader = .{ .src = &in };
    const got = x.readNullableString(std.testing.allocator) catch {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expect(got == null);
}

test "readNullableString:empty" {
    var in = [_]u8{ 0x00, 0x00 };
    var x: Reader = .{ .src = &in };
    const got = x.readNullableString(std.testing.allocator) catch {
        try std.testing.expect(false);
        return;
    };
    if (got) |str| {
        try std.testing.expect(str.len == 0);
        return;
    }
    try std.testing.expect(false);
}

test "readNullableString:hello" {
    var in = [_]u8{ 0x00, 0x05, 'h', 'e', 'l', 'l', 'o' };
    var x: Reader = .{ .src = &in };
    const got = x.readNullableString(std.testing.allocator) catch {
        try std.testing.expect(false);
        return;
    };
    if (got) |str| {
        try std.testing.expect(mem.eql(u8, str, "hello"));
        std.testing.allocator.free(str);
        return;
    }
    try std.testing.expect(false);
}

test "readNullableString:alloc_fail" {
    var in = [_]u8{ 0x00, 0x05, 'h', 'e', 'l', 'l', 'o' };
    var x: Reader = .{ .src = &in };
    _ = x.readNullableString(std.testing.failing_allocator) catch |err| {
        try std.testing.expect(err == error.OutOfMemory);
        return;
    };
    try std.testing.expect(false);
}

test "readUuid" {
    var in = [_]u8{ 0x45, 0x0c, 0xfe, 0xbc, 0x51, 0xe1, 0x4c, 0x7b, 0x7a, 0x25, 0xe4, 0x33, 0x0e, 0xc5, 0x5e, 0x5d };
    var x: Reader = .{ .src = &in };
    const got = try x.readUuid();
    try std.testing.expect(mem.eql(u8, &got, &in));
}
