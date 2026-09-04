const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const RequestHeader = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 2) {
        return true;
    } else {
        return false;
    }
}
RequestApiKey: i16 = 0,
RequestApiVersion: i16 = 0,
CorrelationId: i32 = 0,
ClientId: ?[]const u8 = "",

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    if (self.ClientId) |val| {
        alloc.free(val);
    }
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    self.RequestApiKey = try reader.readInt(i16);
    self.RequestApiVersion = try reader.readInt(i16);
    self.CorrelationId = try reader.readInt(i32);
    if (version >= 1) {
        self.ClientId = try reader.readNullableString(alloc);
    }
    if (isFlexible(version)) {
        const num_tags = try reader.readUvarint();
        for (0..num_tags) |_| {
            const tag: u32 = try reader.readUvarint();
            const tag_len: u32 = try reader.readUvarint();
            defer reader.src = reader.src[tag_len..];
            switch (tag) {
                else => unreachable,
            }
        }
    }
}
