const std = @import("std");

const Writer = @import("Writer.zig");

const mem = std.mem;

const InitProducerIdResponse = @This();

throttle_time_ms: i32,
error_code: i16,
producer_id: i64 = -1,
producer_epoch: i16,

pub fn write(self: InitProducerIdResponse, alloc: mem.Allocator, writer: *Writer) !void {
    try writer.writeInt(alloc, @TypeOf(self.throttle_time_ms), self.throttle_time_ms);
    try writer.writeInt(alloc, @TypeOf(self.error_code), self.error_code);
    try writer.writeInt(alloc, @TypeOf(self.producer_id), self.producer_id);
    try writer.writeInt(alloc, @TypeOf(self.producer_epoch), self.producer_epoch);
    try writer.writeUvarint(alloc, 0);
}
