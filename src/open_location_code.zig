const std = @import("std");

/// Character set for Open Location Code encoding (base 20)
pub const CODE_ALPHABET: []const u8 = "23456789CFGHJMPQRVWX";

/// Separator character appearing after 8th digit
pub const SEPARATOR: u8 = '+';

/// Padding character for short codes
pub const PADDING: u8 = '0';

/// Maximum code length (excluding separator)
pub const MAX_CODE_LENGTH: u8 = 15;

/// Default code length when not specified
pub const DEFAULT_CODE_LENGTH: u8 = 10;

/// Separator position in full codes
pub const SEPARATOR_POSITION: u8 = 8;

/// Encoding base
const ENCODING_BASE: f64 = 20.0;

/// Grid rows for refinement
const GRID_ROWS: f64 = 5.0;

/// Grid columns for refinement
const GRID_COLS: f64 = 4.0;

/// Pair code length (first 10 characters use pair encoding)
const PAIR_CODE_LENGTH: u8 = 10;

/// Represents a decoded Plus Code area
pub const CodeArea = struct {
    south_latitude: f64,
    west_longitude: f64,
    north_latitude: f64,
    east_longitude: f64,
    code_length: u8,

    pub fn center_latitude(self: CodeArea) f64 {
        return (self.south_latitude + self.north_latitude) / 2.0;
    }

    pub fn center_longitude(self: CodeArea) f64 {
        return (self.west_longitude + self.east_longitude) / 2.0;
    }
};

/// Errors that can occur
pub const OlcError = error{
    InvalidCode,
    InvalidLength,
    BufferTooSmall,
};

/// Encode latitude/longitude to Plus Code
pub fn encode(lat: f64, lng: f64, code_length: u8, buffer: []u8) OlcError!usize {
    var length = code_length;
    if (length < 2) length = DEFAULT_CODE_LENGTH;
    if (length > MAX_CODE_LENGTH) length = MAX_CODE_LENGTH;
    if (length < SEPARATOR_POSITION and length % 2 == 1) length += 1;

    const required: usize = @as(usize, length) + 1;
    if (buffer.len < required) return OlcError.BufferTooSmall;

    // Clamp and normalize coordinates
    var latitude = @min(90.0, @max(-90.0, lat));
    var longitude = normalizeL(lng);

    // Adjust if at pole
    if (latitude == 90.0) {
        latitude -= computeRes(length);
    }

    // Shift to positive
    latitude += 90.0;
    longitude += 180.0;

    var idx: usize = 0;
    var digit: u8 = 0;

    // Pair encoding (first 10 digits, 5 pairs)
    var lat_val = latitude;
    var lng_val = longitude;
    var res: f64 = ENCODING_BASE;

    while (digit < length and digit < PAIR_CODE_LENGTH) {
        // Latitude digit
        res = pairRes(digit);
        var lat_digit = @as(usize, @intFromFloat(@floor(lat_val / res)));
        if (lat_digit >= CODE_ALPHABET.len) lat_digit = CODE_ALPHABET.len - 1;
        lat_val = @mod(lat_val, res);
        buffer[idx] = CODE_ALPHABET[lat_digit];
        idx += 1;
        digit += 1;

        // Separator after 8
        if (digit == SEPARATOR_POSITION) {
            buffer[idx] = SEPARATOR;
            idx += 1;
        }

        if (digit >= length) break;

        // Longitude digit
        var lng_digit = @as(usize, @intFromFloat(@floor(lng_val / res)));
        if (lng_digit >= CODE_ALPHABET.len) lng_digit = CODE_ALPHABET.len - 1;
        lng_val = @mod(lng_val, res);
        buffer[idx] = CODE_ALPHABET[lng_digit];
        idx += 1;
        digit += 1;

        if (digit == SEPARATOR_POSITION) {
            buffer[idx] = SEPARATOR;
            idx += 1;
        }
    }

    // Pad if needed
    while (digit < SEPARATOR_POSITION) {
        buffer[idx] = PADDING;
        idx += 1;
        digit += 1;
        if (digit == SEPARATOR_POSITION) {
            buffer[idx] = SEPARATOR;
            idx += 1;
        }
    }

    // Grid encoding (digits 11+)
    if (length > PAIR_CODE_LENGTH) {
        const lat_res_base = pairRes(PAIR_CODE_LENGTH - 2);
        const lng_res_base = lat_res_base;
        var grid_lat = lat_val;
        var grid_lng = lng_val;
        var step: u8 = 0;

        while (digit < length) {
            const lat_step = lat_res_base / std.math.pow(f64, GRID_ROWS, @as(f64, @floatFromInt(step + 1)));
            const lng_step = lng_res_base / std.math.pow(f64, GRID_COLS, @as(f64, @floatFromInt(step + 1)));

            var row = @as(usize, @intFromFloat(@floor(grid_lat / lat_step)));
            var col = @as(usize, @intFromFloat(@floor(grid_lng / lng_step)));
            if (row >= 5) row = 4;
            if (col >= 4) col = 3;

            const grid_val = row * 4 + col;
            buffer[idx] = CODE_ALPHABET[grid_val];
            idx += 1;
            digit += 1;
            step += 1;

            grid_lat = @mod(grid_lat, lat_step);
            grid_lng = @mod(grid_lng, lng_step);
        }
    }

    return idx;
}

/// Encode with default length
pub fn encode_default(lat: f64, lng: f64, buffer: []u8) OlcError![]u8 {
    const len = try encode(lat, lng, DEFAULT_CODE_LENGTH, buffer);
    return buffer[0..len];
}

/// Check if code is valid
pub fn is_valid(code: []const u8) bool {
    if (code.len < 2) return false;

    var sep_found = false;
    var sep_pos: usize = 0;
    var padding = false;

    for (code, 0..) |c, i| {
        if (c == SEPARATOR) {
            if (sep_found) return false;
            if (i > SEPARATOR_POSITION or i % 2 == 1) return false;
            sep_found = true;
            sep_pos = i;
            continue;
        }
        if (c == PADDING) {
            if (sep_found) return false;
            padding = true;
            continue;
        }
        if (padding) return false;

        var valid = false;
        for (CODE_ALPHABET) |a| {
            if (c == a) {
                valid = true;
                break;
            }
        }
        if (!valid) return false;
    }

    return true;
}

/// Check if full code
pub fn is_full(code: []const u8) bool {
    if (!is_valid(code)) return false;
    for (code, 0..) |c, i| {
        if (c == SEPARATOR) return i == SEPARATOR_POSITION;
    }
    return false;
}

/// Check if short code
pub fn is_short(code: []const u8) bool {
    if (!is_valid(code)) return false;
    for (code, 0..) |c, i| {
        if (c == SEPARATOR) return i < SEPARATOR_POSITION;
    }
    return true;
}

/// Decode Plus Code to area
pub fn decode(code: []const u8) OlcError!CodeArea {
    if (!is_full(code)) return OlcError.InvalidCode;

    var clean: [MAX_CODE_LENGTH]u8 = undefined;
    var clen: usize = 0;
    for (code) |c| {
        if (c != SEPARATOR and c != PADDING) {
            clean[clen] = c;
            clen += 1;
        }
    }

    var south: f64 = 0;
    var west: f64 = 0;
    var lat_res: f64 = ENCODING_BASE;
    var lng_res: f64 = ENCODING_BASE;

    // Pair decode
    var i: usize = 0;
    while (i < clen and i < PAIR_CODE_LENGTH) {
        lat_res /= ENCODING_BASE;
        lng_res /= ENCODING_BASE;
        south += @as(f64, @floatFromInt(charVal(clean[i]))) * lat_res * ENCODING_BASE;
        i += 1;
        if (i < clen) {
            west += @as(f64, @floatFromInt(charVal(clean[i]))) * lng_res * ENCODING_BASE;
            i += 1;
        }
    }

    // Grid decode
    while (i < clen) {
        lat_res /= GRID_ROWS;
        lng_res /= GRID_COLS;
        const v = charVal(clean[i]);
        const row = v / 4;
        const col = v % 4;
        south += @as(f64, @floatFromInt(row)) * lat_res;
        west += @as(f64, @floatFromInt(col)) * lng_res;
        i += 1;
    }

    return CodeArea{
        .south_latitude = south - 90.0,
        .west_longitude = west - 180.0,
        .north_latitude = south - 90.0 + lat_res,
        .east_longitude = west - 180.0 + lng_res,
        .code_length = @intCast(clen),
    };
}

// Helpers
fn normalizeL(lng: f64) f64 {
    var r = lng;
    while (r < -180.0) r += 360.0;
    while (r >= 180.0) r -= 360.0;
    return r;
}

fn pairRes(digit: u8) f64 {
    const pair = digit / 2;
    return ENCODING_BASE / std.math.pow(f64, ENCODING_BASE, @as(f64, @floatFromInt(pair)));
}

fn computeRes(len: u8) f64 {
    if (len <= PAIR_CODE_LENGTH) {
        const pairs: i32 = @as(i32, len / 2);
        return std.math.pow(f64, ENCODING_BASE, @as(f64, @floatFromInt(2 - pairs)));
    }
    const grid_steps = len - PAIR_CODE_LENGTH;
    return std.math.pow(f64, ENCODING_BASE, -3.0) / std.math.pow(f64, GRID_ROWS, @as(f64, @floatFromInt(grid_steps)));
}

fn charVal(c: u8) u8 {
    for (CODE_ALPHABET, 0..) |a, i| {
        if (c == a) return @intCast(i);
    }
    return 0;
}

// Tests
test "encode San Francisco" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 10, &buf);
    try std.testing.expectEqualStrings("849VQHFJ+X6", buf[0..len]);
}

test "encode London" {
    var buf: [20]u8 = undefined;
    const len = try encode(51.5074, -0.1278, 10, &buf);
    try std.testing.expectEqualStrings("9C3XGV4C+XV", buf[0..len]);
}

test "encode Tokyo" {
    var buf: [20]u8 = undefined;
    const len = try encode(35.6762, 139.6503, 10, &buf);
    try std.testing.expectEqualStrings("8Q7XMMG2+F4", buf[0..len]);
}

test "is_valid" {
    try std.testing.expect(is_valid("849VQHFJ+X6"));
    try std.testing.expect(!is_valid(""));
}

test "is_full" {
    try std.testing.expect(is_full("849VQHFJ+X6"));
}

test "decode roundtrip" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 10, &buf);
    const area = try decode(buf[0..len]);
    try std.testing.expect(area.center_latitude() > 37.77);
    try std.testing.expect(area.center_latitude() < 37.78);
}

test "encode Sydney" {
    var buf: [20]u8 = undefined;
    const len = try encode(-33.8688, 151.2093, 10, &buf);
    try std.testing.expectEqualStrings("4RRH46J5+FP", buf[0..len]);
}

test "encode Moscow" {
    var buf: [20]u8 = undefined;
    const len = try encode(55.7558, 37.6173, 10, &buf);
    try std.testing.expectEqualStrings("9G7VQJ48+8W", buf[0..len]);
}

test "encode Mexico City" {
    var buf: [20]u8 = undefined;
    const len = try encode(19.4326, -99.1332, 10, &buf);
    try std.testing.expectEqualStrings("76F2CVM8+2P", buf[0..len]);
}

test "encode North Pole" {
    var buf: [20]u8 = undefined;
    const len = try encode(90.0, 0.0, 10, &buf);
    // Should not panic at pole
    try std.testing.expect(len > 0);
}

test "encode South Pole" {
    var buf: [20]u8 = undefined;
    const len = try encode(-90.0, 0.0, 10, &buf);
    try std.testing.expect(len > 0);
}

test "encode date line positive" {
    var buf: [20]u8 = undefined;
    const len = try encode(0.0, 180.0, 10, &buf);
    try std.testing.expect(len > 0);
}

test "encode date line negative" {
    var buf: [20]u8 = undefined;
    const len = try encode(0.0, -180.0, 10, &buf);
    try std.testing.expect(len > 0);
}

test "encode origin" {
    var buf: [20]u8 = undefined;
    const len = try encode(0.0, 0.0, 10, &buf);
    try std.testing.expectEqualStrings("6FG22222+22", buf[0..len]);
}

test "short code length 4" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 4, &buf);
    try std.testing.expect(len == 9); // 4 chars + 4 padding + separator
}

test "short code length 6" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 6, &buf);
    try std.testing.expect(len == 9); // 6 chars + 2 padding + separator
}

test "is_short detection" {
    try std.testing.expect(!is_short("849VQHFJ+X6")); // full code
    try std.testing.expect(is_short("QHFJ+X6")); // short code
}

test "invalid codes" {
    try std.testing.expect(!is_valid(""));
    try std.testing.expect(!is_valid("A")); // too short
    try std.testing.expect(!is_valid("849VQHFJ++X6")); // double separator
    try std.testing.expect(!is_valid("849+VQHFJ")); // separator in wrong position (odd)
}

test "decode center accuracy" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 10, &buf);
    const area = try decode(buf[0..len]);

    // Center should be within ~0.0001 degrees of input
    const lat_diff = @abs(area.center_latitude() - 37.7749);
    const lng_diff = @abs(area.center_longitude() - (-122.4194));

    try std.testing.expect(lat_diff < 0.001);
    try std.testing.expect(lng_diff < 0.001);
}
