const std = @import("std");

const mem = std.mem;

const Writer = @This();

buf: std.ArrayList(u8) = .empty,

pub fn writeBool(self: *Writer, alloc: mem.Allocator, val: bool) !void {
    try self.buf.append(alloc, if (val) 1 else 0);
}

pub fn writeInt(self: *Writer, alloc: mem.Allocator, comptime T: type, val: T) !void {
    var buffer: [@sizeOf(T)]u8 = undefined;
    mem.writeInt(T, &buffer, val, .big);
    try self.buf.appendSlice(alloc, &buffer);
}

pub fn writeVarint(self: *Writer, alloc: mem.Allocator, val: i32) !void {
    try self.writeUvarint(alloc, @as(u32, @bitCast(val << 1 ^ val >> 31)));
}

pub fn writeVarlong(self: *Writer, alloc: mem.Allocator, val: i64) !void {
    const x = @as(u64, @bitCast(val << 1 ^ val >> 63));
    try self.writeUvarlong(alloc, x);
}

pub fn writeUvarint(self: *Writer, alloc: mem.Allocator, val: u32) !void {
    var buf: [5]u8 = undefined;
    var tmp = val;
    comptime var i = 0;
    inline while (i < buf.len) {
        buf[i] = @as(u8, @truncate(tmp)) & 0x7F; // take first 7 bits
        if (i > 0) {
            buf[i - 1] |= 0x80; // set continuation bit
        }
        tmp >>= 7;
        i += 1;
        if (tmp == 0) {
            try self.buf.appendSlice(alloc, buf[0..i]);
            return;
        }
    }
}

pub fn writeUvarlong(self: *Writer, alloc: mem.Allocator, val: u64) !void {
    var buf: [10]u8 = undefined;
    var tmp = val;
    comptime var i = 0;
    inline while (i < buf.len) {
        buf[i] = @as(u8, @truncate(tmp)) & 0x7F;
        if (i > 0) {
            buf[i - 1] |= 0x80;
        }
        tmp >>= 7;
        i += 1;
        if (tmp == 0) {
            try self.buf.appendSlice(alloc, buf[0..i]);
            return;
        }
    }
}

pub fn writeUuid(self: *Writer, alloc: mem.Allocator, val: [16]u8) !void {
    try self.buf.appendSlice(alloc, &val);
}

pub fn writeFloat64(self: *Writer, alloc: mem.Allocator, val: f64) !void {
    try self.writeInt(alloc, u64, @bitCast(val));
}

pub fn writeString(self: *Writer, alloc: mem.Allocator, val: []const u8) !void {
    try self.writeInt(alloc, i16, @intCast(val.len));
    try self.buf.appendSlice(alloc, val);
}

pub fn writeCompactString(self: *Writer, alloc: mem.Allocator, val: []const u8) !void {
    try self.writeUvarint(alloc, @intCast(val.len + 1));
    try self.buf.appendSlice(alloc, val);
}

pub fn writeNullableString(self: *Writer, alloc: mem.Allocator, val: ?[]const u8) !void {
    if (val) |str| {
        try self.writeString(alloc, str);
    } else {
        try self.writeInt(alloc, i16, -1);
    }
}

pub fn writeCompactNullableString(self: *Writer, alloc: mem.Allocator, val: ?[]const u8) !void {
    if (val) |str| {
        try self.writeCompactString(alloc, str);
    } else {
        try self.writeUvarint(alloc, 0);
    }
}

pub fn writeBytes(self: *Writer, alloc: mem.Allocator, val: []const u8) !void {
    try self.writeInt(alloc, i32, @intCast(val.len));
    try self.buf.appendSlice(alloc, val);
}

pub fn writeCompactBytes(self: *Writer, alloc: mem.Allocator, val: []const u8) !void {
    try self.writeUvarint(alloc, @intCast(val.len + 1));
    try self.buf.appendSlice(alloc, val);
}

pub fn writeNullableBytes(self: *Writer, alloc: mem.Allocator, val: ?[]const u8) !void {
    if (val) |bs| {
        try self.writeBytes(alloc, bs);
    } else {
        try self.writeInt(alloc, i32, -1);
    }
}

pub fn writeCompactNullableBytes(self: *Writer, alloc: mem.Allocator, val: ?[]const u8) !void {
    if (val) |bs| {
        try self.writeCompactBytes(alloc, bs);
    } else {
        try self.writeUvarint(alloc, 0);
    }
}

pub fn writeArray(self: *Writer, alloc: mem.Allocator, T: type, val: []const T, version: i16) !void {
    try self.writeInt(alloc, i32, @intCast(val.len));
    for (val) |item| {
        switch (@typeInfo(T)) {
            .int => {
                try self.writeInt(alloc, T, item);
            },
            .@"struct" => {
                try item.write(alloc, self, version);
            },
            .pointer => {
                try self.writeString(alloc, item);
            },
            else => unreachable,
        }
    }
}

pub fn writeCompactArray(self: *Writer, alloc: mem.Allocator, T: type, val: []const T, version: i16) !void {
    try self.writeUvarint(alloc, @intCast(val.len + 1));
    for (val) |item| {
        switch (@typeInfo(T)) {
            .int => {
                try self.writeInt(alloc, T, item);
            },
            .@"struct" => {
                try item.write(alloc, self, version);
            },
            .pointer => {
                try self.writeString(alloc, item);
            },
            else => unreachable,
        }
    }
}

pub fn writeNullableArray(self: *Writer, alloc: mem.Allocator, T: type, val: ?[]const T, version: i16) !void {
    if (val) |arr| {
        try self.writeArray(alloc, T, arr, version);
    } else {
        try self.writeInt(alloc, i32, -1);
    }
}

pub fn writeCompactNullableArray(self: *Writer, alloc: mem.Allocator, T: type, val: ?[]const T, version: i16) !void {
    if (val) |arr| {
        try self.writeCompactArray(alloc, T, arr, version);
    } else {
        try self.writeUvarint(alloc, 0);
    }
}

pub fn writeNullableStruct(self: *Writer, alloc: mem.Allocator, T: type, val: ?T, version: i16) !void {
    if (val) |s| {
        try self.writeInt(alloc, i8, 1);
        try s.write(alloc, self, version);
    } else {
        try self.writeInt(alloc, i8, -1);
    }
}

pub fn deinit(self: *Writer, alloc: mem.Allocator) void {
    self.buf.deinit(alloc);
}

test "writeBool" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = true, .expect = .{0x01} },
        .{ .in = false, .expect = .{0x00} },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeBool(gpa, case.in);
        try std.testing.expectEqualSlices(u8, &case.expect, w.buf.items);
    }
}

test "writeInt" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .t = u8, .in = 0x42, .expect = .{0x42} },
        .{ .t = u16, .in = 0x1234, .expect = .{ 0x12, 0x34 } },
        .{ .t = u32, .in = 0x12345678, .expect = .{ 0x12, 0x34, 0x56, 0x78 } },
        .{ .t = u64, .in = 0x123456789ABCDEF1, .expect = .{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF1 } },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeInt(gpa, case.t, case.in);
        try std.testing.expectEqualSlices(u8, &case.expect, w.buf.items);
    }
}

test "writeVarint" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = std.math.minInt(i32) },
        .{ .in = -123456 },
        .{ .in = -123457 },
        .{ .in = -2 },
        .{ .in = -1 },
        .{ .in = 0 },
        .{ .in = 1 },
        .{ .in = 2 },
        .{ .in = 123456 },
        .{ .in = 123457 },
        .{ .in = std.math.maxInt(i32) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeVarint(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        try std.testing.expectEqual(case.in, try r.readVarint());
    }
}

test "writeVarlong" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = std.math.minInt(i64) },
        .{ .in = -123456 },
        .{ .in = -123457 },
        .{ .in = -2 },
        .{ .in = -1 },
        .{ .in = 0 },
        .{ .in = 1 },
        .{ .in = 2 },
        .{ .in = 123456 },
        .{ .in = 123457 },
        .{ .in = std.math.maxInt(i64) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeVarlong(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        try std.testing.expectEqual(case.in, try r.readVarlong());
    }
}

test "writeUvarint" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = 0 },
        .{ .in = 1 },
        .{ .in = 2 },
        .{ .in = 3 },
        .{ .in = 123456 },
        .{ .in = 123457 },
        .{ .in = std.math.maxInt(u32) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeUvarint(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        try std.testing.expectEqual(case.in, try r.readUvarint());
    }
}

test "writeUvarlong" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = 0 },
        .{ .in = 1 },
        .{ .in = 2 },
        .{ .in = 3 },
        .{ .in = 123456 },
        .{ .in = 123457 },
        .{ .in = std.math.maxInt(u64) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeUvarlong(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        try std.testing.expectEqual(case.in, try r.readUvarlong());
    }
}

test "writeUuid" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = [_]u8{0} ** 16 },
        .{ .in = [16]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 } },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeUuid(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        try std.testing.expectEqual(case.in, try r.readUuid());
    }
}

test "writeFloat64" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = 0.0 },
        .{ .in = 0.1 },
        .{ .in = 1.23 },
        .{ .in = std.math.floatMax(f64) },
        .{ .in = std.math.floatMin(f64) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeFloat64(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        try std.testing.expectEqual(case.in, try r.readFloat64());
    }
}

test "writeString" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = "" },
        .{ .in = "a" },
        .{ .in = "foo" },
        .{ .in = "foobar" },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeString(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readString(gpa);
        defer gpa.free(result);
        try std.testing.expectEqualStrings(case.in, result);
    }
}

test "writeCompactString" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = "" },
        .{ .in = "a" },
        .{ .in = "foo" },
        .{ .in = "foobar" },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeCompactString(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readCompactString(gpa);
        defer gpa.free(result);
        try std.testing.expectEqualStrings(case.in, result);
    }
}

test "writeNullableString" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = @as(?[]const u8, null) },
        .{ .in = @as(?[]const u8, "foobar") },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeNullableString(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readNullableString(gpa);
        if (case.in) |str| {
            defer gpa.free(result.?);
            try std.testing.expectEqualStrings(str, result.?);
        } else {
            try std.testing.expectEqual(null, result);
        }
    }
}

test "writeCompactNullableString" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = @as(?[]const u8, null) },
        .{ .in = @as(?[]const u8, "foobar") },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeCompactNullableString(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readCompactNullableString(gpa);
        if (case.in) |str| {
            defer gpa.free(result.?);
            try std.testing.expectEqualStrings(str, result.?);
        } else {
            try std.testing.expectEqual(null, result);
        }
    }
}

test "writeBytes" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = .{} },
        .{ .in = .{0x0} },
        .{ .in = .{ 0x01, 0x02, 0x03 } },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeBytes(gpa, &case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readBytes(gpa);
        defer gpa.free(result);
        try std.testing.expectEqualSlices(u8, &case.in, result);
    }
}

test "writeCompactBytes" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = .{} },
        .{ .in = .{0x0} },
        .{ .in = .{ 0x01, 0x02, 0x03 } },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeCompactBytes(gpa, &case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readCompactBytes(gpa);
        defer gpa.free(result);
        try std.testing.expectEqualSlices(u8, &case.in, result);
    }
}

test "writeNullableBytes" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = @as(?[]const u8, null) },
        .{ .in = @as(?[]const u8, &.{ 0x01, 0x02, 0x03 }) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeNullableBytes(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readNullableBytes(gpa);
        if (case.in) |str| {
            defer gpa.free(result.?);
            try std.testing.expectEqualStrings(str, result.?);
        } else {
            try std.testing.expectEqual(null, result);
        }
    }
}

test "writeCompactNullableBytes" {
    const gpa = std.testing.allocator;

    const table = .{
        .{ .in = @as(?[]const u8, null) },
        .{ .in = @as(?[]const u8, &.{ 0x01, 0x02, 0x03 }) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeCompactNullableBytes(gpa, case.in);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readCompactNullableBytes(gpa);
        if (case.in) |str| {
            defer gpa.free(result.?);
            try std.testing.expectEqualStrings(str, result.?);
        } else {
            try std.testing.expectEqual(null, result);
        }
    }
}

test "writeArray" {
    const gpa = std.testing.allocator;

    const mock = struct {
        f: i32,
        pub fn write(self: @This(), alloc: mem.Allocator, w: *Writer, _: i16) !void {
            try w.writeInt(alloc, @TypeOf(self.f), self.f);
        }

        pub fn read(self: *@This(), r: *@import("Reader.zig"), _: mem.Allocator, _: i16) !void {
            self.f = try r.readInt(@TypeOf(self.f));
        }
    };

    const table = .{
        .{
            .t = mock,
            .in = .{
                mock{ .f = 0x12345678 },
                mock{ .f = 0x77654321 },
            },
        },
        .{ .t = i32, .in = .{ 0x12345678, 0x77654321 } },
        .{ .t = []const u8, .in = .{ "foo", "bar" } },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeArray(gpa, case.t, &case.in, 0);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readArray(case.t, gpa, 0);
        defer {
            if (case.t == []const u8) {
                for (result) |str| {
                    gpa.free(str);
                }
            }
            gpa.free(result);
        }
        try std.testing.expectEqualDeep(@as([]const case.t, &case.in), result);
    }
}

test "writeCompactArray" {
    const gpa = std.testing.allocator;

    const mock = struct {
        f: i32,
        pub fn write(self: @This(), alloc: mem.Allocator, w: *Writer, _: i16) !void {
            try w.writeInt(alloc, @TypeOf(self.f), self.f);
        }

        pub fn read(self: *@This(), r: *@import("Reader.zig"), _: mem.Allocator, _: i16) !void {
            self.f = try r.readInt(@TypeOf(self.f));
        }
    };

    const table = .{
        .{
            .t = mock,
            .in = .{
                mock{ .f = 0x12345678 },
                mock{ .f = 0x77654321 },
            },
        },
        .{ .t = i32, .in = .{ 0x12345678, 0x77654321 } },
        .{ .t = []const u8, .in = .{ "foo", "bar" } },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeCompactArray(gpa, case.t, &case.in, 0);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readCompactArray(case.t, gpa, 0);
        defer {
            if (case.t == []const u8) {
                for (result) |str| {
                    gpa.free(str);
                }
            }
            gpa.free(result);
        }
        try std.testing.expectEqualDeep(@as([]const case.t, &case.in), result);
    }
}

test "writeNullableArray" {
    const gpa = std.testing.allocator;

    const mock = struct {
        f: i32,
        pub fn write(self: @This(), alloc: mem.Allocator, w: *Writer, _: i16) !void {
            try w.writeInt(alloc, @TypeOf(self.f), self.f);
        }

        pub fn read(self: *@This(), r: *@import("Reader.zig"), _: mem.Allocator, _: i16) !void {
            self.f = try r.readInt(@TypeOf(self.f));
        }
    };

    const table = .{
        .{ .t = mock, .in = @as(?[]const mock, null) },
        .{ .t = mock, .in = @as(?[]const mock, &.{ .{ .f = 0x12345678 }, .{ .f = 0x77654321 } }) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeNullableArray(gpa, case.t, case.in, 0);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readNullableArray(case.t, gpa, 0);
        if (case.in) |e| {
            defer gpa.free(result.?);
            try std.testing.expectEqualDeep(@as([]const case.t, e), result.?);
        } else {
            try std.testing.expectEqualDeep(null, result);
        }
    }
}

test "writeCompactNullableArray" {
    const gpa = std.testing.allocator;

    const mock = struct {
        f: i32,
        pub fn write(self: @This(), alloc: mem.Allocator, w: *Writer, _: i16) !void {
            try w.writeInt(alloc, @TypeOf(self.f), self.f);
        }

        pub fn read(self: *@This(), r: *@import("Reader.zig"), _: mem.Allocator, _: i16) !void {
            self.f = try r.readInt(@TypeOf(self.f));
        }
    };

    const table = .{
        .{ .t = mock, .in = @as(?[]const mock, null) },
        .{ .t = mock, .in = @as(?[]const mock, &.{ .{ .f = 0x12345678 }, .{ .f = 0x77654321 } }) },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeCompactNullableArray(gpa, case.t, case.in, 0);
        var r: @import("Reader.zig") = .{ .src = w.buf.items };
        const result = try r.readCompactNullableArray(case.t, gpa, 0);
        if (case.in) |e| {
            defer gpa.free(result.?);
            try std.testing.expectEqualDeep(@as([]const case.t, e), result.?);
        } else {
            try std.testing.expectEqualDeep(null, result);
        }
    }
}

test "writeNullableStruct" {
    const gpa = std.testing.allocator;

    const mock = struct {
        f: i32,
        fn write(self: @This(), alloc: mem.Allocator, w: *Writer, _: i16) !void {
            try w.writeInt(alloc, @TypeOf(self.f), self.f);
        }
    };

    const table = .{
        .{ .in = null, .expect = [_]u8{0xFF} },
        .{ .in = mock{ .f = 0x12345678 }, .expect = [_]u8{ 0x01, 0x12, 0x34, 0x56, 0x78 } },
    };
    inline for (table) |case| {
        var w: Writer = .{};
        defer w.deinit(gpa);

        try w.writeNullableStruct(gpa, mock, case.in, 0);
        var expect = case.expect;
        try std.testing.expectEqualSlices(u8, &expect, w.buf.items);
    }
}
