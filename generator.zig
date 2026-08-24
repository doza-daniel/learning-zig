const std = @import("std");

const json = std.json;
const mem = std.mem;

pub fn main(init: std.process.Init) !void {
    const paths = [_][]const u8{
        "./protocol_json_files/ProduceRequest.json",
    };

    for (paths) |path| {
        try readAndPrint(init, path);
    }
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

fn readAndPrint(init: std.process.Init, path: []const u8) !void {
    const file_content = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .unlimited);
    defer init.gpa.free(file_content);

    const clean = try clearComments(file_content, init.gpa);
    defer init.gpa.free(clean);

    const parsed = try json.parseFromSlice(Msg, init.gpa, clean, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try codeGen(parsed.value, init.gpa);
}

fn codeGen(T: anytype, alloc: std.mem.Allocator) !void {
    const tinfo = try parseTypeInfo(T.type, alloc);
    defer tinfo.deinit(alloc);

    var q: std.Deque(Field) = .empty;
    defer q.deinit(alloc);

    var close: bool = false;

    switch (tinfo.t) {
        .Request, .Response, .Data => {
            std.debug.print("const std = @import(\"std\");\n", .{});
            std.debug.print("const Reader = @import(\"Reader.zig\");\n", .{});
            std.debug.print("const RecordBatch = @import(\"RecordBatch.zig\");\n", .{});
            std.debug.print("const {s} = @This();\n", .{T.name});
        },
        .Struct => {
            std.debug.print("const {s} = struct{{\n", .{tinfo.name.?});
            close = true;
        },
        .Array => {
            if (tinfo.sub) |sub| {
                if (sub.t == .Struct) {
                    // push to queue
                    std.debug.print("const {s} = struct{{\n", .{sub.name.?});
                    close = true;
                }
            }
        },
        else => {},
    }

    for (T.fields) |field| {
        const finfo = try parseTypeInfo(field.type, alloc);
        defer finfo.deinit(alloc);
        switch (finfo.t) {
            .Struct, .Array => try q.pushBack(alloc, field),
            else => {},
        }
        std.debug.print("{s}: {s},\n", .{ field.name, finfo.name.? });
    }
    std.debug.print("pub fn read(self: *@This(), reader: *Reader, alloc: std.mem.Allocator) !void {{\n", .{});
    for (T.fields) |field| {
        const finfo = try parseTypeInfo(field.type, alloc);
        defer finfo.deinit(alloc);

        switch (finfo.t) {
            .Boolean => {
                std.debug.print("self.{s} = try reader.readBool();\n", .{field.name});
            },
            .Int8 => {
                std.debug.print("self.{s} = try reader.readInt(i8);\n", .{field.name});
            },
            .Int16 => {
                std.debug.print("self.{s} = try reader.readInt(i16);\n", .{field.name});
            },
            .Int32 => {
                std.debug.print("self.{s} = try reader.readInt(i32);\n", .{field.name});
            },
            .Int64 => {
                std.debug.print("self.{s} = try reader.readInt(i64);\n", .{field.name});
            },
            .Uint16 => {
                std.debug.print("self.{s} = try reader.readInt(u16);\n", .{field.name});
            },
            .Uint32 => {
                std.debug.print("self.{s} = try reader.readInt(u32);\n", .{field.name});
            },
            .UUID => {
                std.debug.print("self.{s} = try reader.readUuid();\n", .{field.name});
            },
            .Float64 => {
                std.debug.print("self.{s} = try reader.readFloat64();\n", .{field.name});
            },
            .String => {
                std.debug.print("self.{s} = try reader.readString(alloc);\n", .{field.name});
            },
            .Bytes => {
                std.debug.print("self.{s} = try reader.readBytes(alloc);\n", .{field.name});
            },
            .Array => {
                std.debug.print("self.{s} = try reader.readArray({s}, alloc);\n", .{ field.name, finfo.sub.?.name.? });
            },
            .Struct => {
                std.debug.print("try self.{s}.read(reader, alloc);\n", .{field.name});
            },
            .Records => {
                std.debug.print("var bytes = try reader.readBytes(alloc);\n", .{});
                std.debug.print("defer alloc.free(bytes);\n", .{});
                std.debug.print("var record_reader: Reader = .{{.src = &bytes}};\n", .{});
                std.debug.print("try self.{s}.read(&record_reader, alloc);\n", .{field.name});
            },

            // TODO: fix
            .Response, .Request, .Data => unreachable,
        }
    }
    std.debug.print("}}\n", .{});

    if (close) {
        std.debug.print("}};\n", .{});
    }

    while (q.len > 0) {
        try codeGen(q.popFront().?, alloc);
    }
}

fn parseTypeInfo(s: []const u8, alloc: std.mem.Allocator) !*typeInfo {
    const result = try alloc.create(typeInfo);
    result.t = try parseType(s);
    result.name = null;
    result.sub = null;

    switch (result.t) {
        .Array => {
            result.sub = try parseTypeInfo(s[2..], alloc);
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
        .Bytes => result.name = "[]u8",
        .Records => result.name = "RecordBatch",

        .Request => result.name = "request",
        .Response => result.name = "response",
        .Data => result.name = "data",
    }
    return result;
}

const typeMap: std.static_string_map.StaticStringMap(Type) = .initComptime(&[_]struct { []const u8, Type }{
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
});

fn parseType(typeStr: []const u8) !Type {
    if (typeMap.get(typeStr)) |typ| {
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
