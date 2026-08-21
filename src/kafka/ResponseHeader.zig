const std = @import("std");

const mem = std.mem;

const Writer = @import("Writer.zig");

const ResponseHeader = @This();

correlation_id: i32,

pub fn write(self: ResponseHeader, alloc: mem.Allocator, writer: *Writer) !void {
    try writer.writeInt(alloc, @TypeOf(self.correlation_id), self.correlation_id);
}
