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

    const position = Position{ .pos = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 } };
    const velocity = Velocity{ .vel = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 } };

    // create an entity that only has a position
    const entity = try registry.spawn(.{position});
    std.debug.print("Created entity: {}\n", .{entity});

    // add a velocity to the entity: it consumes in the previous one, and gives a new one ?
    const moving_entity = try registry.add_components(entity, .{velocity});
    std.debug.print("Updated entity: {}\n", .{moving_entity});

    const data = try registry.despawn(moving_entity);
    std.debug.print("Despawned entity and got back components: {}\n", .{data});

    // That is illegal, and works but we should prevent that
    // the idea is that this entity have already been moved when adding a velocity the first time
    // There is only a shadow of it left, it shall not be used like so
    // try registry.add_components(entity, .{velocity});

    // create an already moving entity
    const already_moving = try registry.spawn(.{ velocity, position });
    std.debug.print("Created new entity: {}\n", .{already_moving});

    // remove the velocity from the entity
    const ent_and_vel = try registry.remove_components(already_moving, struct { Velocity });
    const stopped_moving = ent_and_vel.entity;
    const prev_velocity = ent_and_vel.components;
    std.debug.print("Entity {} no more has {}\n", .{ stopped_moving, prev_velocity });
}
