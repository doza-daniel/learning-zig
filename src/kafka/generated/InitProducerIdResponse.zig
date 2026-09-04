const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const InitProducerIdResponse = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 2) {
        return true;
    } else {
        return false;
    }
}
ThrottleTimeMs: i32 = 0,
ErrorCode: i16 = 0,
ProducerId: i64 = -1,
ProducerEpoch: i16 = 0,
OngoingTxnProducerId: i64 = -1,
OngoingTxnProducerEpoch: i16 = -1,

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    _ = self;
    _ = alloc;
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    self.ThrottleTimeMs = try reader.readInt(i32);
    self.ErrorCode = try reader.readInt(i16);
    self.ProducerId = try reader.readInt(i64);
    self.ProducerEpoch = try reader.readInt(i16);
    if (version >= 6) {
        self.OngoingTxnProducerId = try reader.readInt(i64);
    }
    if (version >= 6) {
        self.OngoingTxnProducerEpoch = try reader.readInt(i16);
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
    _ = alloc;
}
