const std = @import("std");
const zce = @import("zce");

// Let's see how I picture this ECS to work ?

// create some components
const Vec3 = struct { x: f32, y: f32, z: f32 };
const Velocity = struct { vel: Vec3 };
const Position = struct { pos: Vec3 };

// create a registry from the list of possible archetypes
const Archetypes = [_]type{
    struct { Position, Velocity },
    struct { Position },
};
const Registry = zce.registry.Registry(&Archetypes);

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // init the registry
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator.deinit();

    var registry = Registry.init(allocator.allocator());
    defer registry.deinit();

    // create an entity that only has a position
    const position = Position{ .pos = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 } };
    const entity = try registry.spawn(.{position});
    std.debug.print("Created entity: {}", .{entity});
    // add a velocity to the entity: it consumes in the previous one, and gives a new one ?
    // const moving_entity = registry.add_components(entity, .{Velocity{ .vel = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 } }});

}
