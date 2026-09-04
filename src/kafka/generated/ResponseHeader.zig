const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const ResponseHeader = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 1) {
        return true;
    } else {
        return false;
    }
}
CorrelationId: i32 = 0,

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    _ = self;
    _ = alloc;
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    self.CorrelationId = try reader.readInt(i32);
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
    _ = alloc;
}
