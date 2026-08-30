const std = @import("std");

const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const VersionInfo = @import("root.zig").VersionInfo;

const context = struct {
    min: i16 = 0,
    max: i16 = std.math.maxInt(i16),

    fn make(c: Condition) context {
        return switch (c) {
            .version => |v| switch (v) {
                .range => |range| .{ .min = range.min, .max = range.max orelse std.math.maxInt(i16) },
                else => .{},
            },
            else => .{},
        };
    }
};

pub const Condition = union(enum) {
    version: VersionInfo,
    literal: []const u8,

    pub fn render(self: Condition, ctx: context, out: *Writer) !void {
        switch (self) {
            .version => |vi| switch (vi) {
                .exact => |exact| {
                    if (exact < ctx.min or exact > ctx.max) {
                        return error.AlwaysFalse;
                    }
                    try out.print("version == {d}", .{exact});
                },
                .range => |range| {
                    var err: bool = true;

                    if (range.min > ctx.max) {
                        return error.AlwaysFalse;
                    }

                    if (range.min > ctx.min) {
                        try out.print("version >= {d}", .{range.min});
                        err = false;
                    }
                    if (range.max) |max| {
                        if (max < ctx.min) {
                            return error.AlwaysFalse;
                        }
                        if (max < ctx.max) {
                            const and_op = if (!err) " and " else "";
                            try out.print("{s}version <= {d}", .{ and_op, range.max.? });
                            err = false;
                        }
                    }

                    if (err) {
                        return error.AlwaysTrue;
                    }
                },
                .none => return error.AlwaysFalse,
            },
            .literal => |str| try out.print("{s}", .{str}),
        }
    }
};

const Kind = union(enum) {
    @"if": struct {
        cond: Condition,
        true: *Expr,
        false: ?*Expr,
    },
    line: []const u8,
    block: []const *Expr,
};

const Expr = @This();

kind: Kind,

pub fn If(gpa: Allocator, c: Condition, t: *Expr, f: ?*Expr) !*Expr {
    const ptr = try gpa.create(Expr);
    ptr.* = .{ .kind = .{ .@"if" = .{ .cond = c, .true = t, .false = f } } };
    return ptr;
}

pub fn Line(gpa: Allocator, comptime fmt: []const u8, args: anytype) !*Expr {
    const ptr = try gpa.create(Expr);
    ptr.* = .{ .kind = .{ .line = try std.fmt.allocPrint(gpa, fmt, args) } };
    return ptr;
}

pub fn Block(gpa: Allocator, list: []const *Expr) !*Expr {
    const ptr = try gpa.create(Expr);
    ptr.* = .{ .kind = .{ .block = list } };
    return ptr;
}

pub fn render(self: @This(), ctx: context, writer: *Writer) !void {
    switch (self.kind) {
        .@"if" => |e| {
            var buff: [1024]u8 = undefined;
            var w: Writer = .fixed(&buff);
            e.cond.render(ctx, &w) catch |err| {
                return switch (err) {
                    error.AlwaysTrue => try e.true.render(ctx, writer),
                    error.AlwaysFalse => if (e.false) |f| try f.render(ctx, writer),
                    else => err,
                };
            };

            const new_ctx: context = .make(e.cond);

            try writer.print("if ({s}) {{\n", .{w.buffered()});

            try e.true.render(new_ctx, writer);
            if (e.false) |f| {
                try writer.print("}} else {{\n", .{});
                try f.render(new_ctx, writer);
            }
            try writer.print("}}\n", .{});
        },
        .line => |e| try writer.writeAll(e),
        .block => |e| {
            for (e) |expr| {
                try expr.render(ctx, writer);
            }
        },
    }
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    defer gpa.destroy(self);
    switch (self.kind) {
        .@"if" => |e| {
            e.true.deinit(gpa);
            if (e.false) |f| f.deinit(gpa);
        },
        .line => |e| gpa.free(e),
        .block => |e| {
            for (e) |expr| {
                expr.deinit(gpa);
            }
        },
    }
}

test "if literal" {
    const gpa = std.testing.allocator;
    const if_lit: *Expr = try .If(gpa, .{ .literal = "cond" }, try .Line(gpa, "foo", .{}), try .Line(gpa, "bar", .{}));
    defer if_lit.deinit(gpa);
    var buff: [300]u8 = undefined;
    var out: Writer = .fixed(&buff);
    try if_lit.render(.{}, &out);
    try std.testing.expectEqualStrings("if (cond) {\nfoo} else {\nbar}\n", out.buffered());
}

test "different version setups" {
    const gpa = std.testing.allocator;

    const table = .{
        .{
            .version = VersionInfo.none,
            .false_branch = try Expr.Line(gpa, "bar", .{}),
            .expect = "bar",
        },
        .{
            .version = VersionInfo.none,
            .false_branch = null,
            .expect = "",
        },
        .{
            // only min, no else branch
            .version = VersionInfo{ .range = .{ .min = 1 } },
            .false_branch = null,
            .expect = "if (version >= 1) {\nfoo}\n",
        },
        .{
            // only min, always true, no else branch
            .version = VersionInfo{ .range = .{ .min = 0 } },
            .false_branch = null,
            .expect = "foo",
        },
        .{
            // only min, always true, else branch ignored
            .version = VersionInfo{ .range = .{ .min = 0 } },
            .false_branch = try Expr.Line(gpa, "bar", .{}),
            .expect = "foo",
        },
        .{
            // only min, with else branch
            .version = VersionInfo{ .range = .{ .min = 1 } },
            .false_branch = try Expr.Line(gpa, "bar", .{}),
            .expect = "if (version >= 1) {\nfoo} else {\nbar}\n",
        },
        .{
            // only min, no else branch
            .version = VersionInfo{ .exact = 1 },
            .false_branch = null,
            .expect = "if (version == 1) {\nfoo}\n",
        },
        .{
            // only min, with else branch
            .version = VersionInfo{ .exact = 1 },
            .false_branch = try Expr.Line(gpa, "bar", .{}),
            .expect = "if (version == 1) {\nfoo} else {\nbar}\n",
        },
    };

    inline for (table) |case| {
        const expr: *Expr = try .If(gpa, .{ .version = case.version }, try .Line(gpa, "foo", .{}), case.false_branch);
        defer expr.deinit(gpa);
        var buff: [300]u8 = undefined;
        var out: Writer = .fixed(&buff);
        try expr.render(.{}, &out);
        try std.testing.expectEqualStrings(case.expect, out.buffered());
    }
}

test "if expression - range condition based on context" {
    const gpa = std.testing.allocator;

    const table = .{
        .{
            // full range
            .ctx = context{},
            .expect = "if (version >= 10 and version <= 20) {\nfoo} else {\nbar}\n",
        },
        .{
            // left, outside - always false
            .ctx = context{ .min = 30, .max = 40 },
            .expect = "bar",
        },
        .{
            // left, touching
            .ctx = context{ .min = 20, .max = 40 },
            .expect = "if (version <= 20) {\nfoo} else {\nbar}\n",
        },
        .{
            // left, intersect
            .ctx = context{ .min = 15, .max = 40 },
            .expect = "if (version <= 20) {\nfoo} else {\nbar}\n",
        },
        .{
            // inside, touching left
            .ctx = context{ .min = 10, .max = 40 },
            .expect = "if (version <= 20) {\nfoo} else {\nbar}\n",
        },
        .{
            // inside, fully
            .ctx = context{ .min = 5, .max = 40 },
            .expect = "if (version >= 10 and version <= 20) {\nfoo} else {\nbar}\n",
        },
        .{
            // inside, touching right
            .ctx = context{ .min = 5, .max = 20 },
            .expect = "if (version >= 10) {\nfoo} else {\nbar}\n",
        },
        .{
            // right, intersect
            .ctx = context{ .min = 5, .max = 15 },
            .expect = "if (version >= 10) {\nfoo} else {\nbar}\n",
        },
        .{
            // right, touching
            .ctx = context{ .min = 5, .max = 10 },
            .expect = "if (version >= 10) {\nfoo} else {\nbar}\n",
        },
        .{
            // right, outside - always false
            .ctx = context{ .min = 5, .max = 9 },
            .expect = "bar",
        },
        .{
            // containing - always true
            .ctx = context{ .min = 11, .max = 19 },
            .expect = "foo",
        },
    };

    inline for (table) |case| {
        const rng: VersionInfo = .{ .range = .{ .min = 10, .max = 20 } };
        const expr: *Expr = try .If(gpa, .{ .version = rng }, try .Line(gpa, "foo", .{}), try .Line(gpa, "bar", .{}));
        defer expr.deinit(gpa);
        var buff: [300]u8 = undefined;
        var out: Writer = .fixed(&buff);
        try expr.render(case.ctx, &out);
        try std.testing.expectEqualStrings(case.expect, out.buffered());
    }
}

test "if expression - exact condition based on context" {
    const gpa = std.testing.allocator;

    const table = .{
        .{
            // left, outside - always false
            .ctx = context{ .min = 20, .max = 30 },
            .expect = "bar",
        },
        .{
            // left, border
            .ctx = context{ .min = 15, .max = 30 },
            .expect = "if (version == 15) {\nfoo} else {\nbar}\n",
        },
        .{
            // inside
            .ctx = context{ .min = 10, .max = 30 },
            .expect = "if (version == 15) {\nfoo} else {\nbar}\n",
        },
        .{
            // right, border
            .ctx = context{ .min = 10, .max = 15 },
            .expect = "if (version == 15) {\nfoo} else {\nbar}\n",
        },
        .{
            // right, outside
            .ctx = context{ .min = 5, .max = 10 },
            .expect = "bar",
        },
    };

    inline for (table) |case| {
        const rng: VersionInfo = .{ .exact = 15 };
        const expr: *Expr = try .If(gpa, .{ .version = rng }, try .Line(gpa, "foo", .{}), try .Line(gpa, "bar", .{}));
        defer expr.deinit(gpa);
        var buff: [300]u8 = undefined;
        var out: Writer = .fixed(&buff);
        try expr.render(case.ctx, &out);
        try std.testing.expectEqualStrings(case.expect, out.buffered());
    }
}
