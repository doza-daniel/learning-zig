const std = @import("std");

const Reader = @import("Reader.zig");
const RecordBatch = @This();

base_offset: i64,
batch_length: i32,
partition_leader_epoch: i32,
magic: i8,
crc: u32,
attributes: i16,
//     bit 0~2:
//         0: no compression
//         1: gzip
//         2: snappy
//         3: lz4
//         4: zstd
//     bit 3: timestampType
//     bit 4: isTransactional (0 means not transactional)
//     bit 5: isControlBatch (0 means not a control batch)
//     bit 6: hasDeleteHorizonMs (0 means baseTimestamp is not set as the delete horizon for compaction)
//     bit 7~15: unused
last_offset_delta: i32,
base_timestamp: i64,
max_timestamp: i64,
producer_id: i64,
producer_epoch: i16,
base_sequence: i32,
records_count: i32,
records: []Record,

pub fn read(self: *RecordBatch, reader: *Reader, alloc: std.mem.Allocator) !void {
    self.base_offset = try reader.readInt(i64);
    self.batch_length = try reader.readInt(i32);
    self.partition_leader_epoch = try reader.readInt(i32);
    self.magic = try reader.readInt(i8);
    self.crc = try reader.readInt(u32);
    self.attributes = try reader.readInt(i16);
    self.last_offset_delta = try reader.readInt(i32);
    self.base_timestamp = try reader.readInt(i64);
    self.max_timestamp = try reader.readInt(i64);
    self.producer_id = try reader.readInt(i16);
    self.producer_epoch = try reader.readInt(i16);
    self.base_sequence = try reader.readInt(i32);

    self.records_count = try reader.readInt(i32);
    const j = @as(usize, @intCast(self.records_count));
    self.records = try alloc.alloc(Record, j);
    for (0..j) |i| {
        var record: Record = .{
            .length = 0,
            .attributes = 0,
            .timestamp_delta = 0,
            .offset_delta = 0,
            .key_length = 0,
            .key = &.{},
            .value_length = 0,
            .value = &.{},
            .headers_count = 0,
            .headers = &.{},
        };
        try record.read(reader, alloc);
        self.records[i] = record;
    }
}

pub fn deinit(self: RecordBatch, alloc: std.mem.Allocator) void {
    for (self.records) |record| {
        record.deinit(alloc);
    }
    alloc.free(self.records);
}

const Record = struct {
    length: u32,
    attributes: i8,
    timestamp_delta: i64,
    offset_delta: i32,
    key_length: i32,
    key: []u8,
    value_length: i32,
    value: []u8,
    headers_count: i32,
    headers: []Header,

    pub fn read(self: *Record, reader: *Reader, alloc: std.mem.Allocator) !void {
        self.length = try reader.readInt(u32);
        self.attributes = try reader.readInt(i8);
        self.timestamp_delta = try reader.readVarlong();
        self.offset_delta = try reader.readVarint();

        var j: usize = 0;

        self.key_length = try reader.readVarint();
        j = @as(usize, @intCast(self.key_length));
        self.key = try alloc.dupe(u8, reader.src[0..j]);
        reader.src = reader.src[j..];

        self.value_length = try reader.readVarint();
        j = @as(usize, @intCast(self.value_length));
        self.value = try alloc.dupe(u8, reader.src[0..j]);
        reader.src = reader.src[j..];

        self.headers_count = try reader.readVarint();
        j = @as(usize, @intCast(self.value_length));
        self.headers = try alloc.alloc(Header, j);
        for (0..j) |i| {
            var h: Header = .{
                .header_key_length = 0,
                .header_key = &.{},
                .header_value_length = 0,
                .header_value = &.{},
            };
            try h.read(reader, alloc);
            self.headers[i] = h;
        }
    }

    pub fn deinit(self: *Record, alloc: std.mem.Allocator) void {
        alloc.free(self.key);
        alloc.free(self.value);
        for (self.headers) |header| {
            header.deinit(alloc);
        }
        alloc.free(self.headers);
    }
};

const Header = struct {
    header_key_length: i32,
    header_key: []u8,
    header_value_length: i32,
    header_value: []u8,

    pub fn read(self: *Header, reader: *Reader, alloc: std.mem.Allocator) !void {
        var j: usize = 0;

        self.header_key_length = try reader.readVarint();
        j = @as(usize, @intCast(self.header_key_length));
        self.header_key = try alloc.dupe(u8, reader.src[0..j]);
        reader.src = reader.src[j..];

        self.header_value_length = try reader.readVarint();
        j = @as(usize, @intCast(self.header_value_length));
        self.header_value = try alloc.dupe(u8, reader.src[0..j]);
        reader.src = reader.src[j..];
    }

    pub fn deinit(self: *Header, alloc: std.mem.Allocator) void {
        alloc.free(self.header_key);
        alloc.free(self.value);
    }
};
