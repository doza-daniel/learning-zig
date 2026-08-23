const std = @import("std");

const mem = std.mem;

const Reader = @This();

src: []u8,

pub fn readBool(self: *Reader) !bool {
    return try self.readInt(u8) > 0;
}

pub fn readInt(self: *Reader, T: type) !T {
    if (self.src.len < @sizeOf(T)) {
        return error.UnexpectedEOF;
    }
    const result = mem.readInt(T, self.src[0..@sizeOf(T)], .big);
    self.src = self.src[@sizeOf(T)..];
    return result;
}

pub fn readVarint(self: *Reader) !i32 {
    const x = try self.readUvarint();
    return @bitCast((x >> 1) ^ -%(x & 1));
}

pub fn readVarlong(self: *Reader) !i64 {
    const x = try self.readUvarlong();
    return @bitCast((x >> 1) ^ -%(x & 1));
}

pub fn readUvarint(self: *Reader) !u32 {
    var result: u32 = 0;

    for (self.src, 0..) |byte, i| {
        if (i == 4) {
            if (byte > 0x0F) {
                return error.Overflow;
            }
        }

        result |= @as(u32, byte & 0x7F) << @as(u5, @intCast(7 * i));

        if (byte & 0x80 == 0) {
            self.src = self.src[i + 1 ..];
            return result;
        }
    }

    return error.UnexpectedEOF;
}

pub fn readUvarlong(self: *Reader) !u64 {
    var result: u64 = 0;

    for (self.src, 0..) |byte, i| {
        if (i == 9) {
            if (byte > 0x01) {
                return error.Overflow;
            }
        }

        result |= @as(u64, byte & 0x7F) << @as(u6, @intCast(7 * i));

        if (byte & 0x80 == 0) {
            self.src = self.src[i + 1 ..];
            return result;
        }
    }

    return error.UnexpectedEOF;
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

pub fn readFloat64(self: *Reader) !f64 {
    if (self.src.len < @sizeOf(f64)) {
        return error.UnexpectedEOF;
    }

    return @bitCast(try self.readInt(u64));
}

pub fn readString(self: *Reader, alloc: mem.Allocator) ![]const u8 {
    const len = try self.readInt(i16);
    if (len < 0) {
        return error.NullString;
    }
    if (len == 0) {
        return "";
    }
    if (self.src.len < len) {
        return error.UnexpectedEOF;
    }

    const str = try alloc.dupe(u8, self.src[0..@intCast(len)]);
    self.src = self.src[@intCast(len)..];
    return str;
}

pub fn readCompactString(self: *Reader, alloc: mem.Allocator) ![]const u8 {
    const len = try self.readUvarint();
    if (len == 0) {
        return error.NullString;
    }
    if (len == 1) {
        return "";
    }
    if (self.src.len < len - 1) {
        return error.UnexpectedEOF;
    }
    const str = try alloc.dupe(u8, self.src[0 .. len - 1]);
    self.src = self.src[len - 1 ..];
    return str;
}

pub fn readNullableString(
    self: *Reader,
    alloc: mem.Allocator,
) !?[]const u8 {
    return self.readString(alloc) catch |err| {
        if (err == error.NullString) {
            return null;
        }
        return err;
    };
}

pub fn readCompactNullableString(self: *Reader, alloc: mem.Allocator) !?[]const u8 {
    return self.readCompactString(alloc) catch |err| {
        if (err == error.NullString) {
            return null;
        }
        return err;
    };
}

pub fn readBytes(self: *Reader, alloc: mem.Allocator) ![]u8 {
    const len = try self.readInt(i32);
    if (len < 0) {
        return error.NullBytes;
    }
    if (len == 0) {
        return &.{};
    }
    if (self.src.len < len) {
        return error.UnexpectedEOF;
    }
    const str = try alloc.dupe(u8, self.src[0..@intCast(len)]);
    self.src = self.src[@intCast(len)..];
    return str;
}

pub fn readCompactBytes(self: *Reader, alloc: mem.Allocator) ![]u8 {
    const len = try self.readUvarint();
    if (len == 0) {
        return error.NullBytes;
    }
    if (len == 1) {
        return &.{};
    }
    if (self.src.len < len - 1) {
        return error.UnexpectedEOF;
    }
    const bytes = try alloc.dupe(u8, self.src[0 .. len - 1]);
    self.src = self.src[len - 1 ..];
    return bytes;
}

pub fn readNullableBytes(self: *Reader, alloc: mem.Allocator) !?[]u8 {
    return self.readBytes(alloc) catch |err| {
        if (err == error.NullBytes) {
            return null;
        }
        return err;
    };
}

pub fn readCompactNullableBytes(self: *Reader, alloc: mem.Allocator) !?[]u8 {
    return self.readCompactBytes(alloc) catch |err| {
        if (err == error.NullBytes) {
            return null;
        }
        return err;
    };
}

pub fn readArray(self: *Reader, T: type, alloc: mem.Allocator) ![]T {
    const len = try self.readInt(i32);
    if (len < 0) {
        return error.NullArray;
    }
    if (len == 0) {
        return &.{};
    }
    if (self.src.len < len * @sizeOf(T)) {
        return error.UnexpectedEOF;
    }
    const arr = try alloc.alloc(T, @intCast(len));
    for (0..arr.len) |i| {
        try arr[i].read(self, alloc);
    }
    return arr;
}

pub fn readCompactArray(self: *Reader, T: type, alloc: mem.Allocator) ![]T {
    const len = try self.readUvarint();
    if (len == 0) {
        return error.NullArray;
    }
    if (len == 1) {
        return &.{};
    }
    var arr = try alloc.alloc(T, len - 1);
    for (0..arr.len) |i| {
        try arr[i].read(self, alloc);
    }
    return arr;
}

pub fn readNullableArray(self: *Reader, T: type, alloc: mem.Allocator) !?[]T {
    return self.readArray(self, T, alloc) catch |err| {
        if (err == error.NullArray) {
            return null;
        }
        return err;
    };
}

pub fn readCompactNullableArray(self: *Reader, T: type, alloc: mem.Allocator) !?[]T {
    return self.readCompactArray(self, T, alloc) catch |err| {
        if (err == error.NullArray) {
            return null;
        }
        return err;
    };
}

pub fn readNullableStruct(self: *Reader, T: type, alloc: mem.Allocator) !?T {
    const byte = try self.readInt(u8);
    if (byte == -1) {
        return null;
    }
    if (byte == 1) {
        var result: T = undefined;
        try result.read(self, alloc);
        return result;
    }
    return error.UnexpectedByte;
}

test "readCompactArray" {
    const readable = struct {
        f1: i16,
        f2: i8,
        fn read(self: *@This(), reader: *Reader, _: std.mem.Allocator) !void {
            self.f1 = try reader.readInt(i16);
            self.f2 = try reader.readInt(i8);
        }
    };

    const table = .{
        .{ .in = [_]u8{0x00}, .expect = [_]readable{}, .expectError = @as(?anyerror, error.NullArray) },
        .{ .in = [_]u8{0x01}, .expect = [_]readable{}, .expectError = null },
        .{ .in = [_]u8{ 0x02, 0x00, 0x01, 0x02 }, .expect = [_]readable{
            .{ .f1 = 1, .f2 = 2 },
        }, .expectError = null },
        .{ .in = [_]u8{ 0x03, 0x72, 0xA1, 0x71, 0x63, 0xC6, 0x62 }, .expect = [_]readable{
            .{ .f1 = 0x72A1, .f2 = 0x71 },
            .{ .f1 = 0x63C6, .f2 = 0x62 },
        }, .expectError = null },
    };

    inline for (table) |case| {
        var src = case.in;
        var reader: Reader = .{ .src = &src };

        if (case.expectError) |err| {
            try std.testing.expectError(err, reader.readCompactArray(readable, std.testing.allocator));
        } else {
            const got = try reader.readCompactArray(readable, std.testing.allocator);
            defer std.testing.allocator.free(got);
            var expect = case.expect;
            try std.testing.expectEqualDeep(&expect, got);
        }
    }
}

test "readUvarint" {
    const table = .{
        .{ .input = [_]u8{0x00}, .expect = 0 },
        .{ .input = [_]u8{0x01}, .expect = 1 },
        .{ .input = [_]u8{0x02}, .expect = 2 },
        .{ .input = [_]u8{0x03}, .expect = 3 },
        .{ .input = [_]u8{0x7D}, .expect = 125 },
        .{ .input = [_]u8{0x7E}, .expect = 126 },
        .{ .input = [_]u8{0x7F}, .expect = 127 },
        .{ .input = [_]u8{ 0x80, 0x01 }, .expect = 128 },
        .{ .input = [_]u8{ 0x81, 0x01 }, .expect = 129 },
        .{ .input = [_]u8{ 0x82, 0x01 }, .expect = 130 },
        .{ .input = [_]u8{ 0xFF, 0x7F }, .expect = 16383 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x01 }, .expect = 16384 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x01 }, .expect = 16385 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x01 }, .expect = 16386 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0x7F }, .expect = 2097149 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0x7F }, .expect = 2097150 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0x7F }, .expect = 2097151 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x01 }, .expect = 2097152 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x01 }, .expect = 2097153 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x01 }, .expect = 2097154 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0x7F }, .expect = 268435453 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0x7F }, .expect = 268435454 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 268435455 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 268435456 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x01 }, .expect = 268435457 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x01 }, .expect = 268435458 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = 4294967293 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = 4294967294 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = 4294967295 },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        try std.testing.expectEqual(case.expect, try reader.readUvarint());
        try std.testing.expectEqual(0, reader.src.len);
    }
}

test "readUvarint:overflow" {
    var in = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x1F };
    var reader: Reader = .{ .src = &in };
    try std.testing.expectError(error.Overflow, reader.readUvarint());
}

test "readUvarint:eof" {
    const table = .{
        .{ .input = [_]u8{0x80} },
        .{ .input = [_]u8{ 0x80, 0x80 } },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80 } },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80 } },
    };

    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        try std.testing.expectError(error.UnexpectedEOF, reader.readUvarint());
    }
}

test "readUvarlong" {
    const table = .{
        // same as varint
        .{ .input = [_]u8{0x00}, .expect = 0 },
        .{ .input = [_]u8{0x01}, .expect = 1 },
        .{ .input = [_]u8{0x02}, .expect = 2 },
        .{ .input = [_]u8{0x03}, .expect = 3 },
        .{ .input = [_]u8{0x7D}, .expect = 125 },
        .{ .input = [_]u8{0x7E}, .expect = 126 },
        .{ .input = [_]u8{0x7F}, .expect = 127 },
        .{ .input = [_]u8{ 0x80, 0x01 }, .expect = 128 },
        .{ .input = [_]u8{ 0x81, 0x01 }, .expect = 129 },
        .{ .input = [_]u8{ 0x82, 0x01 }, .expect = 130 },
        .{ .input = [_]u8{ 0xFF, 0x7F }, .expect = 16383 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x01 }, .expect = 16384 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x01 }, .expect = 16385 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x01 }, .expect = 16386 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0x7F }, .expect = 2097149 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0x7F }, .expect = 2097150 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0x7F }, .expect = 2097151 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x01 }, .expect = 2097152 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x01 }, .expect = 2097153 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x01 }, .expect = 2097154 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0x7F }, .expect = 268435453 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0x7F }, .expect = 268435454 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 268435455 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 268435456 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x01 }, .expect = 268435457 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x01 }, .expect = 268435458 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = 4294967293 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = 4294967294 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = 4294967295 },
        // varlong
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 34359738365 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 34359738366 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 34359738367 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 34359738368 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 34359738369 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 34359738370 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 4398046511101 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 4398046511102 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 4398046511103 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 4398046511104 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 4398046511105 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 4398046511106 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 562949953421309 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 562949953421310 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 562949953421311 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 562949953421312 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 562949953421313 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 562949953421314 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 72057594037927933 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 72057594037927934 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 72057594037927935 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 72057594037927936 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 72057594037927937 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 72057594037927938 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 9223372036854775805 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 9223372036854775806 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 9223372036854775807 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 9223372036854775808 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 9223372036854775809 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 9223372036854775810 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01 }, .expect = 18446744073709551613 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01 }, .expect = 18446744073709551614 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01 }, .expect = 18446744073709551615 },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        try std.testing.expectEqual(case.expect, try reader.readUvarlong());
        try std.testing.expectEqual(0, reader.src.len);
    }
}

test "readUvarlong:overflow" {
    var in = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 };
    var reader: Reader = .{ .src = &in };
    try std.testing.expectError(error.Overflow, reader.readUvarlong());
}

test "readUvarlong:eof" {
    const table = .{
        .{ .input = [_]u8{0x80} },
        .{ .input = [_]u8{ 0x80, 0x80 } },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80 } },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80 } },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 } },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 } },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 } },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 } },
    };

    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        try std.testing.expectError(error.UnexpectedEOF, reader.readUvarlong());
    }
}

test "readVarint" {
    const table = .{
        .{ .input = [_]u8{0x00}, .expect = 0 },
        .{ .input = [_]u8{0x01}, .expect = -1 },
        .{ .input = [_]u8{0x02}, .expect = 1 },
        .{ .input = [_]u8{0x03}, .expect = -2 },
        .{ .input = [_]u8{0x04}, .expect = 2 },
        .{ .input = [_]u8{0x7D}, .expect = -63 },
        .{ .input = [_]u8{0x7E}, .expect = 63 },
        .{ .input = [_]u8{0x7F}, .expect = -64 },
        .{ .input = [_]u8{ 0x80, 0x01 }, .expect = 64 },
        .{ .input = [_]u8{ 0x81, 0x01 }, .expect = -65 },
        .{ .input = [_]u8{ 0x82, 0x01 }, .expect = 65 },
        .{ .input = [_]u8{ 0xFD, 0x01 }, .expect = -127 },
        .{ .input = [_]u8{ 0xFE, 0x01 }, .expect = 127 },
        .{ .input = [_]u8{ 0xFF, 0x01 }, .expect = -128 },
        .{ .input = [_]u8{ 0x80, 0x02 }, .expect = 128 },
        .{ .input = [_]u8{ 0x81, 0x02 }, .expect = -129 },
        .{ .input = [_]u8{ 0x82, 0x02 }, .expect = 129 },
        .{ .input = [_]u8{ 0xFD, 0x7F }, .expect = -8191 },
        .{ .input = [_]u8{ 0xFE, 0x7F }, .expect = 8191 },
        .{ .input = [_]u8{ 0xFF, 0x7F }, .expect = -8192 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x01 }, .expect = 8192 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x01 }, .expect = -8193 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x01 }, .expect = 8193 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0x7F }, .expect = -1048575 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0x7F }, .expect = 1048575 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0x7F }, .expect = -1048576 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x01 }, .expect = 1048576 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x01 }, .expect = -1048577 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x01 }, .expect = 1048577 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0x7F }, .expect = -134217727 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0x7F }, .expect = 134217727 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -134217728 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 134217728 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x01 }, .expect = -134217729 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x01 }, .expect = 134217729 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = -2147483647 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = 2147483647 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x0F }, .expect = -2147483648 },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        try std.testing.expectEqual(case.expect, try reader.readVarint());
        try std.testing.expectEqual(0, reader.src.len);
    }
}

test "readVarlong" {
    const table = .{
        .{ .input = [_]u8{0x00}, .expect = 0 },
        .{ .input = [_]u8{0x01}, .expect = -1 },
        .{ .input = [_]u8{0x02}, .expect = 1 },
        .{ .input = [_]u8{0x03}, .expect = -2 },
        .{ .input = [_]u8{0x04}, .expect = 2 },
        .{ .input = [_]u8{0x7D}, .expect = -63 },
        .{ .input = [_]u8{0x7E}, .expect = 63 },
        .{ .input = [_]u8{0x7F}, .expect = -64 },
        .{ .input = [_]u8{ 0x80, 0x01 }, .expect = 64 },
        .{ .input = [_]u8{ 0x81, 0x01 }, .expect = -65 },
        .{ .input = [_]u8{ 0x82, 0x01 }, .expect = 65 },
        .{ .input = [_]u8{ 0xFD, 0x01 }, .expect = -127 },
        .{ .input = [_]u8{ 0xFE, 0x01 }, .expect = 127 },
        .{ .input = [_]u8{ 0xFF, 0x01 }, .expect = -128 },
        .{ .input = [_]u8{ 0x80, 0x02 }, .expect = 128 },
        .{ .input = [_]u8{ 0x81, 0x02 }, .expect = -129 },
        .{ .input = [_]u8{ 0x82, 0x02 }, .expect = 129 },
        .{ .input = [_]u8{ 0xFD, 0x7F }, .expect = -8191 },
        .{ .input = [_]u8{ 0xFE, 0x7F }, .expect = 8191 },
        .{ .input = [_]u8{ 0xFF, 0x7F }, .expect = -8192 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x01 }, .expect = 8192 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x01 }, .expect = -8193 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x01 }, .expect = 8193 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0x7F }, .expect = -1048575 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0x7F }, .expect = 1048575 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0x7F }, .expect = -1048576 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x01 }, .expect = 1048576 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x01 }, .expect = -1048577 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x01 }, .expect = 1048577 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0x7F }, .expect = -134217727 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0x7F }, .expect = 134217727 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -134217728 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 134217728 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x01 }, .expect = -134217729 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x01 }, .expect = 134217729 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -17179869183 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 17179869183 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -17179869184 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 17179869184 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = -17179869185 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 17179869185 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -2199023255551 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 2199023255551 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -2199023255552 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 2199023255552 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = -2199023255553 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 2199023255553 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -281474976710655 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 281474976710655 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -281474976710656 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 281474976710656 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = -281474976710657 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 281474976710657 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -36028797018963967 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 36028797018963967 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -36028797018963968 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 36028797018963968 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = -36028797018963969 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 36028797018963969 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -4611686018427387903 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = 4611686018427387903 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }, .expect = -4611686018427387904 },
        .{ .input = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 4611686018427387904 },
        .{ .input = [_]u8{ 0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = -4611686018427387905 },
        .{ .input = [_]u8{ 0x82, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }, .expect = 4611686018427387905 },
        .{ .input = [_]u8{ 0xFD, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01 }, .expect = -9223372036854775807 },
        .{ .input = [_]u8{ 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01 }, .expect = 9223372036854775807 },
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01 }, .expect = -9223372036854775808 },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        try std.testing.expectEqual(case.expect, try reader.readVarlong());
        try std.testing.expectEqual(0, reader.src.len);
    }
}

test "readString" {
    const table = .{
        .{ .input = [_]u8{ 0xff, 0xff }, .expect = "", .expect_error = @as(?anyerror, error.NullString) },
        .{ .input = [_]u8{ 0x00, 0x01 }, .expect = "", .expect_error = @as(?anyerror, error.UnexpectedEOF) },
        .{ .input = [_]u8{ 0x00, 0x01, 'a' }, .expect = "a", .expect_error = null },
        .{ .input = [_]u8{ 0x00, 0x02, 'a', 'b' }, .expect = "ab", .expect_error = null },
        .{ .input = [_]u8{ 0x73, 0x81 } ++ [_]u8{'a'} ** 0x7381, .expect = "a" ** 0x7381, .expect_error = null },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readString(std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            try std.testing.expectEqual(0, reader.src.len);
            const str = try got;
            defer std.testing.allocator.free(str);
            try std.testing.expectEqualStrings(case.expect, str);
        }
    }
}

test "readCompactString" {
    const table = .{
        .{ .input = [_]u8{0x00}, .expect = "", .expect_error = @as(?anyerror, error.NullString) },
        .{ .input = [_]u8{0x02}, .expect = "", .expect_error = @as(?anyerror, error.UnexpectedEOF) },
        .{ .input = [_]u8{0x01}, .expect = "", .expect_error = null },
        .{ .input = [_]u8{ 0x02, 'a' }, .expect = "a", .expect_error = null },
        .{ .input = [_]u8{ 0x03, 'a', 'b' }, .expect = "ab", .expect_error = null },
        .{ .input = [_]u8{0x72} ++ [_]u8{'a'} ** 0x71, .expect = "a" ** 0x71, .expect_error = null },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readCompactString(std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            try std.testing.expectEqual(0, reader.src.len);
            const str = try got;
            defer std.testing.allocator.free(str);
            try std.testing.expectEqualStrings(case.expect, str);
        }
    }
}

test "readNullableString" {
    const table = .{
        .{ .input = [_]u8{ 0xff, 0xff }, .expect = @as(?[]const u8, null), .expect_error = null },
        .{ .input = [_]u8{ 0x00, 0x01 }, .expect = @as(?[]const u8, ""), .expect_error = @as(?anyerror, error.UnexpectedEOF) },
        .{ .input = [_]u8{ 0x00, 0x01, 'a' }, .expect = @as(?[]const u8, "a"), .expect_error = null },
        .{ .input = [_]u8{ 0x00, 0x02, 'a', 'b' }, .expect = @as(?[]const u8, "ab"), .expect_error = null },
        .{ .input = [_]u8{ 0x73, 0x81 } ++ [_]u8{'a'} ** 0x7381, .expect = @as(?[]const u8, "a" ** 0x7381), .expect_error = null },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readNullableString(std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            try std.testing.expectEqual(0, reader.src.len);
            const nullableStr = try got;
            if (nullableStr) |str| {
                defer std.testing.allocator.free(str);
                try std.testing.expectEqualStrings(case.expect.?, str);
            } else {
                try std.testing.expect(case.expect == null);
            }
        }
    }
}

test "readCompactNullableString" {
    const table = .{
        .{ .input = [_]u8{0x00}, .expect = @as(?[]const u8, null), .expect_error = null },
        .{ .input = [_]u8{0x02}, .expect = @as(?[]const u8, ""), .expect_error = @as(?anyerror, error.UnexpectedEOF) },
        .{ .input = [_]u8{0x01}, .expect = @as(?[]const u8, ""), .expect_error = null },
        .{ .input = [_]u8{ 0x02, 'a' }, .expect = @as(?[]const u8, "a"), .expect_error = null },
        .{ .input = [_]u8{ 0x03, 'a', 'b' }, .expect = @as(?[]const u8, "ab"), .expect_error = null },
        .{ .input = [_]u8{0x72} ++ [_]u8{'a'} ** 0x71, .expect = @as(?[]const u8, "a" ** 0x71), .expect_error = null },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readCompactNullableString(std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            try std.testing.expectEqual(0, reader.src.len);
            const nullableStr = try got;
            if (nullableStr) |str| {
                defer std.testing.allocator.free(str);
                try std.testing.expectEqualStrings(case.expect.?, str);
            } else {
                try std.testing.expect(case.expect == null);
            }
        }
    }
}

test "readBytes" {
    const table = .{
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, .expect = &.{}, .expect_error = @as(?anyerror, error.NullBytes) },
        .{ .input = [_]u8{ 0x00, 0x00, 0x00, 0x01 }, .expect = &.{}, .expect_error = @as(?anyerror, error.UnexpectedEOF) },
        .{ .input = [_]u8{ 0x00, 0x00, 0x00, 0x00 }, .expect = [_]u8{}, .expect_error = null },
        .{ .input = [_]u8{ 0x00, 0x00, 0x00, 0x01, 0xF2 }, .expect = [_]u8{0xF2}, .expect_error = null },
        .{ .input = [_]u8{ 0x00, 0x00, 0x00, 0x02, 0xF2, 0x31 }, .expect = [_]u8{ 0xF2, 0x31 }, .expect_error = null },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readBytes(std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            try std.testing.expectEqual(0, reader.src.len);
            const bytes = try got;
            defer std.testing.allocator.free(bytes);
            var expect = case.expect;
            try std.testing.expectEqualSlices(u8, &expect, bytes);
        }
    }
}

test "readCompactBytes" {
    const table = .{
        .{ .input = [_]u8{0x00}, .expect = &.{}, .expect_error = @as(?anyerror, error.NullBytes) },
        .{ .input = [_]u8{0x02}, .expect = &.{}, .expect_error = @as(?anyerror, error.UnexpectedEOF) },
        .{ .input = [_]u8{0x01}, .expect = [_]u8{}, .expect_error = null },
        .{ .input = [_]u8{ 0x02, 0xF2 }, .expect = [_]u8{0xF2}, .expect_error = null },
        .{ .input = [_]u8{ 0x03, 0xF2, 0x31 }, .expect = [_]u8{ 0xF2, 0x31 }, .expect_error = null },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readCompactBytes(std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            try std.testing.expectEqual(0, reader.src.len);
            const bytes = try got;
            defer std.testing.allocator.free(bytes);
            var expect = case.expect;
            try std.testing.expectEqualSlices(u8, &expect, bytes);
        }
    }
}

test "readNullableBytes" {
    const table = .{
        .{ .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF }, .expect = @as(?[]u8, null), .expect_error = null },
        .{ .input = [_]u8{ 0x00, 0x00, 0x00, 0x01 }, .expect = &.{}, .expect_error = @as(?anyerror, error.UnexpectedEOF) },
        .{ .input = [_]u8{ 0x00, 0x00, 0x00, 0x00 }, .expect = @as(?[0]u8, [0]u8{}), .expect_error = null },
        .{ .input = [_]u8{ 0x00, 0x00, 0x00, 0x01, 0xF2 }, .expect = @as(?[1]u8, [_]u8{0xF2}), .expect_error = null },
        .{ .input = [_]u8{ 0x00, 0x00, 0x00, 0x02, 0xF2, 0x31 }, .expect = @as(?[2]u8, [_]u8{ 0xF2, 0x31 }), .expect_error = null },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readNullableBytes(std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            try std.testing.expectEqual(0, reader.src.len);
            const nullableBytes = try got;
            if (nullableBytes) |bytes| {
                defer std.testing.allocator.free(bytes);
                var expect = case.expect.?;
                try std.testing.expectEqualSlices(u8, &expect, bytes);
            } else {
                try std.testing.expect(case.expect == null);
            }
        }
    }
}

test "readCompactNullableBytes" {
    const table = .{
        .{ .input = [_]u8{0x00}, .expect = @as(?[]u8, null), .expect_error = null },
        .{ .input = [_]u8{0x02}, .expect = @as(?[]u8, null), .expect_error = @as(?anyerror, error.UnexpectedEOF) },
        .{ .input = [_]u8{0x01}, .expect = @as(?[0]u8, [_]u8{}), .expect_error = null },
        .{ .input = [_]u8{ 0x02, 0xF2 }, .expect = @as(?[1]u8, [_]u8{0xF2}), .expect_error = null },
        .{ .input = [_]u8{ 0x03, 0xF2, 0x31 }, .expect = @as(?[2]u8, [_]u8{ 0xF2, 0x31 }), .expect_error = null },
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readCompactNullableBytes(std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            try std.testing.expectEqual(0, reader.src.len);
            const nullableBytes = try got;
            if (nullableBytes) |bytes| {
                defer std.testing.allocator.free(bytes);
                var expect = case.expect.?;
                try std.testing.expectEqualSlices(u8, &expect, bytes);
            } else {
                try std.testing.expect(case.expect == null);
            }
        }
    }
}

test "readArray" {
    const mock = struct {
        foo: i16,
        bar: i8,
        fn read(_: *@This(), _: *Reader, _: mem.Allocator) !void {

        }
    };
    const table = .{
        .{ .input = [_]u8{0xFF, 0xFF, 0xFF, 0xFF}, .expect = [_]mock{}, .expect_error = @as(?anyerror, error.NullArray)},
    };
    inline for (table) |case| {
        var in = case.input;
        var reader: Reader = .{ .src = &in };
        const got = reader.readArray(mock, std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            const arr = try got;
            defer std.testing.allocator.free(arr);
            var expect = case.expect;
            try std.testing.expectEqualSlices(mock, &expect, arr);
        }
    }
}

test "readFloat64" {
    var in = [_]u8{ 0x3F, 0xF7, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33 };
    var reader: Reader = .{ .src = &in };

    const got = try reader.readFloat64();
    try std.testing.expectEqual(1.45, got);
}

test "readUuid" {
    var in = [_]u8{ 0x45, 0x0c, 0xfe, 0xbc, 0x51, 0xe1, 0x4c, 0x7b, 0x7a, 0x25, 0xe4, 0x33, 0x0e, 0xc5, 0x5e, 0x5d };
    var x: Reader = .{ .src = &in };
    const got = try x.readUuid();
    try std.testing.expectEqualDeep(&in, &got);
}
