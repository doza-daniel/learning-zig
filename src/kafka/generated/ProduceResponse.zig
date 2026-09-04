const std = @import("std");
const Reader = @import("../Reader.zig");
const RecordBatch = @import("../RecordBatch.zig");
const ProduceResponse = @This();

pub fn isFlexible(version: i16) bool {
    if (version >= 9) {
        return true;
    } else {
        return false;
    }
}
Responses: []TopicProduceResponse = &.{},
ThrottleTimeMs: i32 = 0,
NodeEndpoints: []NodeEndpoint = &.{},

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    for (self.Responses) |elem| {
        elem.deinit(alloc);
    }
    alloc.free(self.Responses);
    for (self.NodeEndpoints) |elem| {
        elem.deinit(alloc);
    }
    alloc.free(self.NodeEndpoints);
}

pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
    if (isFlexible(version)) {
        self.Responses = try reader.readCompactArray(TopicProduceResponse, alloc, version);
    } else {
        self.Responses = try reader.readArray(TopicProduceResponse, alloc, version);
    }
    if (version >= 1) {
        self.ThrottleTimeMs = try reader.readInt(i32);
    }
    if (isFlexible(version)) {
        const num_tags = try reader.readUvarint();
        for (0..num_tags) |_| {
            const tag: u32 = try reader.readUvarint();
            const tag_len: u32 = try reader.readUvarint();
            defer reader.src = reader.src[tag_len..];
            switch (tag) {
                0 => {
                    var tag_reader: Reader = .{ .src = reader.src[0..tag_len] };
                    if (version >= 10) {
                        if (isFlexible(version)) {
                            self.NodeEndpoints = try tag_reader.readCompactArray(NodeEndpoint, alloc, version);
                        } else {
                            self.NodeEndpoints = try tag_reader.readArray(NodeEndpoint, alloc, version);
                        }
                    }
                },
                else => unreachable,
            }
        }
    }
}
const TopicProduceResponse = struct {
    Name: []const u8 = "",
    TopicId: [16]u8 = @as([16]u8, @splat(0)),
    PartitionResponses: []PartitionProduceResponse = &.{},

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.Name);
        for (self.PartitionResponses) |elem| {
            elem.deinit(alloc);
        }
        alloc.free(self.PartitionResponses);
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        if (version <= 12) {
            if (isFlexible(version)) {
                self.Name = try reader.readCompactString(alloc);
            } else {
                self.Name = try reader.readString(alloc);
            }
        }
        if (version >= 13) {
            self.TopicId = try reader.readUuid();
        }
        if (isFlexible(version)) {
            self.PartitionResponses = try reader.readCompactArray(PartitionProduceResponse, alloc, version);
        } else {
            self.PartitionResponses = try reader.readArray(PartitionProduceResponse, alloc, version);
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
const PartitionProduceResponse = struct {
    Index: i32 = 0,
    ErrorCode: i16 = 0,
    BaseOffset: i64 = 0,
    LogAppendTimeMs: i64 = -1,
    LogStartOffset: i64 = -1,
    RecordErrors: []BatchIndexAndErrorMessage = &.{},
    ErrorMessage: ?[]const u8 = null,
    CurrentLeader: LeaderIdAndEpoch = .{},

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        for (self.RecordErrors) |elem| {
            elem.deinit(alloc);
        }
        alloc.free(self.RecordErrors);
        if (self.ErrorMessage) |val| {
            alloc.free(val);
        }
        self.CurrentLeader.deinit(alloc);
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        self.Index = try reader.readInt(i32);
        self.ErrorCode = try reader.readInt(i16);
        self.BaseOffset = try reader.readInt(i64);
        if (version >= 2) {
            self.LogAppendTimeMs = try reader.readInt(i64);
        }
        if (version >= 5) {
            self.LogStartOffset = try reader.readInt(i64);
        }
        if (version >= 8) {
            if (isFlexible(version)) {
                self.RecordErrors = try reader.readCompactArray(BatchIndexAndErrorMessage, alloc, version);
            } else {
                self.RecordErrors = try reader.readArray(BatchIndexAndErrorMessage, alloc, version);
            }
        }
        if (version >= 8) {
            if (isFlexible(version)) {
                if (version >= 8) {
                    self.ErrorMessage = try reader.readCompactNullableString(alloc);
                } else {
                    self.ErrorMessage = try reader.readCompactString(alloc);
                }
            } else {
                if (version >= 8) {
                    self.ErrorMessage = try reader.readNullableString(alloc);
                } else {
                    self.ErrorMessage = try reader.readString(alloc);
                }
            }
        }
        if (isFlexible(version)) {
            const num_tags = try reader.readUvarint();
            for (0..num_tags) |_| {
                const tag: u32 = try reader.readUvarint();
                const tag_len: u32 = try reader.readUvarint();
                defer reader.src = reader.src[tag_len..];
                switch (tag) {
                    0 => {
                        var tag_reader: Reader = .{ .src = reader.src[0..tag_len] };
                        if (version >= 10) {
                            try self.CurrentLeader.read(&tag_reader, alloc, version);
                        }
                    },
                    else => unreachable,
                }
            }
        }
    }
};
const BatchIndexAndErrorMessage = struct {
    BatchIndex: i32 = 0,
    BatchIndexErrorMessage: ?[]const u8 = null,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        if (self.BatchIndexErrorMessage) |val| {
            alloc.free(val);
        }
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        if (version >= 8) {
            self.BatchIndex = try reader.readInt(i32);
        }
        if (version >= 8) {
            if (isFlexible(version)) {
                if (version >= 8) {
                    self.BatchIndexErrorMessage = try reader.readCompactNullableString(alloc);
                } else {
                    self.BatchIndexErrorMessage = try reader.readCompactString(alloc);
                }
            } else {
                if (version >= 8) {
                    self.BatchIndexErrorMessage = try reader.readNullableString(alloc);
                } else {
                    self.BatchIndexErrorMessage = try reader.readString(alloc);
                }
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
const LeaderIdAndEpoch = struct {
    LeaderId: i32 = -1,
    LeaderEpoch: i32 = -1,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        if (version >= 10) {
            self.LeaderId = try reader.readInt(i32);
        }
        if (version >= 10) {
            self.LeaderEpoch = try reader.readInt(i32);
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
};
const NodeEndpoint = struct {
    NodeId: i32 = 0,
    Host: []const u8 = "",
    Port: i32 = 0,
    Rack: ?[]const u8 = null,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.Host);
        if (self.Rack) |val| {
            alloc.free(val);
        }
    }

    pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator, version: i16) !void {
        if (version >= 10) {
            self.NodeId = try reader.readInt(i32);
        }
        if (version >= 10) {
            if (isFlexible(version)) {
                self.Host = try reader.readCompactString(alloc);
            } else {
                self.Host = try reader.readString(alloc);
            }
        }
        if (version >= 10) {
            self.Port = try reader.readInt(i32);
        }
        if (version >= 10) {
            if (isFlexible(version)) {
                if (version >= 10) {
                    self.Rack = try reader.readCompactNullableString(alloc);
                } else {
                    self.Rack = try reader.readCompactString(alloc);
                }
            } else {
                if (version >= 10) {
                    self.Rack = try reader.readNullableString(alloc);
                } else {
                    self.Rack = try reader.readString(alloc);
                }
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
