const std = @import("std");

const json = std.json;
const mem = std.mem;

pub fn main(init: std.process.Init) !void {
    try hello(init);
}

const Field = struct {
    type: []const u8,
    name: []const u8,
    versions: []const u8,
    nullableVersions: []const u8 = "",
    flexibleVersions: []const u8 = "",
    fields: []Field = &.{},
};

const Msg = struct {
    apiKey: i16 = 0,
    type: []const u8,
    name: []const u8,
    validVersions: []const u8,
    flexibleVersions: []const u8,
    fields: []Field,
};

const typeInfo = struct {
    t: Type,
    name: ?[]const u8 = null,
    sub: ?*@This() = null,

    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        if (self.name) |str| {
            if (self.t == .Struct or self.t == .Array) {
                alloc.free(str);
            }
        }
        if (self.sub) |s| {
            s.deinit(alloc);
        }
        alloc.destroy(self);
    }
};

const Type = enum {
    Boolean,
    Int8,
    Int16,
    Int32,
    Int64,
    Uint16,
    Uint32,
    UUID,
    Float64,
    String,
    Bytes,
    Array,
    Struct,
    Records,

    Response,
    Request,
    Data,
};

pub fn hello(init: std.process.Init) !void {
    const paths = [_][]const u8{
        "./protocol_json_files/ProduceResponse.json",
    };

    for (paths) |path| {
        try readAndPrint(init, path);
    }
}

fn readAndPrint(init: std.process.Init, path: []const u8) !void {
    const file_content = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .unlimited);
    defer init.gpa.free(file_content);

    const clean = try clearComments(file_content, init.gpa);
    defer init.gpa.free(clean);

    const parsed = try json.parseFromSlice(Msg, init.gpa, clean, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    // std.json.fmt(parsed.value, .{});
    // std.debug.print("{f}\n", .{std.json.fmt(parsed.value, .{})});

    try p(parsed.value, init.gpa);
}

fn p(T: anytype, alloc: std.mem.Allocator) !void {
    const tinfo = try gen(T.type, alloc);
    defer tinfo.deinit(alloc);

    switch (tinfo.t) {
        .Request, .Response, .Data => {
            std.debug.print("const std = @import(\"std\");\n", .{});
            std.debug.print("const Reader = @import(\"Reader.zig\");\n", .{});
            std.debug.print("const {s} = @This();\n", .{T.name});
        },
        .Struct => {
                // push to queue
            std.debug.print("const {s} = struct{{\n", .{T.name});
            std.debug.print("}}\n", .{}); // TODO: remove
        },
        .Array => {
            if (tinfo.sub) |sub| {
                if (sub.t == .Struct) {
                    // push to queue
                    std.debug.print("const {s} = struct{{\n", .{T.name});
                    std.debug.print("}}\n", .{}); // TODO: remove
                }
            }
        },
        else => {},
    }

    for (T.fields) |field| {
        const finfo = try gen(field.type, alloc);
        std.debug.print("{s}: {s},\n", .{ field.name, finfo.name.? });
        finfo.deinit(alloc);
    }
    std.debug.print("pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator) !void {{\n", .{});
    for (T.fields) |field| {
        const finfo = try gen(field.type, alloc);
        defer finfo.deinit(alloc);

        std.debug.print("\t", .{});
        switch (finfo.t) {
            .Boolean => {
                std.debug.print("self.{s} = try reader.readBool();", .{field.name});
            },
            .Int8 => {
                std.debug.print("self.{s} = try reader.readInt(i8);", .{field.name});
            },
            .Int16 => {
                std.debug.print("self.{s} = try reader.readInt(i16);", .{field.name});
            },
            .Int32 => {
                std.debug.print("self.{s} = try reader.readInt(i32);", .{field.name});
            },
            .Int64 => {
                std.debug.print("self.{s} = try reader.readInt(i64);", .{field.name});
            },
            .Uint16 => {
                std.debug.print("self.{s} = try reader.readInt(u16);", .{field.name});
            },
            .Uint32 => {
                std.debug.print("self.{s} = try reader.readInt(u32);", .{field.name});
            },
            .UUID => {
                std.debug.print("self.{s} = try reader.readUuid();", .{field.name});
            },
            .Float64 => {
                std.debug.print("self.{s} = try reader.readFloat64();", .{field.name});
            },
            .String => {
                std.debug.print("self.{s} = try reader.readString(alloc);", .{field.name});
            },
            .Bytes => {
                std.debug.print("self.{s} = try reader.readBytes(alloc);", .{field.name});
            },
            .Array => {
                std.debug.print("self.{s} = try reader.readArray({s}, alloc);", .{ finfo.sub.?.name.?, field.name });
            },
            .Struct => {
                std.debug.print("try self.{s}.read(reader, alloc);", .{field.name});
            },
            .Records => unreachable,

            .Response, .Request, .Data => unreachable,
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("}}\n", .{});
}

fn gen(s: []const u8, alloc: std.mem.Allocator) !*typeInfo {
    const result = try alloc.create(typeInfo);
    result.t = try parseType(s);
    result.name = null;
    result.sub = null;

    switch (result.t) {
        .Array => {
            result.sub = try gen(s[2..], alloc);
            result.name = try std.fmt.allocPrint(alloc, "[]{s}", .{result.sub.?.name.?});
        },

        .Struct => result.name = try alloc.dupe(u8, s),

        .Boolean => result.name = "bool",
        .Int8 => result.name = "i8",
        .Int16 => result.name = "i16",
        .Int32 => result.name = "i32",
        .Int64 => result.name = "i64",
        .Uint16 => result.name = "u16",
        .Uint32 => result.name = "u32",
        .UUID => result.name = "[16]u8",
        .Float64 => result.name = "f64",
        .String => result.name = "[]const u8",

        .Request => result.name = "request",
        .Response => result.name = "response",
        .Data => result.name = "data",

        .Bytes, .Records => unreachable,
    }
    return result;
}

fn parseType(typeStr: []const u8) !Type {
    const map = std.static_string_map.StaticStringMap(Type);
    const kv = struct { []const u8, Type };
    const slice: []const kv = &.{
        .{ "bool", .Boolean },
        .{ "int8", .Int8 },
        .{ "int16", .Int16 },
        .{ "uint16", .Uint16 },
        .{ "int32", .Int32 },
        .{ "uint32", .Uint32 },
        .{ "int64", .Int64 },
        .{ "float64", .Float64 },
        .{ "string", .String },
        .{ "uuid", .UUID },
        .{ "bytes", .Bytes },
        .{ "records", .Records },
        .{ "struct", .Struct },

        .{ "request", .Request },
        .{ "response", .Response },
        .{ "data", .Data },
    };
    const m = map.initComptime(slice);
    if (m.get(typeStr)) |typ| {
        return typ;
    } else {
        if (typeStr[0] == '[') {
            return .Array;
        }
        if (std.ascii.isUpper(typeStr[0])) {
            return .Struct;
        }
    }
    return error.NotFound;
}

fn clearComments(src: []const u8, alloc: mem.Allocator) ![]const u8 {
    const dst = try alloc.alloc(u8, src.len);

    var pos: usize = 0;

    var in_comment = false;
    var in_string = false;
    for (src, 0..) |byte, i| {
        if (!in_string and byte == '"') {
            in_string = true;
        }
        if (in_string and byte == '"') {
            in_string = false;
        }
        if (!in_string and byte == '/' and i < src.len - 1 and src[i + 1] == '/') {
            in_comment = true;
        }

        if (in_comment and byte == '\n') {
            in_comment = false;
            continue;
        }

        if (in_comment) {
            continue;
        }

        dst[pos] = byte;
        pos += 1;
    }

    const result = try alloc.dupe(u8, dst[0..pos]);
    defer alloc.free(dst);

    return result;
}
