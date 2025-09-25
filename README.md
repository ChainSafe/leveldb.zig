# leveldb.zig

A minimal, idiomatic Zig wrapper around LevelDB's C API.

## Installation

1. Zig fetch
   ```bash
   zig fetch --save=leveldb git+https://github.com/chainsafe/leveldb.zig
   ```

2. In your `build.zig`, link the dependency
   ```zig
   const leveldb_module = b.dependency("leveldb", .{}).module("leveldb");
   my_module.addImport("leveldb", leveldb_module);
   ```

3. Import and use in your code:
   ```zig
   const leveldb = @import("leveldb");
   ```

## Quick Start

Here's a simple example to get you started:

```zig
const std = @import("std");
const leveldb = @import("leveldb");

pub fn main() !void {
    // Create options
    var options = leveldb.Options.create();
    defer options.destroy();
    options.setCreateIfMissing(true);

    // Open database
    var db = try leveldb.DB.open(&options, "/tmp/testdb");
    defer db.close();

    // Put a key-value pair
    var write_opts = leveldb.WriteOptions.create();
    defer write_opts.destroy();
    try db.put(&write_opts, "hello", "world");

    // Get the value
    var read_opts = leveldb.ReadOptions.create();
    defer read_opts.destroy();
    const value = try db.get(&read_opts, "hello");
    if (value) |v| {
        std.debug.print("Value: {s}\n", .{v});
        // IMPORTANT: Free the memory allocated by LevelDB
        leveldb.free(v.ptr);
    }
}
```

## API Overview

### Core Types

- **`DB`**: Main database handle for operations like `put`, `get`, `delete`.
- **`Options`**: Configuration for database creation (compression, cache, etc.).
- **`Iterator`**: For traversing key-value pairs in order.
- **`WriteBatch`**: Groups multiple write operations atomically.
- **`Snapshot`**: Provides consistent read views.
- **`Cache`**: LRU cache for block caching.
- **`Comparator`**: Custom key comparison logic.
- **`FilterPolicy`**: Bloom filter for read optimization.

### Key Functions

- **Database Management**: `DB.open()`, `DB.close()`, `destroyDB()`, `repairDB()`
- **CRUD Operations**: `DB.put()`, `DB.get()`, `DB.delete()`
- **Iteration**: `DB.createIterator()`, `Iterator.seek()`, `Iterator.next()`
- **Batching**: `WriteBatch.put()`, `DB.write()`
- **Snapshots**: `DB.createSnapshot()`, `ReadOptions.setSnapshot()`
- **Utilities**: `free()` for memory management

### Error Handling

All operations return `Error!T` where `Error` includes:
- `Corruption`: Database corruption
- `InvalidArgument`: Bad input
- `IOError`: File system issues
- `Unknown`: Other errors

## Examples

### Basic Operations

```zig
// Open database
var options = leveldb.Options.create();
options.setCreateIfMissing(true);
var db = try leveldb.DB.open(&options, "/tmp/mydb");

// Put and get
try db.put(&leveldb.WriteOptions.create(), "key1", "value1");
const val = try db.get(&leveldb.ReadOptions.create(), "key1");
if (val) |v| {
    // Use v...
    // Then free v
    leveldb.free(v);
}

// Delete
try db.delete(&leveldb.WriteOptions.create(), "key1");

// Close
db.close();
options.destroy();
```

### Using Iterators

```zig
var iter = db.createIterator(&leveldb.ReadOptions.create());
defer iter.destroy();

iter.seekToFirst();
while (iter.valid()) {
    const key = iter.key();
    const value = iter.value();
    // Process key/value (valid until next iterator move)
    std.debug.print("{s} = {s}\n", .{key, value});
    iter.next();
}
```

### Write Batches

```zig
var batch = leveldb.WriteBatch.create();
defer batch.destroy();

batch.put("key1", "val1");
batch.put("key2", "val2");
batch.delete("old_key");

try db.write(&leveldb.WriteOptions.create(), &batch);
```

### Snapshots

```zig
var snapshot = db.createSnapshot();
defer db.releaseSnapshot(&snapshot);

var read_opts = leveldb.ReadOptions.create();
read_opts.setSnapshot(&snapshot);
// Reads will see DB state at snapshot time
```

## Memory Management

⚠️ **Important**: Functions `DB.get()` and `DB.propertyValue()` return slices pointing to C-allocated memory. You **must** call `leveldb.free(slice)` after use to avoid memory leaks.

Iterator `key()` and `value()` return slices valid only until the next iterator operation or DB modification.

## License

MIT