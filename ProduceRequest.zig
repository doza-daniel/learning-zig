const std = @import("std");

const Reader = @import("Reader.zig");
const RecordBatch = @import("RecordBatch.zig");

const mem = std.mem;

const ProduceRequest = @This();

const PartitionProduceData = struct {
    index: i32,
    data: []u8,
    record_batch: RecordBatch,

    fn deinit(self: *PartitionProduceData, alloc: mem.Allocator) void {
        alloc.free(self.data);
    }
};

const TopicProduceData = struct {
    name: ?[]const u8 = null,
    topic_id: [16]u8,
    partition_data: []PartitionProduceData,

    fn deinit(self: *TopicProduceData, alloc: mem.Allocator) void {
        alloc.free(self.name);
        for (self.partition_data) |partition| {
            partition.deinit(alloc);
        }
        alloc.free(self.partition_data);
    }
};

version: i16,

transactional_id: ?[]const u8 = null,
acks: i16,
timeout_ms: i32,
topic_data: []TopicProduceData,

// 00 00                                            -- api_key 0
// 00 0d                                            -- api_version 13
// 00 00 00 01                                      -- correlation_id
// 00 0e                                            -- client_id len = 14
// 70 65 74 61 72 20 70 65 74 72 6f 76 69 63        -- "petar petrovic"
// 00                                               -- tags len = 0
// 00                                               -- transactional_id len = 0
// ff ff                                            -- acks = -1
// 00 00 27 10                                      -- timeout_ms
// 02                                               -- topic_data len = 2 (1)
// 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10  -- topic_id
// 02                                               -- partition_data len = 2
// 00 00 00 00                                      -- partition index = 0
// 56                                               -- compact bytes len - 86
// 00 00 00 00 00 00 00 00                          -- base offset = 0
// 00 00 00 49                                      -- batch_length = 73
// ff ff ff ff                                      -- partition leader_epoch = -1
// 02                                               -- magic
// 6b a8 72 73                                      -- crc
// 00 00                                            -- attributes = 0
// 00 00 00 00                                      -- last offset delta = 0
// 00 00 01 a0 00 b8 ec 2e                          -- base timestamp = 1786718514222 = 08/14/2026 @ 3:45pm UTC
// 00 00 01 a0 00 b8 ec 2e                          -- max timestamp = 1786718514222 = 08/14/2026 @ 3:45pm UTC
// 00 00 00 00 00 00 01 a4                          -- producer id = 420
// 00 00                                            -- producer epoch = 0
// 00 00 00 00                                      -- base sequence = 0
// 00 00 00 01                                      -- record count = 1
// 2e                                               -- record len = 46
// 00                                               -- attributes
// 00                                               -- timestamp delta
// 00                                               -- offset delta
// 0e                                               -- key len = 14 ?
// 31 32 33 2e 34 35 36                             -- key = 1 2 3 . 4 5 6
// 14                                               -- value len = 20 ?
// 7b 22 66 6f 6f 22 3a 34 32 7d                    -- value = { " f o o " : 4 2 }
// 00                                               -- header count = 0
// 00 00 00

pub fn read(self: *ProduceRequest, reader: *Reader, alloc: mem.Allocator) !void {
    if (self.version >= 3) {
        if (self.isFlexible()) {
            self.transactional_id = try reader.readCompactString(alloc);
        } else {
            self.transactional_id = try reader.readNullableString(alloc);
        }
    }
    self.acks = try reader.readInt(i16);
    self.timeout_ms = try reader.readInt(i32);

    var num_topics: u32 = 0;
    if (self.isFlexible()) {
        num_topics = try reader.readUvarint();
    } else {
        num_topics = try reader.readInt(u32) + 1;
    }
    if (num_topics > 1) {
        try self.readTopics(reader, alloc, num_topics - 1);
    }
}

fn readTopics(self: *ProduceRequest, reader: *Reader, alloc: mem.Allocator, n: u32) !void {
    self.topic_data = try alloc.alloc(TopicProduceData, n);
    for (0..n) |i| {
        self.topic_data[i].name = null;
        if (self.version <= 12) {
            if (self.isFlexible()) {
                self.topic_data[i].name = try reader.readCompactString(alloc);
            } else {
                self.topic_data[i].name = try reader.readNullableString(alloc);
            }
        }
        if (self.version >= 13) {
            self.topic_data[i].topic_id = try reader.readUuid();
        }
        var num_partitions: u32 = 0;
        if (self.isFlexible()) {
            num_partitions = try reader.readUvarint();
        } else {
            num_partitions = try reader.readInt(u32) + 1;
        }
        if (num_partitions > 1) {
            try self.readPartitions(reader, alloc, &self.topic_data[i], num_partitions - 1);
        }
    }
}

fn readPartitions(self: *ProduceRequest, reader: *Reader, alloc: mem.Allocator, topic_data: *TopicProduceData, n: u32) !void {
    _ = self;
    topic_data.partition_data = try alloc.alloc(PartitionProduceData, n);
    for (0..n) |i| {
        topic_data.partition_data[i].index = try reader.readInt(i32);
        topic_data.partition_data[i].data = try reader.readCompactBytes(alloc);
        var record_batch_reader: Reader = .{ .src = topic_data.partition_data[i].data };
        try topic_data.partition_data[i].record_batch.read(&record_batch_reader, alloc);
    }
}

pub fn deinit(self: *ProduceRequest, alloc: mem.Allocator) void {
    alloc.free(self.transactional_id);
    for (self.topic_data) |topic| {
        topic.deinit(alloc);
    }
    alloc.free(self.topic_data);
}

pub fn isFlexible(self: ProduceRequest) bool {
    return self.version >= 9;
}
