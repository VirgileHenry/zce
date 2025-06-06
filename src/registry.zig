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
    archetype_utils.checkArchetype(archetype);

    return struct {
        const Self = @This();
        const Archetype = archetype;
        const BucketType = std.AutoArrayHashMap(usize, archetype);
        bucket: BucketType,
        last_id: usize,

        fn init(allocator: mem.Allocator) Self {
            return Self{
                .bucket = BucketType.init(allocator),
                .last_id = 0,
            };
        }

        fn spawn(self: *Self, data: Archetype) !entity_utils.Entity(Archetype) {
            const id = self.last_id;
            self.last_id += 1;
            try self.bucket.put(id, data);
            return entity_utils.Entity(Archetype).new(id);
        }

        fn despawn(self: *Self, entity: entity_utils.Entity(Archetype)) ?Archetype {
            return self.bucket.get(entity.id);
        }

        fn deinit(self: *Self) void {
            self.bucket.deinit();
        }
    };
}

pub fn Registry(comptime Archetypes: []const type) type {
    inline for (Archetypes, 0..) |archetype, archetype_index| {
        archetype_utils.checkArchetype(archetype);
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
        fn findArchetype(comptime TestArchetype: type) type {
            archetype_utils.checkArchetype(TestArchetype);
            inline for (Archetypes) |archetype| {
                if (archetype_utils.equal(archetype, TestArchetype)) {
                    return archetype;
                }
            }
            @compileError(comptimePrint("No matching archetype in register for data {}.", .{TestArchetype}));
        }

        fn findBucketIndex(comptime Archetype: type) usize {
            comptime var bucket_index: ?usize = null;
            inline for (Archetypes, 0..) |TestArchetype, field_index| {
                if (comptime archetype_utils.equal(TestArchetype, Archetype)) {
                    bucket_index = field_index;
                }
            }
            if (bucket_index == null) {
                @compileError(comptimePrint("Can't spawn entity: archetype not declared in the registry.", .{}));
            }
            return bucket_index.?;
        }

        pub fn spawn(self: *Self, data: anytype) !entity_utils.Entity(findArchetype(@TypeOf(data))) {
            const Archetype = @TypeOf(data);
            archetype_utils.checkArchetype(Archetype);
            const bucket_index = comptime findBucketIndex(Archetype);
            const entity = try @field(self.bucket_map, comptimePrint("{}", .{bucket_index})).spawn(data);
            return entity;
        }

        pub fn add_components(self: *Self, entity: anytype, data: anytype) !entity_utils.Entity(findArchetype(archetype_utils.Combined(@TypeOf(entity).Archetype, @TypeOf(data)))) {
            archetype_utils.checkArchetype(@TypeOf(data));
            archetype_utils.checkArchetype(@TypeOf(entity).Archetype);
            const Archetype = archetype_utils.Combined(@TypeOf(entity).Archetype, @TypeOf(data));
            archetype_utils.checkArchetype(Archetype);

            const prev_bucket_index = comptime findBucketIndex(@TypeOf(entity).Archetype);
            const prev_data = @field(self.bucket_map, comptimePrint("{}", .{prev_bucket_index})).despawn(entity) orelse return RegistryError.InvalidEntity;

            var combined_data: Archetype = undefined;

            const entity_data_fields = @typeInfo(@TypeOf(entity).Archetype).@"struct".fields;

            inline for (entity_data_fields) |field| {
                @field(combined_data, field.name) = @field(prev_data, field.name);
            }

            inline for (@typeInfo(@TypeOf(data)).@"struct".fields, entity_data_fields.len..) |field, field_index| {
                @field(combined_data, comptimePrint("{}", .{field_index})) = @field(data, field.name);
            }

            const new_bucket_index = comptime findBucketIndex(Archetype);
            const new_entity = try @field(self.bucket_map, comptimePrint("{}", .{new_bucket_index})).spawn(combined_data);

            return new_entity;
        }
    };
}
