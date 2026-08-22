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

pub fn readVarint(self: *Reader) !i32 {
    const x = try self.readUvarint();
    return @bitCast((x >> 1) ^ -%(x & 1));
}

pub fn readVarlong(self: *Reader) !i64 {
    const x = try self.readUvarlong();
    return @bitCast((x >> 1) ^ -%(x & 1));
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

pub fn readCompactBytes(self: *Reader, alloc: mem.Allocator) ![]u8 {
    const len = try self.readUvarint();
    const ret = try alloc.dupe(u8, self.src[0..len]);
    self.src = self.src[len..];
    return ret;
}

pub fn readCompactArrayOf(self: *Reader, T: type, alloc: mem.Allocator) ![]T {
    const len = try self.readUvarint();
    if (len == 0) {
        return error.UnexpectedNullArray;
    }
    if (len == 1) {
        return &.{};
    }
    const x = try alloc.alloc(T, len - 1);
    for (0..len - 1) |i| {
        var y: T = undefined;
        try y.read(self, alloc);
        x[i] = y;
    }
    return x;
}

test "readCompactArrayOf" {
    const readable = struct {
        f1: i16,
        f2: i8,
        fn read(self: *@This(), reader: *Reader, _: std.mem.Allocator) !void {
            self.f1 = try reader.readInt(i16);
            self.f2 = try reader.readInt(i8);
        }
    };

    const table = .{
        .{ .in = [_]u8{0x00}, .expect = [_]readable{}, .expectError = @as(?anyerror, error.UnexpectedNullArray) },
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
            try std.testing.expectError(err, reader.readCompactArrayOf(readable, std.testing.allocator));
        } else {
            const got = try reader.readCompactArrayOf(readable, std.testing.allocator);
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
