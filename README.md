# Open Location Code (Plus Codes) for Zig

A pure Zig implementation of [Google's Open Location Code](https://github.com/google/open-location-code) (Plus Codes) - a geocoding system for identifying any location on Earth.

## Features

- **Pure Zig** - No dependencies, works with Zig 0.15+
- **Zero allocations** - All encoding uses caller-provided buffers
- **Fully tested** - 30 tests including table-driven reference cities, edge cases, and fuzz tests
- **Complete API** - encode, decode, validate, full/short code detection

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .open_location_code = .{
        .url = "https://github.com/bmorphism/open-location-code-zig/archive/refs/tags/v1.0.0.tar.gz",
        .hash = "open_location_code-1.0.0-0pnGtZ5pAADexp2bUTRnLu90RwlaA1lxh7_pY5p2Zekh",
    },
},
```

Then in your `build.zig`:

```zig
const olc = b.dependency("open_location_code", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("olc", olc.module("olc"));
```

## Usage

```zig
const olc = @import("olc");

pub fn main() void {
    var buffer: [20]u8 = undefined;

    // Encode coordinates to Plus Code
    const len = olc.encode(37.7749, -122.4194, 10, &buffer) catch return;
    const code = buffer[0..len];
    // code = "849VQHFJ+X6"

    // Decode Plus Code to area
    const area = olc.decode("849VQHFJ+X6") catch return;
    std.debug.print("Center: {d}, {d}\n", .{
        area.center_latitude(),
        area.center_longitude(),
    });

    // Validate codes
    _ = olc.is_valid("849VQHFJ+X6");  // true
    _ = olc.is_full("849VQHFJ+X6");   // true
    _ = olc.is_short("QHFJ+X6");      // true
}
```

## API Reference

### `encode(lat: f64, lng: f64, code_length: u8, buffer: []u8) !usize`

Encodes latitude/longitude to a Plus Code. Returns the number of bytes written.

- `lat`: Latitude (-90 to 90)
- `lng`: Longitude (-180 to 180)
- `code_length`: Desired code length (2-15, default 10)
- `buffer`: Output buffer (minimum 12 bytes for length 10)

### `decode(code: []const u8) !CodeArea`

Decodes a Plus Code to a `CodeArea` struct with:
- `south_latitude`, `north_latitude`
- `west_longitude`, `east_longitude`
- `center_latitude()`, `center_longitude()` methods

### `is_valid(code: []const u8) bool`

Returns true if the code is a valid Plus Code.

### `is_full(code: []const u8) bool`

Returns true if the code is a full (not shortened) Plus Code.

### `is_short(code: []const u8) bool`

Returns true if the code is a shortened Plus Code.

## Examples

| Location | Coordinates | Plus Code |
|----------|-------------|-----------|
| San Francisco | 37.7749, -122.4194 | 849VQHFJ+X6 |
| London | 51.5074, -0.1278 | 9C3XGV4C+XV |
| Tokyo | 35.6762, 139.6503 | 8Q7XMMG2+F4 |
| Sydney | -33.8688, 151.2093 | 4RRH46J5+FP |
| Origin (0,0) | 0.0, 0.0 | 6FG22222+22 |

## Running Tests

```bash
zig build test
```

## License

Apache License 2.0 - See [LICENSE](LICENSE)

## Author

Barton Rhodes <freemorphism+zig@gmail.com>

## Credits

Based on [Google's Open Location Code](https://github.com/google/open-location-code) specification.
Cross-validated against Python and Go reference implementations.
