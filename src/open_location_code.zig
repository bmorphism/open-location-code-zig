//! Open Location Code (Plus Codes) for Zig
//!
//! A pure Zig implementation of Google's Open Location Code geocoding system.
//! Plus Codes provide a simple way to identify any location on Earth.
//!
//! ## Example
//! ```zig
//! const olc = @import("open_location_code");
//!
//! var buffer: [20]u8 = undefined;
//! const len = try olc.encode(37.7749, -122.4194, 10, &buffer);
//! const code = buffer[0..len]; // "849VQHFJ+X6"
//!
//! const area = try olc.decode("849VQHFJ+X6");
//! const lat = area.center_latitude(); // ~37.7749
//! const lng = area.center_longitude(); // ~-122.4194
//! ```

const std = @import("std");

// =============================================================================
// Constants
// =============================================================================

/// The 20 valid characters for Plus Code encoding.
/// Excludes easily confused characters: A, I, L, O.
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

// =============================================================================
// Types
// =============================================================================

/// Represents a decoded Plus Code area with bounding box coordinates.
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

/// Errors that can occur during encoding/decoding.
pub const OlcError = error{
    /// The code is not a valid Plus Code format.
    InvalidCode,
    /// The requested code length is invalid.
    InvalidLength,
    /// The provided buffer is too small for the result.
    BufferTooSmall,
};

// =============================================================================
// Public API
// =============================================================================

/// Encodes a latitude/longitude pair to a Plus Code.
///
/// - `lat`: Latitude in degrees (-90 to 90). Values outside range are clamped.
/// - `lng`: Longitude in degrees. Values are normalized to (-180, 180].
/// - `code_length`: Desired code length (2-15). Default is 10 if < 2.
/// - `buffer`: Output buffer. Must be at least `code_length + 1` bytes.
///
/// Returns the number of bytes written to the buffer.
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

/// Encodes a latitude/longitude pair to a Plus Code with default length (10).
/// Returns a slice of the buffer containing the code.
pub fn encode_default(lat: f64, lng: f64, buffer: []u8) OlcError![]u8 {
    const len = try encode(lat, lng, DEFAULT_CODE_LENGTH, buffer);
    return buffer[0..len];
}

/// Returns true if the code is a valid Plus Code (full or short).
/// Checks format, character set, separator position, and padding rules.
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

/// Returns true if the code is a full (not shortened) Plus Code.
/// Full codes have the separator at position 8.
pub fn is_full(code: []const u8) bool {
    if (!is_valid(code)) return false;
    for (code, 0..) |c, i| {
        if (c == SEPARATOR) return i == SEPARATOR_POSITION;
    }
    return false;
}

/// Returns true if the code is a shortened Plus Code.
/// Short codes have the separator before position 8.
pub fn is_short(code: []const u8) bool {
    if (!is_valid(code)) return false;
    for (code, 0..) |c, i| {
        if (c == SEPARATOR) return i < SEPARATOR_POSITION;
    }
    return true;
}

/// Decodes a full Plus Code to a CodeArea with bounding box coordinates.
/// Returns error.InvalidCode if the code is not a valid full code.
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

// =============================================================================
// Internal Helpers
// =============================================================================

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

// =============================================================================
// Tests
// =============================================================================

const TestCase = struct {
    lat: f64,
    lng: f64,
    expected: []const u8,
    name: []const u8,
};

// Reference test cases cross-validated with Python/Go implementations
const encoding_tests = [_]TestCase{
    .{ .lat = 0.0, .lng = 0.0, .expected = "6FG22222+22", .name = "Origin" },
    .{ .lat = 37.7749, .lng = -122.4194, .expected = "849VQHFJ+X6", .name = "San Francisco" },
    .{ .lat = 51.5074, .lng = -0.1278, .expected = "9C3XGV4C+XV", .name = "London" },
    .{ .lat = 35.6762, .lng = 139.6503, .expected = "8Q7XMMG2+F4", .name = "Tokyo" },
    .{ .lat = -33.8688, .lng = 151.2093, .expected = "4RRH46J5+FP", .name = "Sydney" },
    .{ .lat = 55.7558, .lng = 37.6173, .expected = "9G7VQJ48+8W", .name = "Moscow" },
    .{ .lat = 19.4326, .lng = -99.1332, .expected = "76F2CVM8+2P", .name = "Mexico City" },
    .{ .lat = -22.9068, .lng = -43.1729, .expected = "589R3RVG+7R", .name = "Rio de Janeiro" },
    .{ .lat = 48.8566, .lng = 2.3522, .expected = "8FW4V942+JV", .name = "Paris" },
    .{ .lat = 40.7128, .lng = -74.0060, .expected = "87G7PX7V+4H", .name = "New York" },
    .{ .lat = 1.3521, .lng = 103.8198, .expected = "6PH59R29+RW", .name = "Singapore" },
    .{ .lat = 25.2048, .lng = 55.2708, .expected = "7HQQ673C+W8", .name = "Dubai" },
};

test "encode: reference cities" {
    var buf: [20]u8 = undefined;
    for (encoding_tests) |tc| {
        const len = try encode(tc.lat, tc.lng, 10, &buf);
        try std.testing.expectEqualStrings(tc.expected, buf[0..len]);
    }
}

test "decode: roundtrip all reference cities" {
    var buf: [20]u8 = undefined;
    for (encoding_tests) |tc| {
        const len = try encode(tc.lat, tc.lng, 10, &buf);
        const area = try decode(buf[0..len]);
        const lat_diff = @abs(area.center_latitude() - tc.lat);
        const lng_diff = @abs(area.center_longitude() - tc.lng);
        try std.testing.expect(lat_diff < 0.001);
        try std.testing.expect(lng_diff < 0.001);
    }
}

// Edge cases: poles, date line, extremes
test "edge: north pole" {
    var buf: [20]u8 = undefined;
    const len = try encode(90.0, 0.0, 10, &buf);
    try std.testing.expect(len > 0);
    const area = try decode(buf[0..len]);
    try std.testing.expect(area.north_latitude <= 90.0);
}

test "edge: south pole" {
    var buf: [20]u8 = undefined;
    const len = try encode(-90.0, 0.0, 10, &buf);
    try std.testing.expect(len > 0);
    const area = try decode(buf[0..len]);
    try std.testing.expect(area.south_latitude >= -90.0);
}

test "edge: date line +180" {
    var buf: [20]u8 = undefined;
    const len = try encode(0.0, 180.0, 10, &buf);
    try std.testing.expect(len > 0);
}

test "edge: date line -180" {
    var buf: [20]u8 = undefined;
    const len = try encode(0.0, -180.0, 10, &buf);
    try std.testing.expect(len > 0);
}

test "edge: wrap longitude > 180" {
    var buf1: [20]u8 = undefined;
    var buf2: [20]u8 = undefined;
    const len1 = try encode(0.0, 190.0, 10, &buf1);
    const len2 = try encode(0.0, -170.0, 10, &buf2);
    try std.testing.expectEqualStrings(buf2[0..len2], buf1[0..len1]);
}

test "edge: wrap longitude < -180" {
    var buf1: [20]u8 = undefined;
    var buf2: [20]u8 = undefined;
    const len1 = try encode(0.0, -190.0, 10, &buf1);
    const len2 = try encode(0.0, 170.0, 10, &buf2);
    try std.testing.expectEqualStrings(buf2[0..len2], buf1[0..len1]);
}

test "edge: clamp latitude > 90" {
    var buf1: [20]u8 = undefined;
    var buf2: [20]u8 = undefined;
    const len1 = try encode(95.0, 0.0, 10, &buf1);
    const len2 = try encode(90.0, 0.0, 10, &buf2);
    try std.testing.expectEqualStrings(buf2[0..len2], buf1[0..len1]);
}

test "edge: clamp latitude < -90" {
    var buf1: [20]u8 = undefined;
    var buf2: [20]u8 = undefined;
    const len1 = try encode(-95.0, 0.0, 10, &buf1);
    const len2 = try encode(-90.0, 0.0, 10, &buf2);
    try std.testing.expectEqualStrings(buf2[0..len2], buf1[0..len1]);
}

// Code length variations
test "length: 4 digits (padded)" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 4, &buf);
    try std.testing.expect(len == 9);
    try std.testing.expect(buf[4] == PADDING);
}

test "length: 6 digits (padded)" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 6, &buf);
    try std.testing.expect(len == 9);
}

test "length: 8 digits (no refinement)" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 8, &buf);
    try std.testing.expect(len == 9);
    try std.testing.expect(buf[8] == SEPARATOR);
}

test "length: 11 digits (grid refinement)" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 11, &buf);
    try std.testing.expect(len == 12);
}

test "length: max 15 digits" {
    var buf: [20]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 15, &buf);
    try std.testing.expect(len == 16);
}

// Validation tests
const valid_codes = [_][]const u8{
    "6FG22222+22",
    "849VQHFJ+X6",
    "9C3XGV4C+XV",
    "8FW4V75V+8QRXGVP",
    "8FW40000+",
    "8FW4+",
};

const invalid_codes = [_][]const u8{
    "",
    "A",
    "849VQHFJ++X6",
    "849+VQHFJ",
    "O49VQHFJ+X6", // O not in alphabet
    "I49VQHFJ+X6", // I not in alphabet
    "L49VQHFJ+X6", // L not in alphabet
    "A49VQHFJ+X6", // A not in alphabet
};

test "validate: valid codes" {
    for (valid_codes) |code| {
        try std.testing.expect(is_valid(code));
    }
}

test "validate: invalid codes" {
    for (invalid_codes) |code| {
        try std.testing.expect(!is_valid(code));
    }
}

test "validate: is_full" {
    try std.testing.expect(is_full("849VQHFJ+X6"));
    try std.testing.expect(is_full("6FG22222+22"));
    try std.testing.expect(!is_full("QHFJ+X6"));
    try std.testing.expect(!is_full("8FW4+"));
}

test "validate: is_short" {
    try std.testing.expect(is_short("QHFJ+X6"));
    try std.testing.expect(is_short("8FW4+"));
    try std.testing.expect(!is_short("849VQHFJ+X6"));
}

// Buffer size tests
test "buffer: too small returns error" {
    var buf: [5]u8 = undefined;
    const result = encode(37.7749, -122.4194, 10, &buf);
    try std.testing.expectError(OlcError.BufferTooSmall, result);
}

test "buffer: exact size works" {
    var buf: [11]u8 = undefined;
    const len = try encode(37.7749, -122.4194, 10, &buf);
    try std.testing.expect(len == 11);
}

// Decode error tests
test "decode: invalid code returns error" {
    const result = decode("invalid");
    try std.testing.expectError(OlcError.InvalidCode, result);
}

test "decode: short code returns error" {
    const result = decode("QHFJ+X6");
    try std.testing.expectError(OlcError.InvalidCode, result);
}

// CodeArea struct tests
test "CodeArea: bounds make sense" {
    const area = try decode("849VQHFJ+X6");
    try std.testing.expect(area.south_latitude < area.north_latitude);
    try std.testing.expect(area.west_longitude < area.east_longitude);
    try std.testing.expect(area.code_length == 10);
}

test "CodeArea: center is within bounds" {
    const area = try decode("849VQHFJ+X6");
    const center_lat = area.center_latitude();
    const center_lng = area.center_longitude();
    try std.testing.expect(center_lat >= area.south_latitude);
    try std.testing.expect(center_lat <= area.north_latitude);
    try std.testing.expect(center_lng >= area.west_longitude);
    try std.testing.expect(center_lng <= area.east_longitude);
}

// Precision tests
test "precision: longer codes have smaller areas" {
    const area8 = try decode("849VQHFJ+");
    const area10 = try decode("849VQHFJ+X6");

    const height8 = area8.north_latitude - area8.south_latitude;
    const height10 = area10.north_latitude - area10.south_latitude;

    try std.testing.expect(height10 < height8);
}

// Alphabet tests
test "alphabet: all 20 characters are valid" {
    for (CODE_ALPHABET) |c| {
        const code = [_]u8{ '8', '4', '9', 'V', 'Q', 'H', 'F', 'J', '+', c, '6' };
        try std.testing.expect(is_valid(&code));
    }
}

test "alphabet: excluded characters are invalid" {
    const excluded = "AILO";
    for (excluded) |c| {
        const code = [_]u8{ '8', '4', '9', 'V', 'Q', 'H', c, 'J', '+', 'X', '6' };
        try std.testing.expect(!is_valid(&code));
    }
}

// Fuzz test: random coordinates roundtrip
test "fuzz: 100 random coordinates roundtrip" {
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const random = prng.random();
    var buf: [20]u8 = undefined;

    for (0..100) |_| {
        const lat = random.float(f64) * 180.0 - 90.0;
        const lng = random.float(f64) * 360.0 - 180.0;

        const len = try encode(lat, lng, 10, &buf);
        const area = try decode(buf[0..len]);

        // Decoded center should be within 0.001 degrees
        const lat_diff = @abs(area.center_latitude() - lat);
        const lng_diff = @abs(area.center_longitude() - lng);

        try std.testing.expect(lat_diff < 0.001);
        try std.testing.expect(lng_diff < 0.001);
    }
}

// Fuzz test: all code lengths
test "fuzz: all code lengths 2-15" {
    var buf: [20]u8 = undefined;
    const lat: f64 = 37.7749;
    const lng: f64 = -122.4194;

    var length: u8 = 2;
    while (length <= 15) : (length += 1) {
        const len = try encode(lat, lng, length, &buf);
        try std.testing.expect(len > 0);

        // Codes >= 8 digits should be decodable
        if (length >= 8) {
            const area = try decode(buf[0..len]);
            try std.testing.expect(area.south_latitude < area.north_latitude);
        }
    }
}
