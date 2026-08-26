const std = @import("std");

const generator = @import("generator");

pub fn main(init: std.process.Init) !void {
    try generator.handleFile(init, "./protocol_json_files/ProduceRequest.json");
}
