const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const InitProducerIdRequest = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 2) {
        return true;
    } else {
        return false;
    }
}
TransactionalId: ?[]const u8 = "",
TransactionTimeoutMs: i32 = 0,
ProducerId: i64 = -1,
ProducerEpoch: i16 = -1,
Enable2Pc: bool = false,
KeepPreparedTxn: bool = false,

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    if (self.TransactionalId) |val| {
        alloc.free(val);
    }
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    if (isFlexible(version)) {
        self.TransactionalId = try reader.readCompactNullableString(alloc);
    } else {
        self.TransactionalId = try reader.readNullableString(alloc);
    }
    self.TransactionTimeoutMs = try reader.readInt(i32);
    if (version >= 3) {
        self.ProducerId = try reader.readInt(i64);
    }
    if (version >= 3) {
        self.ProducerEpoch = try reader.readInt(i16);
    }
    if (version >= 6) {
        self.Enable2Pc = try reader.readBool();
    }
    if (version >= 6) {
        self.KeepPreparedTxn = try reader.readBool();
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
