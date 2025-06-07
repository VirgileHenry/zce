const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;

/// Creates an order on types, based on their name with @typeName.
/// If type1 is smaller, returns true. If type2 is smaller, return false.
/// If the order can't be decided (both type have the same name), throw a compile error.
fn typeOrd(comptime type1: type, comptime type2: type) bool {
    const name1 = @typeName(type1);
    const name2 = @typeName(type2);

    for (name1, name2) |char1, char2| {
        if (char1 < char2) {
            return true;
        } else if (char1 > char2) {
            return false;
        } else {
            continue;
        }
    }

    if (name1.len < name2.len) {
        return true;
    } else if (name1.len > name2.len) {
        return false;
    }

    @compileError(comptimePrint(
        "Can't decide order between types {s} and {s}",
        .{ name1, name2 },
    ));
}

/// Creates a new archetype from the given tuple of types.
pub fn Archetype(comptime archetype: type) type {
    const type_info = @typeInfo(archetype);

    switch (type_info) {
        .@"struct" => {},
        else => |other| @compileError(comptimePrint(
            "Unable to build archetype from {}.",
            .{other},
        )),
    }

    // An archetype is a set of types.
    // We can express them in the Zig type system as a sorted tuple of unique types.

    const Type = std.builtin.Type;
    const StructField = Type.StructField;
    const fields = type_info.@"struct".fields;

    comptime var ordered_fields = [_]StructField{undefined} ** fields.len;

    inline for (fields, 0..) |field, field_index| {
        if (@TypeOf(field.type) != type) @compileError(comptimePrint(
            "Unable to build archetype with non-type field: {s} is {}.",
            .{ field.name, field.type },
        ));
        ordered_fields[field_index] = field;
        ordered_fields[field_index].default_value_ptr = null;
        ordered_fields[field_index].is_comptime = false;
        inline for (0..field_index) |check_index| {
            const rev_index = field_index - check_index - 1;
            if (ordered_fields[rev_index].type == ordered_fields[rev_index + 1].type) @compileError(comptimePrint(
                "Unable to build archetype with duplicate type at {s} and {s}.",
                .{ ordered_fields[rev_index].name, ordered_fields[rev_index + 1].name },
            ));
            if (comptime typeOrd(ordered_fields[rev_index + 1].type, ordered_fields[rev_index].type)) {
                const temp = ordered_fields[rev_index + 1];
                ordered_fields[rev_index + 1] = ordered_fields[rev_index];
                ordered_fields[rev_index] = temp;
            }
        }
    }
    inline for (0..ordered_fields.len) |index| {
        ordered_fields[index].name = comptimePrint("{}", .{index});
    }

    return @Type(Type{
        .@"struct" = Type.Struct{
            .layout = Type.ContainerLayout.auto,
            .backing_integer = null,
            .fields = &ordered_fields,
            .decls = &[0]Type.Declaration{},
            .is_tuple = true,
        },
    });
}

fn typeInArchetype(comptime archetype: type, comptime @"type": type) bool {
    const fields = @typeInfo(Archetype(archetype)).@"struct".fields;

    inline for (fields) |field| {
        if (field.type == @"type") return true;
    }

    return false;
}

pub fn isSub(comptime sub: type, comptime super: type) bool {
    const sub_fields = @typeInfo(Archetype(sub)).@"struct".fields;

    inline for (sub_fields) |sub_field| {
        if (!typeInArchetype(super, sub_field.type)) return false;
    }

    return true;
}

pub fn equal(comptime archetype1: type, comptime archetype2: type) bool {
    const include = isSub(Archetype(archetype1), Archetype(archetype2));
    const included = isSub(Archetype(archetype2), Archetype(archetype1));

    return include and included;
}

pub fn Combined(comptime archetype1: type, comptime archetype2: type) type {
    const archetype_info1 = @typeInfo(archetype1).@"struct";
    const archetype_info2 = @typeInfo(archetype2).@"struct";

    const dummy_field = std.builtin.Type.StructField{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 0,
    };
    const total_field_count = archetype_info1.fields.len + archetype_info2.fields.len;
    comptime var combined_fields = [_]std.builtin.Type.StructField{dummy_field} ** total_field_count;
    inline for (archetype_info1.fields, 0..) |field, index| {
        combined_fields[index] = field;
    }
    inline for (archetype_info2.fields, archetype_info1.fields.len..) |field, index| {
        const new_field = std.builtin.Type.StructField{
            .name = comptimePrint("{}", .{index}),
            .type = field.type,
            .default_value_ptr = field.default_value_ptr,
            .is_comptime = field.is_comptime,
            .alignment = field.alignment,
        };
        combined_fields[index] = new_field;
    }

    const CombinedArchetypes = @Type(std.builtin.Type{
        .@"struct" = std.builtin.Type.Struct{
            .layout = std.builtin.Type.ContainerLayout.auto,
            .fields = &combined_fields,
            .decls = &[0]std.builtin.Type.Declaration{},
            .is_tuple = true,
        },
    });
    return Archetype(CombinedArchetypes);
}

pub fn Diff(comptime archetype1: type, comptime archetype2: type) type {
    if (!comptime isSub(archetype1, archetype2)) {
        @compileError(comptimePrint(
            "Can't make diff: {} is not sub of {}",
            .{ archetype1, archetype2 },
        ));
    }

    const archetype_info1 = @typeInfo(archetype1).@"struct";
    const archetype_info2 = @typeInfo(archetype2).@"struct";

    const dummy_field = std.builtin.Type.StructField{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 0,
    };
    const total_field_count = archetype_info2.fields.len - archetype_info1.fields.len;
    comptime var resulting_fields = [_]std.builtin.Type.StructField{dummy_field} ** total_field_count;
    comptime var index = 0;

    inline for (archetype_info2.fields) |field| {
        if (!typeInArchetype(archetype1, field.type)) {
            const new_field = std.builtin.Type.StructField{
                .name = comptimePrint("{}", .{index}),
                .type = field.type,
                .default_value_ptr = field.default_value_ptr,
                .is_comptime = field.is_comptime,
                .alignment = field.alignment,
            };
            resulting_fields[index] = new_field;
            index += 1;
        }
    }

    const DiffArchetype = @Type(std.builtin.Type{
        .@"struct" = std.builtin.Type.Struct{
            .layout = std.builtin.Type.ContainerLayout.auto,
            .fields = &resulting_fields,
            .decls = &[0]std.builtin.Type.Declaration{},
            .is_tuple = true,
        },
    });
    return Archetype(DiffArchetype);
}

/// For a given archetype, returns the name of the field that matches the given type.
pub fn typeFieldInArchetype(comptime archetype: type, comptime @"type": type) []const u8 {
    const fields = @typeInfo(Archetype(archetype)).@"struct".fields;
    inline for (fields) |field| {
        if (field.type == @"type") {
            return field.name;
        }
    }
    @compileError(comptimePrint(
        "Type {} not in archetype {}",
        .{ @"type", archetype },
    ));
}
