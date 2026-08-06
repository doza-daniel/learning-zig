const std = @import("std");

const Reader = @import("Reader.zig");

const mem = std.mem;

const ApiVersionsRequest = @This();

client_software_name: []const u8 = "",
client_software_version: []const u8 = "",

pub fn read(self: *ApiVersionsRequest, reader: *Reader, alloc: mem.Allocator) !void {
    self.client_software_name = try reader.readCompactString(alloc);
    self.client_software_version = try reader.readCompactString(alloc);
    if (try reader.readUvarint() > 0) {
        return error.UnexpectedTags;
    }
}

pub fn deinit(self: *ApiVersionsRequest, alloc: mem.Allocator) void {
    alloc.free(self.client_software_name);
    alloc.free(self.client_software_version);
}
