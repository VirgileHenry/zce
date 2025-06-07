const archetype_utils = @import("archetype.zig");

pub fn Entity(comptime archetype: anytype) type {
    return struct {
        const Self = @This();
        pub const Archetype = archetype_utils.Archetype(archetype);
        id: usize,

        pub fn new(id: usize) Self {
            return .{
                .id = id,
            };
        }
    };
}
