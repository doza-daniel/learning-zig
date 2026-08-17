const std = @import("std");

const Reader = @import("Reader.zig");

const mem = std.mem;

const MetadataRequest = @This();

const MetadataRequestTopic = struct {
    id: [16]u8,
    name: []const u8,

    fn deinit(self: MetadataRequestTopic, alloc: mem.Allocator) void {
        alloc.free(self.name);
    }
};

version: i16,

topics: []MetadataRequestTopic = undefined,
allow_auto_topic_creation: bool = false,
include_cluster_authorized_operations: bool = false,
include_topic_authorized_operations: bool = false,

pub fn read(self: *MetadataRequest, reader: *Reader, alloc: mem.Allocator) !void {
    self.topics = &[_]MetadataRequestTopic{};
    var num_topics: u32 = 0;
    if (self.isFlexible()) {
        num_topics = try reader.readUvarint();
    } else {
        num_topics = try reader.readInt(u32) + 1;
    }
    if (num_topics > 1) {
         try self.readTopics(alloc, reader, num_topics - 1);
    }
    if (self.version >= 4) {
        self.allow_auto_topic_creation = try reader.readBool();
    }
    if (self.version >= 8 and self.version <= 10) {
        self.include_cluster_authorized_operations = try reader.readBool();
    }
    if (self.version >= 8) {
        self.include_topic_authorized_operations = try reader.readBool();
    }
}

fn readTopics(self: *MetadataRequest, alloc: mem.Allocator, reader: *Reader, n: u32) !void {
    self.topics = try alloc.alloc(MetadataRequestTopic, n);
    for (0..n) |i| {
        var id = [_]u8{0} ** 16;
        var name: []const u8 = undefined;
        if (self.version >= 10) {
            id = try reader.readUuid();
        }
        if (self.isFlexible()) {
            name = try reader.readCompactString(alloc);
        } else {
            name = (try reader.readNullableString(alloc)).?;
        }
        self.topics[i] = .{
            .id = id,
            .name = name,
        };
        try self.parseUnusedTags(reader);
    }
}

fn parseUnusedTags(self: *MetadataRequest, reader: *Reader) !void {
    if (!self.isFlexible()) {
        return;
    }
    const num_tags = try reader.readUvarint();
    if (num_tags > 0) {
        return error.UnsupportedTags;
    }
}

pub fn deinit(self: MetadataRequest, alloc: mem.Allocator) void {
    for (self.topics) |topic| {
        topic.deinit(alloc);
    }
    alloc.free(self.topics);
}

pub fn isFlexible(self: MetadataRequest) bool {
    return self.version >= 9;
}
