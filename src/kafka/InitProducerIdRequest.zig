const std = @import("std");

const Reader = @import("Reader.zig");

const mem = std.mem;

const InitProducerIdRequest = @This();

version: i16,

transactional_id: ?[]const u8,
transaction_timeout_ms: i32,
producer_id: i64 = -1,
producer_epoch: i16 = -1,

pub fn read(self: *InitProducerIdRequest, reader: *Reader, alloc: mem.Allocator) !void {
    if (self.isFlexible()) {
        self.transactional_id = try reader.readCompactString(alloc);
    } else {
        self.transactional_id = try reader.readNullableString(alloc);
    }
    self.transaction_timeout_ms = try reader.readInt(i32);
    if (self.version >= 3) {
        self.producer_id = try reader.readInt(i64);
        self.producer_epoch = try reader.readInt(i16);
    }
}

pub fn isFlexible(self: InitProducerIdRequest) bool {
    return self.version >= 2;
}
