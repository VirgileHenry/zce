const archetype_utils = @import("archetype.zig");

pub fn Entity(comptime archetype: anytype) type {
    archetype_utils.checkArchetype(archetype);

    return struct {
        const Self = @This();
        pub const Archetype = archetype;
        id: usize,

        pub fn new(id: usize) Self {
            return .{
                .id = id,
            };
        }
    };
}
