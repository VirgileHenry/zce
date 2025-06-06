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
        } else if (char2 > char1) {
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
        if (field.type != type) @compileError(comptimePrint(
            "Unable to build archetype with non-type field: {} is {}.",
            .{ field.name, field.type },
        ));
        ordered_fields[field_index] = field;
        inline for (field_index - 1..0) |check_index| {
            if (ordered_fields[check_index].type == ordered_fields[check_index + 1].type) @compileError(comptimePrint(
                "Unable to build archetype with duplicate type at {} and {}.",
                .{ ordered_fields[check_index].name, ordered_fields[check_index + 1].name },
            ));
            if (comptime typeOrd(ordered_fields[check_index + 1].type, ordered_fields[check_index])) {
                const temp = ordered_fields[check_index + 1];
                ordered_fields[check_index + 1] = ordered_fields[check_index];
                ordered_fields[check_index] = temp;
            }
        }
    }

    return @Type(Type{
        .@"struct"{
            .layout = Type.ContainerLayout.auto,
            .backing_integer = null,
            .fields = ordered_fields,
            .decls = {},
            .is_tuple = true,
        },
    });
}

/// Raises a compile error if the provided archetype type can't be used as a valid archetype.
///
/// A valid archetype is a set of types, meaning that for a type to be a valid archetype,
/// it must:
/// - Be a struct/tuple of types
/// - have no duplicates
pub fn checkArchetype(comptime archetype: type) void {
    const type_info = @typeInfo(archetype);

    switch (type_info) {
        .@"struct" => {},
        else => |other| @compileError(comptimePrint("Archetype shall be a struct/tuple of types, found {}.", .{other})),
    }

    const fields = type_info.@"struct".fields;

    inline for (fields) |field| {
        if (@TypeOf(field.type) != type) {
            @compileError(comptimePrint("Archetype is not a valid archetype: field {s} is of type {s}", .{ field.name, @typeName(field.type) }));
        }
    }

    inline for (fields, 0..) |field, field_index| {
        inline for (0..field_index) |check_index| {
            if (field.type == fields[check_index].type) {
                @compileError(comptimePrint("Archetype is not a valid archetype: index {} and {} are both of type {s}", .{ field_index, check_index, @typeName(field.type) }));
            }
        }
    }
}

fn typeInArchetype(comptime archetype: type, comptime @"type": type) bool {
    checkArchetype(archetype);
    const fields = @typeInfo(archetype).@"struct".fields;

    inline for (fields) |field| {
        if (field.type == @"type") return true;
    }

    return false;
}

pub fn exclusive(comptime archetype1: type, comptime archetype2: type) bool {
    checkArchetype(archetype1);
    checkArchetype(archetype2);

    const fields1 = @typeInfo(archetype1).@"struct".fields;
    inline for (fields1) |field1| {
        if (typeInArchetype(archetype2, field1.type)) return false;
    }

    const fields2 = @typeInfo(archetype2).@"struct".fields;
    inline for (fields2) |field2| {
        if (typeInArchetype(archetype1, field2.type)) return false;
    }

    return true;
}

pub fn isSub(comptime sub: type, comptime super: type) bool {
    checkArchetype(sub);
    checkArchetype(super);

    const sub_fields = @typeInfo(sub).@"struct".fields;

    inline for (sub_fields) |sub_field| {
        if (!typeInArchetype(super, sub_field.type)) return false;
    }

    return true;
}

pub fn equal(comptime archetype1: type, comptime archetype2: type) bool {
    checkArchetype(archetype1);
    checkArchetype(archetype2);

    const include = isSub(archetype1, archetype2);
    const included = isSub(archetype2, archetype1);

    return include and included;
}

pub fn Combined(comptime archetype1: type, comptime archetype2: type) type {
    checkArchetype(archetype1);
    checkArchetype(archetype2);
    if (!exclusive(archetype1, archetype2)) {
        @compileError(comptimePrint("Unable to combine non-exclusive archetypes: {} with {}.", .{ archetype1, archetype2 }));
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

    return @Type(std.builtin.Type{
        .@"struct" = std.builtin.Type.Struct{
            .layout = std.builtin.Type.ContainerLayout.auto,
            .fields = &combined_fields,
            .decls = &[0]std.builtin.Type.Declaration{},
            .is_tuple = true,
        },
    });
}
