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
    name: []const u8 = "",
    sub: ?*@This() = null,

    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        if (self.t == .Struct or self.t == .Array) {
            alloc.free(self.name);
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

    var close_struct: bool = false;

    switch (tinfo.t) {
        .Request, .Response, .Data => {
            std.debug.print("const std = @import(\"std\");\n", .{});
            std.debug.print("const Reader = @import(\"Reader.zig\");\n", .{});
            std.debug.print("const RecordBatch = @import(\"RecordBatch.zig\");\n", .{});
            std.debug.print("const {s} = @This();\n", .{T.name});
        },
        .Struct => {
            std.debug.print("const {s} = struct{{\n", .{tinfo.name});
            close_struct = true;
        },
        .Array => {
            if (tinfo.sub) |sub| {
                if (sub.t == .Struct) {
                    std.debug.print("const {s} = struct{{\n", .{sub.name});
                    close_struct = true;
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
        std.debug.print("{s}: {s},\n", .{ field.name, finfo.name });
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
                std.debug.print("self.{s} = try reader.readArray({s}, alloc);\n", .{ field.name, finfo.sub.?.name });
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

            .Response, .Request, .Data => unreachable,
        }
    }
    std.debug.print("}}\n", .{});

    if (close_struct) {
        std.debug.print("}};\n", .{});
    }

    while (q.len > 0) {
        try codeGen(q.popFront().?, alloc);
    }
}

fn parseTypeInfo(s: []const u8, alloc: std.mem.Allocator) !*typeInfo {
    const result = try alloc.create(typeInfo);
    result.t = try parseType(s);
    result.name = "";
    result.sub = null;

    switch (result.t) {
        .Array => {
            result.sub = try parseTypeInfo(s[2..], alloc);
            result.name = try std.fmt.allocPrint(alloc, "[]{s}", .{result.sub.?.name});
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

const Ti = union(enum) {
    bool: void,
    int8: void,
    int16: void,
    int32: void,
    int64: void,
    uint16: void,
    uint32: void,
    uuid: void,
    float64: void,
    string: void,
    bytes: void,
    data: void,
    records: void,
    response: void,
    request: void,
    header: void,

    array: struct {
        name: []const u8,
        elements: *Ti,
    },
    structure: []const u8,

    fn zigType(self: Ti) ![]const u8 {
        return switch (self) {
            .bool => "bool",
            .int8 => "i8",
            .int16 => "i16",
            .int32 => "i32",
            .int64 => "i64",
            .uint16 => "u16",
            .uint32 => "u32",
            .uuid => "[16]u8",
            .float64 => "f64",
            .string => "[]const u8",
            .bytes => "[]u8",
            .array => |arr| arr.name,
            .structure => |name| name,
            else => error.NoName,
        };
    }

    fn parse(str: []const u8, alloc: std.mem.Allocator) !*Ti {
        const result = try alloc.create(Ti);
        errdefer alloc.destroy(result);

        if (std.meta.stringToEnum(std.meta.Tag(Ti), str)) |tag| {
            switch (tag) {
                .bool => |t| result.* = t,
                .int8 => |t| result.* = t,
                .int16 => |t| result.* = t,
                .int32 => |t| result.* = t,
                .int64 => |t| result.* = t,
                .uint16 => |t| result.* = t,
                .uint32 => |t| result.* = t,
                .uuid => |t| result.* = t,
                .float64 => |t| result.* = t,
                .string => |t| result.* = t,
                .bytes => |t| result.* = t,
                .data => |t| result.* = t,
                .records => |t| result.* = t,
                .response => |t| result.* = t,
                .request => |t| result.* = t,
                .header => |t| result.* = t,

                .array, .structure => return error.BadPrimitive,
            }
            return result;
        }

        // parse array
        if (str.len > 2 and str[0] == '[' and str[1] == ']') {
            const elements = try parse(str[2..], alloc);
            result.* = .{
                .array = .{
                    .name = try std.fmt.allocPrint(alloc, "[]{s}", .{try elements.zigType()}),
                    .elements = elements,
                },
            };
            return result;
        }

        // finally, try parse struct
        for (str) |c| {
            if (!std.ascii.isAlphanumeric(c)) {
                return error.BadStructIdent;
            }
        }
        result.* = .{
            .structure = try alloc.dupe(u8, str),
        };
        return result;
    }

    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        defer alloc.destroy(self);
        switch (self.*) {
            .array => |arr| {
                arr.elements.deinit(alloc);
                alloc.free(arr.name);
            },
            .structure => |name| {
                alloc.free(name);
            },
            else => {},
        }
    }
};

test "parse_primitives" {
    const table = .{
        .{ .in = "bool", .expect = .bool },
        .{ .in = "int8", .expect = .int8 },
        .{ .in = "int16", .expect = .int16 },
        .{ .in = "int32", .expect = .int32 },
        .{ .in = "int64", .expect = .int64 },
        .{ .in = "uint16", .expect = .uint16 },
        .{ .in = "uint32", .expect = .uint32 },
        .{ .in = "uuid", .expect = .uuid },
        .{ .in = "float64", .expect = .float64 },
        .{ .in = "string", .expect = .string },
        .{ .in = "bytes", .expect = .bytes },
        .{ .in = "data", .expect = .data },
        .{ .in = "records", .expect = .records },
        .{ .in = "response", .expect = .response },
        .{ .in = "request", .expect = .request },
        .{ .in = "header", .expect = .header },
    };
    inline for (table) |case| {
        const parsed = try Ti.parse(case.in, std.testing.allocator);
        defer parsed.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.expect, parsed.*);
    }

    const my_array = try Ti.parse("[]MyStruct", std.testing.allocator);
    defer my_array.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("[]MyStruct", my_array.array.name);

    try std.testing.expectError(error.BadPrimitive, Ti.parse("structure", std.testing.allocator));
    try std.testing.expectError(error.BadPrimitive, Ti.parse("array", std.testing.allocator));
}

test "parse_struct" {
    const table = .{
        .{ .in = "foo", .expect_error = null },
        .{ .in = "fooBar", .expect_error = null },
        .{ .in = "fooBar1", .expect_error = null },
        .{ .in = "MyStruct", .expect_error = null },
        .{ .in = "MyStruct_", .expect_error = @as(?anyerror, error.BadStructIdent) },
    };
    inline for (table) |case| {
        const got = Ti.parse(case.in, std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            const parsed = try got;
            defer parsed.deinit(std.testing.allocator);
            try std.testing.expectEqualStrings(case.in, parsed.structure);
        }
    }
}

test "parse_array" {
    const table = .{
        .{ .in = "[]foo", .expect_error = null },
        .{ .in = "[]fooBar", .expect_error = null },
        .{ .in = "[]fooBar1", .expect_error = null },
        .{ .in = "[]MyStruct", .expect_error = null },
        .{ .in = "[]MyStruct_", .expect_error = @as(?anyerror, error.BadStructIdent) },
        .{ .in = "[]structure", .expect_error = @as(?anyerror, error.BadPrimitive) },
        .{ .in = "[]array", .expect_error = @as(?anyerror, error.BadPrimitive) },
    };
    inline for (table) |case| {
        const got = Ti.parse(case.in, std.testing.allocator);
        if (case.expect_error) |err| {
            try std.testing.expectError(err, got);
        } else {
            const parsed = try got;
            defer parsed.deinit(std.testing.allocator);
            try std.testing.expectEqualStrings(case.in, parsed.array.name);
        }
    }
}

test "zig_type" {
    try std.testing.expectEqualStrings("bool", try @as(Ti, .bool).zigType());
    try std.testing.expectEqualStrings("i8", try @as(Ti, .int8).zigType());
    try std.testing.expectEqualStrings("i16", try @as(Ti, .int16).zigType());
    try std.testing.expectEqualStrings("i32", try @as(Ti, .int32).zigType());
    try std.testing.expectEqualStrings("i64", try @as(Ti, .int64).zigType());
    try std.testing.expectEqualStrings("u16", try @as(Ti, .uint16).zigType());
    try std.testing.expectEqualStrings("u32", try @as(Ti, .uint32).zigType());
    try std.testing.expectEqualStrings("[16]u8", try @as(Ti, .uuid).zigType());
    try std.testing.expectEqualStrings("f64", try @as(Ti, .float64).zigType());
    try std.testing.expectEqualStrings("[]const u8", try @as(Ti, .string).zigType());
    try std.testing.expectEqualStrings("[]u8", try @as(Ti, .bytes).zigType());

    try std.testing.expectEqualStrings("[]Pera", try @as(Ti, .{ .array = .{ .name = "[]Pera", .elements = undefined } }).zigType());
    try std.testing.expectEqualStrings("MyStruct", try @as(Ti, .{ .structure = "MyStruct" }).zigType());

    try std.testing.expectError(error.NoName, @as(Ti, .records).zigType());
    try std.testing.expectError(error.NoName, @as(Ti, .header).zigType());
    try std.testing.expectError(error.NoName, @as(Ti, .request).zigType());
    try std.testing.expectError(error.NoName, @as(Ti, .response).zigType());
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
