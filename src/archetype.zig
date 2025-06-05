const std = @import("std");
const comptimePrint = std.fmt.comptimePrint;

/// Raises a compile error if the provided archetype type can't be used as a valid archetype.
///
/// A valid archetype is a set of types, meaning that for a type to be a valid archetype,
/// it must:
/// - Be a tuple of types
/// - have no duplicates
pub fn checkArchetype(comptime archetype: type) void {
    const fields = @typeInfo(archetype).@"struct".fields;

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
        if (typeInArchetype(archetype2, field1)) return false;
    }

    const fields2 = @typeInfo(archetype2).@"struct".fields;
    inline for (fields2) |field2| {
        if (typeInArchetype(archetype1, field2)) return false;
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
