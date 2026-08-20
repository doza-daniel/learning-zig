const std = @import("std");

const mem = std.mem;

const Writer = @import("Writer.zig");
const ProduceResponse = @This();

pub const NodeEndpoint = struct {
    node_id: i32,
    host: []const u8,
    port: i32,
    rack: ?[]const u8 = null,

    pub fn write(self: NodeEndpoint, alloc: std.mem.Allocator, writer: *Writer, version: i16) !void {
        if (version < 10) {
            return;
        }
        try writer.writeInt(alloc, @TypeOf(self.node_id), self.node_id);
        try writer.writeCompactString(alloc, self.host);
        try writer.writeInt(alloc, @TypeOf(self.port), self.port);
        try writer.writeCompactNullableString(alloc, self.rack);
        if (isFlexible(version)) {
            try writer.writeUvarint(alloc, 0);
        }
    }
};

pub const BatchIndexAndErrorMessage = struct {
    batch_index: i32,
    batch_index_error_message: ?[]const u8 = null,

    pub fn write(self: BatchIndexAndErrorMessage, alloc: std.mem.Allocator, writer: *Writer, version: i16) !void {
        if (version < 8) {
            return;
        }
        try writer.writeInt(alloc, @TypeOf(self.batch_index), self.batch_index);
        try writer.writeCompactNullableString(alloc, self.batch_index_error_message);
        if (isFlexible(version)) {
            try writer.writeUvarint(alloc, 0);
        }
    }
};

pub const LeaderIdAndEpoch = struct {
    leader_id: i32 = -1,
    leader_epoch: i32 = -1,

    pub fn write(self: LeaderIdAndEpoch, alloc: std.mem.Allocator, writer: *Writer, version: i16) !void {
        if (version < 10) {
            return;
        }
        try writer.writeInt(alloc, @TypeOf(self.leader_id), self.leader_id);
        try writer.writeInt(alloc, @TypeOf(self.leader_epoch), self.leader_epoch);
        if (isFlexible(version)) {
            try writer.writeUvarint(alloc, 0);
        }
    }
};

pub const PartitionProduceResponse = struct {
    index: i32,
    error_code: i16,
    base_offset: i64,
    log_append_time_ms: i64 = -1,
    log_start_offset: i64 = -1,
    record_errors: []BatchIndexAndErrorMessage = &.{},
    error_message: ?[]const u8 = null,
    current_leader: LeaderIdAndEpoch = .{}, // TODO this is marked as tag 0, figure out how to properly serialize

    pub fn write(self: PartitionProduceResponse, alloc: std.mem.Allocator, writer: *Writer, version: i16) !void {
        try writer.writeInt(alloc, @TypeOf(self.index), self.index);
        try writer.writeInt(alloc, @TypeOf(self.error_code), self.error_code);
        try writer.writeInt(alloc, @TypeOf(self.base_offset), self.base_offset);
        if (version >= 2) {
            try writer.writeInt(alloc, @TypeOf(self.log_append_time_ms), self.log_append_time_ms);
        }
        if (version >= 5) {
            try writer.writeInt(alloc, @TypeOf(self.log_start_offset), self.log_start_offset);
        }

        if (version >= 8) {
            try writer.writeUvarint(alloc, @intCast(self.record_errors.len + 1));
            for (self.record_errors) |record_error| {
                try record_error.write(alloc, writer, version);
            }
            try writer.writeCompactNullableString(alloc, self.error_message);
        }

        if (isFlexible(version)) {
            if (version >= 10 and !std.meta.eql(self.current_leader, LeaderIdAndEpoch{})) {
                var x: Writer = .{};
                defer x.deinit(alloc);
                try self.current_leader.write(alloc, &x, version);
                try writer.writeUvarint(alloc, 1);
                try writer.writeUvarint(alloc, 0);
                try writer.writeUvarint(alloc, @intCast(x.buf.items.len));
                try writer.buf.appendSlice(alloc, x.buf.items);
            } else {
                try writer.writeUvarint(alloc, 0);
            }
        }
    }
};

pub const TopicProduceResponse = struct {
    name: ?[]const u8 = null,
    id: [16]u8,
    partition_responses: []PartitionProduceResponse,

    pub fn write(self: TopicProduceResponse, alloc: std.mem.Allocator, writer: *Writer, version: i16) !void {
        if (version <= 12) {
            try writer.writeCompactNullableString(alloc, self.name);
        }
        if (version > 12) {
            try writer.writeUuid(alloc, self.id);
        }

        try writer.writeUvarint(alloc, @intCast(self.partition_responses.len + 1));
        for (self.partition_responses) |partition_response| {
            try partition_response.write(alloc, writer, version);
        }

        if (isFlexible(version)) {
            try writer.writeUvarint(alloc, 0);
        }
    }
};

responses: []TopicProduceResponse = &.{},
throttle_time_ms: i32 = 0,
node_endpoints: []NodeEndpoint = &.{},

pub fn write(self: ProduceResponse, alloc: std.mem.Allocator, writer: *Writer, version: i16) !void {
    try writer.writeUvarint(alloc, @intCast(self.responses.len + 1));
    for (self.responses) |response| {
        try response.write(alloc, writer, version);
    }

    if (version >= 1) {
        try writer.writeInt(alloc, @TypeOf(self.throttle_time_ms), self.throttle_time_ms);
    }

    if (isFlexible(version)) {
        if (version >= 10 and self.node_endpoints.len > 0) {
            var x: Writer = .{};
            defer x.deinit(alloc);
            try x.writeUvarint(alloc, @intCast(self.node_endpoints.len + 1));
            for (self.node_endpoints) |endpoint| {
                try endpoint.write(alloc, &x, version);
            }
            try writer.writeUvarint(alloc, 1);
            try writer.writeUvarint(alloc, 0);
            try writer.writeUvarint(alloc, @intCast(x.buf.items.len));
            try writer.buf.appendSlice(alloc, x.buf.items);
        } else {
            try writer.writeUvarint(alloc, 0);
        }
    }
}

fn isFlexible(version: i16) bool {
    return version >= 9;
}
