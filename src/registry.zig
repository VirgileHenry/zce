const std = @import("std");
const mem = std.mem;
const comptimePrint = std.fmt.comptimePrint;

const entity_utils = @import("entity.zig");
const archetype_utils = @import("archetype.zig");

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

        fn deinit(self: *Self) void {
            self.bucket.deinit();
        }
    };
}

pub fn Registry(comptime archetypes: []const type) type {
    inline for (archetypes, 0..) |archetype, archetype_index| {
        archetype_utils.checkArchetype(archetype);
        inline for (archetypes[0..archetype_index], 0..) |previous_archetype, previous_index| {
            if (archetype_utils.equal(archetype, previous_archetype)) {
                @compileError(comptimePrint("Invalid archetypes for register: archetypes at index {} and {} are the same.", .{ archetype_index, previous_index }));
            }
        }
    }

    const dummy_field = std.builtin.Type.StructField{ .name = "", .type = void, .default_value_ptr = null, .is_comptime = false, .alignment = 0 };
    comptime var bucket_map_fields = [_]std.builtin.Type.StructField{dummy_field} ** archetypes.len;

    inline for (archetypes, 0..) |archetype, index| {
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
            inline for (archetypes, 0..) |archetype, field_index| {
                @field(bucket_map, comptimePrint("{}", .{field_index})) = ArchetypeBucket(archetype).init(allocator);
            }

            return .{
                .bucket_map = bucket_map,
            };
        }

        pub fn deinit(self: *Self) void {
            inline for (0..archetypes.len) |field_index| {
                @field(self.bucket_map, comptimePrint("{}", .{field_index})).deinit();
            }
        }

        /// `findArchetype` allows to get the real archetype type in the registry from the provided anytype.
        ///
        /// This is necessary to bypass comptime types not being recognized as valid archetypes.
        fn findArchetype(data: anytype) type {
            archetype_utils.checkArchetype(@TypeOf(data));
            inline for (archetypes) |archetype| {
                if (archetype_utils.equal(archetype, @TypeOf(data))) {
                    return archetype;
                }
            }
            @compileError(comptimePrint("No matching archetype in register for data {}.", .{@TypeOf(data)}));
        }

        pub fn spawn(self: *Self, data: anytype) !entity_utils.Entity(findArchetype(data)) {
            const archetype = @TypeOf(data);
            archetype_utils.checkArchetype(archetype);
            comptime var bucket_index: ?usize = null;
            inline for (archetypes, 0..) |test_archetype, field_index| {
                if (comptime archetype_utils.equal(test_archetype, archetype)) {
                    bucket_index = field_index;
                }
            }
            if (bucket_index == null) {
                @compileError(comptimePrint("Can't spawn entity: archetype not declared in the registry.", .{}));
            }
            const entity = try @field(self.bucket_map, comptimePrint("{}", .{bucket_index.?})).spawn(data);
            return entity;
        }

        pub fn add_components(self: *Self, entity: usize, comptime archetype: anytype) usize {
            _ = self;
            _ = entity;
            _ = archetype;
            return 0;
        }
    };
}
