const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const MetadataRequest = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 9) {
        return true;
    } else {
        return false;
    }
}
Topics: ?[]MetadataRequestTopic = &.{},
AllowAutoTopicCreation: bool = true,
IncludeClusterAuthorizedOperations: bool = false,
IncludeTopicAuthorizedOperations: bool = false,

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    if (self.Topics) |val| {
        for (val) |elem| {
            elem.deinit(alloc);
        }
        alloc.free(val);
    }
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    if (isFlexible(version)) {
        if (version >= 1) {
            self.Topics = try reader.readCompactNullableArray(MetadataRequestTopic, alloc, version);
        } else {
            self.Topics = try reader.readCompactArray(MetadataRequestTopic, alloc, version);
        }
    } else {
        if (version >= 1) {
            self.Topics = try reader.readNullableArray(MetadataRequestTopic, alloc, version);
        } else {
            self.Topics = try reader.readArray(MetadataRequestTopic, alloc, version);
        }
    }
    if (version >= 4) {
        self.AllowAutoTopicCreation = try reader.readBool();
    }
    if (version >= 8 and version <= 10) {
        self.IncludeClusterAuthorizedOperations = try reader.readBool();
    }
    if (version >= 8) {
        self.IncludeTopicAuthorizedOperations = try reader.readBool();
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
const MetadataRequestTopic = struct {
    TopicId: [16]u8 = @as([16]u8, @splat(0)),
    Name: ?[]const u8 = "",

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        if (self.Name) |val| {
            alloc.free(val);
        }
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        if (version >= 10) {
            self.TopicId = try reader.readUuid();
        }
        if (isFlexible(version)) {
            if (version >= 10) {
                self.Name = try reader.readCompactNullableString(alloc);
            } else {
                self.Name = try reader.readCompactString(alloc);
            }
        } else {
            if (version >= 10) {
                self.Name = try reader.readNullableString(alloc);
            } else {
                self.Name = try reader.readString(alloc);
            }
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
};
