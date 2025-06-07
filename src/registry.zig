const std = @import("std");
const mem = std.mem;
const comptimePrint = std.fmt.comptimePrint;

const entity_utils = @import("entity.zig");
const archetype_utils = @import("archetype.zig");

const MyArchetype = archetype_utils.Archetype(.{ bool, usize, 2 });

pub const RegistryError = error{
    InvalidEntity,
};

fn ArchetypeBucket(comptime archetype: type) type {
    return struct {
        const Self = @This();
        const Archetype = archetype_utils.Archetype(archetype);
        bucket: std.ArrayList(archetype),
        ids: std.ArrayList(usize),

        fn init(allocator: mem.Allocator) Self {
            return Self{
                .bucket = std.ArrayList(archetype).init(allocator),
                .ids = std.ArrayList(usize).init(allocator),
            };
        }

        fn spawn(self: *Self, data: Archetype) !entity_utils.Entity(Archetype) {
            var entity_id: usize = undefined;
            if (self.ids.pop()) |id| {
                self.bucket.items[id] = data;
                entity_id = id;
            } else {
                const id = self.bucket.items.len;
                try self.bucket.append(data);
                entity_id = id;
            }
            return entity_utils.Entity(Archetype).new(entity_id);
        }

        fn despawn(self: *Self, entity: entity_utils.Entity(Archetype)) !?Archetype {
            const data = self.bucket.items[entity.id];
            try self.ids.append(entity.id);
            return data;
        }

        fn deinit(self: *Self) void {
            self.bucket.deinit();
        }
    };
}

pub fn Registry(comptime archetypes: []const type) type {
    comptime var Archetypes = [_]type{undefined} ** archetypes.len;
    inline for (archetypes, 0..) |archetype, archetype_index| {
        Archetypes[archetype_index] = archetype_utils.Archetype(archetype);
        inline for (Archetypes[0..archetype_index], 0..) |previous_archetype, previous_index| {
            if (archetype_utils.equal(archetype, previous_archetype)) {
                @compileError(comptimePrint("Invalid Archetypes for register: Archetypes at index {} and {} are the same.", .{ archetype_index, previous_index }));
            }
        }
    }

    const dummy_field = std.builtin.Type.StructField{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 0,
    };
    comptime var bucket_map_fields = [_]std.builtin.Type.StructField{dummy_field} ** Archetypes.len;

    inline for (Archetypes, 0..) |archetype, index| {
        bucket_map_fields[index] = std.builtin.Type.StructField{
            .name = comptimePrint("{}", .{index}),
            .type = ArchetypeBucket(archetype),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 0, // ???
        };
    }

    const bucket_map_type = std.builtin.Type{
        .@"struct" = std.builtin.Type.Struct{
            .layout = std.builtin.Type.ContainerLayout.auto,
            .fields = &bucket_map_fields,
            .decls = &[0]std.builtin.Type.Declaration{},
            .is_tuple = true,
        },
    };
    // Sooo, if I got this right, I'm manually creating a new type at comptime here ? That's wild
    const BucketMap = @Type(bucket_map_type);

    return struct {
        const Self = @This();
        bucket_map: BucketMap,

        pub fn init(allocator: mem.Allocator) Self {
            var bucket_map: BucketMap = undefined;
            inline for (Archetypes, 0..) |archetype, field_index| {
                @field(bucket_map, comptimePrint("{}", .{field_index})) = ArchetypeBucket(archetype).init(allocator);
            }

            return .{
                .bucket_map = bucket_map,
            };
        }

        pub fn deinit(self: *Self) void {
            inline for (0..Archetypes.len) |field_index| {
                @field(self.bucket_map, comptimePrint("{}", .{field_index})).deinit();
            }
        }

        /// `findArchetype` allows to get the real archetype type in the registry from the provided anytype.
        ///
        /// This is necessary to bypass comptime types not being recognized as valid Archetypes.
        fn findArchetype(comptime archetype: anytype) type {
            const Archetype = archetype_utils.Archetype(archetype);
            inline for (Archetypes) |TestArchetype| {
                if (archetype_utils.equal(Archetype, TestArchetype)) {
                    return TestArchetype;
                }
            }
            @compileError(comptimePrint("No matching archetype in register for data {}.", .{Archetype}));
        }

        fn findBucketIndex(comptime Archetype: type) usize {
            comptime var bucket_index: ?usize = null;
            inline for (Archetypes, 0..) |TestArchetype, field_index| {
                if (comptime archetype_utils.equal(TestArchetype, Archetype)) {
                    bucket_index = field_index;
                }
            }
            if (bucket_index == null) {
                @compileError(comptimePrint(
                    "Can't find bucket index for archetype {}: not declared in the registry.",
                    .{Archetype},
                ));
            }
            return bucket_index.?;
        }

        pub fn spawn(self: *Self, data: anytype) !entity_utils.Entity(findArchetype(@TypeOf(data))) {
            const Archetype = archetype_utils.Archetype(@TypeOf(data));
            const bucket_index = comptime findBucketIndex(Archetype);
            var reordered_data: Archetype = undefined;
            inline for (@typeInfo(@TypeOf(data)).@"struct".fields) |field| {
                const field_name = comptime archetype_utils.typeFieldInArchetype(Archetype, field.type);
                @field(reordered_data, field_name) = @field(data, field.name);
            }
            // @compileLog(.{ "archetype:", Archetype, "bucket:", @TypeOf(@field(self.bucket_map, comptimePrint("{}", .{bucket_index}))).Archetype });
            const entity = try @field(self.bucket_map, comptimePrint("{}", .{bucket_index})).spawn(reordered_data);
            return entity;
        }

        pub fn despawn(self: *Self, entity: anytype) !@TypeOf(entity).Archetype {
            const Archetype = @TypeOf(entity).Archetype;
            const bucket_index = comptime findBucketIndex(Archetype);
            return try @field(self.bucket_map, comptimePrint("{}", .{bucket_index})).despawn(entity) orelse {
                return RegistryError.InvalidEntity;
            };
        }

        pub fn add_components(self: *Self, entity: anytype, data: anytype) !entity_utils.Entity(
            findArchetype(archetype_utils.Combined(
                @TypeOf(entity).Archetype,
                @TypeOf(data),
            )),
        ) {
            const Archetype = archetype_utils.Combined(@TypeOf(entity).Archetype, @TypeOf(data));
            const prev_bucket_index = comptime findBucketIndex(@TypeOf(entity).Archetype);
            const prev_data = try @field(self.bucket_map, comptimePrint(
                "{}",
                .{prev_bucket_index},
            )).despawn(entity) orelse return RegistryError.InvalidEntity;

            var new_data: Archetype = undefined;

            inline for (@typeInfo(@TypeOf(entity).Archetype).@"struct".fields) |field| {
                const field_name = comptime archetype_utils.typeFieldInArchetype(Archetype, field.type);
                @field(new_data, field_name) = @field(prev_data, field.name);
            }
            inline for (@typeInfo(@TypeOf(data)).@"struct".fields) |field| {
                const field_name = comptime archetype_utils.typeFieldInArchetype(Archetype, field.type);
                @field(new_data, field_name) = @field(data, field.name);
            }

            const new_bucket_index = comptime findBucketIndex(Archetype);
            const new_entity = try @field(self.bucket_map, comptimePrint("{}", .{new_bucket_index})).spawn(new_data);

            return new_entity;
        }

        pub fn remove_components(self: *Self, entity: anytype, comptime ToRemove: type) !struct {
            entity: entity_utils.Entity(archetype_utils.Diff(ToRemove, @TypeOf(entity).Archetype)),
            components: archetype_utils.Archetype(ToRemove),
        } {
            const Archetype = archetype_utils.Diff(ToRemove, @TypeOf(entity).Archetype);
            const prev_bucket_index = comptime findBucketIndex(@TypeOf(entity).Archetype);
            const prev_data = try @field(self.bucket_map, comptimePrint(
                "{}",
                .{prev_bucket_index},
            )).despawn(entity) orelse return RegistryError.InvalidEntity;

            var new_data: Archetype = undefined;
            var removed_data: ToRemove = undefined;
            inline for (@typeInfo(Archetype).@"struct".fields) |field| {
                const field_name = comptime archetype_utils.typeFieldInArchetype(@TypeOf(entity).Archetype, field.type);
                @field(new_data, field.name) = @field(prev_data, field_name);
            }
            inline for (@typeInfo(ToRemove).@"struct".fields) |field| {
                const field_name = comptime archetype_utils.typeFieldInArchetype(@TypeOf(entity).Archetype, field.type);
                @field(removed_data, field.name) = @field(prev_data, field_name);
            }

            const new_bucket_index = comptime findBucketIndex(Archetype);
            const new_entity = try @field(self.bucket_map, comptimePrint("{}", .{new_bucket_index})).spawn(new_data);

            return .{
                .entity = new_entity,
                .components = removed_data,
            };
        }
    };
}
