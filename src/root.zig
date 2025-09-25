///! Zig bindings for LevelDB, a fast key-value storage library.
///! This module provides a safe, idiomatic Zig interface to the LevelDB C API.
const std = @import("std");
const leveldb = @cImport({
    @cInclude("leveldb/c.h");
});

// Error type for LevelDB operations
/// Errors that can occur during LevelDB operations.
/// These correspond to the status codes returned by LevelDB's C API.
pub const Error = error{
    /// Database corruption detected.
    Corruption,
    /// Operation not implemented.
    NotImplemented,
    /// Invalid argument provided. Eg: attempt to open a database with invalid options
    InvalidArgument,
    /// I/O error occurred. Eg: fs permission error
    IOError,
    /// Unknown or other error.
    Unknown,
};

// Helper function to handle C errors
/// Internal function to handle errors from LevelDB C API calls.
/// Parses the error string and returns the appropriate Zig error.
fn handleError(errptr: ?[*:0]u8) Error!void {
    if (errptr) |state| {
        defer leveldb.leveldb_free(state);
        const msg = std.mem.span(state);
        // Unfortunately, this helpful error message is suppressed by this binding
        // std.debug.print("Error: {s}\n", .{msg});
        // Based on status.cc ToString(), the string starts with the type
        // (e.g., "NotFound: ", "Corruption: ", etc.)
        if (std.mem.startsWith(u8, msg, "Corruption")) {
            return Error.Corruption;
        } else if (std.mem.startsWith(u8, msg, "Not implemented")) {
            return Error.NotImplemented;
        } else if (std.mem.startsWith(u8, msg, "Invalid argument")) {
            return Error.InvalidArgument;
        } else if (std.mem.startsWith(u8, msg, "IO error")) {
            return Error.IOError;
        } else {
            return Error.Unknown; // Unknown or other errors
        }
    }
}

/// Represents a LevelDB database instance.
pub const DB = struct {
    inner: *leveldb.leveldb_t,

    /// Opens a LevelDB database with the given options and name.
    /// Returns an error if the database cannot be opened.
    pub fn open(options: *Options, name: [:0]const u8) Error!DB {
        var errptr: ?[*:0]u8 = null;
        const db = leveldb.leveldb_open(
            options.inner,
            name.ptr,
            @ptrCast(&errptr),
        );
        try handleError(errptr);
        return DB{ .inner = db.? };
    }

    /// Closes the database and frees associated resources.
    pub fn close(db: *DB) void {
        leveldb.leveldb_close(db.inner);
    }

    /// Stores a key-value pair in the database.
    pub fn put(db: *DB, options: *WriteOptions, key: []const u8, val: []const u8) Error!void {
        var errptr: ?[*:0]u8 = null;
        leveldb.leveldb_put(
            db.inner,
            options.inner,
            key.ptr,
            key.len,
            val.ptr,
            val.len,
            @ptrCast(&errptr),
        );
        try handleError(errptr);
    }

    /// Deletes a key from the database.
    pub fn delete(db: *DB, options: *WriteOptions, key: []const u8) Error!void {
        var errptr: ?[*:0]u8 = null;
        leveldb.leveldb_delete(
            db.inner,
            options.inner,
            key.ptr,
            key.len,
            @ptrCast(&errptr),
        );
        try handleError(errptr);
    }

    /// Applies a write batch to the database.
    pub fn write(db: *DB, options: *WriteOptions, batch: *WriteBatch) Error!void {
        var errptr: ?[*:0]u8 = null;
        leveldb.leveldb_write(
            db.inner,
            options.inner,
            batch.inner,
            @ptrCast(&errptr),
        );
        try handleError(errptr);
    }

    /// Retrieves the value associated with a key.
    /// Returns the value as a slice pointing to C-allocated memory, or null if the key is unknown.
    /// Warning: The returned slice must be freed with `free()` to avoid memory leaks.
    /// Returns null if the key is unknown.
    pub fn get(db: *DB, options: *ReadOptions, key: []const u8) Error!?[]const u8 {
        var vallen: usize = undefined;
        var errptr: ?[*:0]u8 = null;
        const val = leveldb.leveldb_get(
            db.inner,
            options.inner,
            key.ptr,
            key.len,
            &vallen,
            @ptrCast(&errptr),
        );
        if (val == null) return null;
        try handleError(errptr);
        return val[0..vallen];
    }

    /// Creates an iterator for traversing the database.
    pub fn createIterator(db: *DB, options: *ReadOptions) Iterator {
        return Iterator{
            .inner = leveldb.leveldb_create_iterator(
                db.inner,
                options.inner,
            ).?,
        };
    }

    /// Creates a snapshot of the current database state.
    pub fn createSnapshot(db: *DB) Snapshot {
        return Snapshot{
            .inner = leveldb.leveldb_create_snapshot(db.inner).?,
        };
    }

    /// Releases a snapshot.
    pub fn releaseSnapshot(db: *DB, snapshot: *Snapshot) void {
        leveldb.leveldb_release_snapshot(db.inner, snapshot.inner);
    }

    /// Retrieves the value of a database property.
    /// Returns the value as a slice pointing to C-allocated memory, or null if the key is unknown.
    /// Warning: The returned slice must be freed with `free()` to avoid memory leaks.
    /// Returns null if the property is unknown.
    pub fn propertyValue(db: *DB, propname: [:0]const u8) Error!?[]u8 {
        const val = leveldb.leveldb_property_value(
            db.inner,
            propname.ptr,
        );
        if (val == null) return null;
        const len = std.mem.len(val);
        return val[0..len];
    }

    /// Estimates the sizes of the data in the given key ranges.
    /// The sizes array must have the same length as ranges.
    pub fn approximateSizes(
        db: *DB,
        ranges: []const struct { start: []const u8, limit: []const u8 },
        sizes: []u64,
    ) void {
        const max_ranges = 1024;
        if (ranges.len == 0 or ranges.len > max_ranges or ranges.len != sizes.len) return;
        const num_ranges = @as(c_int, @intCast(ranges.len));
        // Prepare arrays for C API
        var start_ptrs: [max_ranges][*c]const u8 = undefined;
        var start_lens: [max_ranges]usize = undefined;
        var limit_ptrs: [max_ranges][*c]const u8 = undefined;
        var limit_lens: [max_ranges]usize = undefined;
        for (ranges, 0..) |range, i| {
            start_ptrs[i] = range.start.ptr;
            start_lens[i] = range.start.len;
            limit_ptrs[i] = range.limit.ptr;
            limit_lens[i] = range.limit.len;
        }
        leveldb.leveldb_approximate_sizes(
            db.inner,
            num_ranges,
            &start_ptrs,
            &start_lens,
            &limit_ptrs,
            &limit_lens,
            @as([*c]u64, @ptrCast(sizes.ptr)),
        );
    }

    /// Compacts the database in the given key range.
    pub fn compactRange(db: *DB, start: ?[]const u8, limit: ?[]const u8) void {
        const start_ptr = if (start) |s| s.ptr else null;
        const start_len = if (start) |s| s.len else 0;
        const limit_ptr = if (limit) |l| l.ptr else null;
        const limit_len = if (limit) |l| l.len else 0;
        leveldb.leveldb_compact_range(
            db.inner,
            start_ptr,
            start_len,
            limit_ptr,
            limit_len,
        );
    }
};

/// Represents a cache for LevelDB.
pub const Cache = struct {
    inner: *leveldb.leveldb_cache_t,

    /// Creates an LRU cache with the given capacity.
    pub fn createLru(capacity: usize) Cache {
        return Cache{
            .inner = leveldb.leveldb_cache_create_lru(capacity).?,
        };
    }

    /// Destroys the cache.
    pub fn destroy(cache: *Cache) void {
        leveldb.leveldb_cache_destroy(cache.inner);
    }
};

/// Represents a custom key comparator for LevelDB.
pub const Comparator = struct {
    inner: *leveldb.leveldb_comparator_t,

    /// Creates a custom comparator with the given callback functions.
    /// All callback functions must have callconv(.C).
    pub fn create(
        state: ?*anyopaque,
        destructor: ?*const fn (?*anyopaque) callconv(.C) void,
        compare: *const fn (?*anyopaque, [*c]const u8, usize, [*c]const u8, usize) callconv(.C) c_int,
        name: *const fn (?*anyopaque) callconv(.C) [*:0]const u8,
    ) Comparator {
        return Comparator{
            .inner = leveldb.leveldb_comparator_create(
                state,
                @ptrCast(destructor),
                @ptrCast(compare),
                @ptrCast(name),
            ).?,
        };
    }

    /// Destroys the comparator.
    pub fn destroy(comparator: *Comparator) void {
        leveldb.leveldb_comparator_destroy(comparator.inner);
    }
};

/// Represents the environment for LevelDB file operations.
pub const Env = struct {
    inner: *leveldb.leveldb_env_t,

    /// Creates the default environment.
    pub fn createDefault() Env {
        return Env{
            .inner = leveldb.leveldb_create_default_env().?,
        };
    }

    /// Destroys the environment.
    pub fn destroy(env: *Env) void {
        leveldb.leveldb_env_destroy(env.inner);
    }
};

/// Represents a filter policy for LevelDB.
pub const FilterPolicy = struct {
    inner: *leveldb.leveldb_filterpolicy_t,

    /// Creates a custom filter policy with the given callback functions.
    /// All callback functions must have callconv(.C).
    pub fn create(
        state: ?*anyopaque,
        destructor: ?*const fn (?*anyopaque) callconv(.C) void,
        create_filter: *const fn (?*anyopaque, [*c]const [*c]const u8, [*c]const usize, c_int, *usize) callconv(.C) [*c]u8,
        key_may_match: *const fn (?*anyopaque, [*c]const u8, usize, [*c]const u8, usize) callconv(.C) u8,
        name: *const fn (?*anyopaque) callconv(.C) [*:0]const u8,
    ) FilterPolicy {
        return FilterPolicy{
            .inner = leveldb.leveldb_filterpolicy_create(
                state,
                @ptrCast(destructor),
                @ptrCast(create_filter),
                @ptrCast(key_may_match),
                @ptrCast(name),
            ).?,
        };
    }

    /// Creates a bloom filter policy with the given bits per key.
    pub fn createBloom(bits_per_key: c_int) FilterPolicy {
        return FilterPolicy{
            .inner = leveldb.leveldb_filterpolicy_create_bloom(bits_per_key).?,
        };
    }

    /// Destroys the filter policy.
    pub fn destroy(filter_policy: *FilterPolicy) void {
        leveldb.leveldb_filterpolicy_destroy(filter_policy.inner);
    }
};

/// Represents an iterator for traversing a LevelDB database.
pub const Iterator = extern struct {
    inner: *leveldb.leveldb_iterator_t,

    /// Destroys the iterator.
    pub fn destroy(iter: *Iterator) void {
        leveldb.leveldb_iter_destroy(iter.inner);
    }

    /// Returns true if the iterator is positioned at a valid entry.
    pub fn valid(iter: *const Iterator) bool {
        return leveldb.leveldb_iter_valid(iter.inner) != 0;
    }

    /// Positions the iterator at the first key in the database.
    pub fn seekToFirst(iter: *Iterator) void {
        leveldb.leveldb_iter_seek_to_first(iter.inner);
    }

    /// Positions the iterator at the last key in the database.
    pub fn seekToLast(iter: *Iterator) void {
        leveldb.leveldb_iter_seek_to_last(iter.inner);
    }

    /// Positions the iterator at the given key or the next greater key.
    pub fn seek(iter: *Iterator, k: []const u8) void {
        leveldb.leveldb_iter_seek(
            iter.inner,
            k.ptr,
            k.len,
        );
    }

    /// Advances the iterator to the next key.
    pub fn next(iter: *Iterator) void {
        leveldb.leveldb_iter_next(iter.inner);
    }

    /// Moves the iterator to the previous key.
    pub fn prev(iter: *Iterator) void {
        leveldb.leveldb_iter_prev(iter.inner);
    }

    /// Returns the key of the current entry.
    /// Warning: The returned slice points to internal DB memory and is valid only until the next iterator modification
    /// (e.g., `next()`, `prev()`, `seek()`) or external DB modification (e.g., `put()`). Accessing it afterward is undefined behavior.
    /// Do not free the slice manually.
    pub fn key(iter: *const Iterator) []const u8 {
        var klen: usize = undefined;
        const key_ptr = leveldb.leveldb_iter_key(iter.inner, &klen);
        return key_ptr[0..klen];
    }

    /// Returns the value of the current entry.
    /// Warning: The returned slice points to internal DB memory and is valid only until the next iterator modification
    /// (e.g., `next()`, `prev()`, `seek()`) or external DB modification (e.g., `put()`). Accessing it afterward is undefined behavior.
    /// Do not free the slice manually.
    pub fn value(iter: *const Iterator) []const u8 {
        var vlen: usize = undefined;
        const val_ptr = leveldb.leveldb_iter_value(iter.inner, &vlen);
        return val_ptr[0..vlen];
    }

    /// Returns an error if the iterator has encountered one.
    pub fn getError(iter: *const Iterator) Error!void {
        var errptr: ?[*:0]u8 = null;
        leveldb.leveldb_iter_get_error(iter.inner, @ptrCast(&errptr));
        try handleError(errptr);
    }
};

pub const Logger = extern struct {
    inner: *leveldb.leveldb_logger_t,
};

/// Represents options for configuring a LevelDB database.
pub const Options = extern struct {
    inner: *leveldb.leveldb_options_t,

    /// Creates a new options instance with default settings.
    pub fn create() Options {
        return Options{
            .inner = leveldb.leveldb_options_create().?,
        };
    }

    /// Destroys the options instance.
    pub fn destroy(options: *Options) void {
        leveldb.leveldb_options_destroy(options.inner);
    }

    /// Sets the comparator for key ordering.
    pub fn setComparator(options: *Options, comparator: *Comparator) void {
        leveldb.leveldb_options_set_comparator(options.inner, comparator.inner);
    }

    /// Sets the filter policy for filtering keys.
    pub fn setFilterPolicy(options: *Options, filter_policy: *FilterPolicy) void {
        leveldb.leveldb_options_set_filter_policy(options.inner, filter_policy.inner);
    }

    /// Sets whether to create the database if it doesn't exist.
    pub fn setCreateIfMissing(options: *Options, value: bool) void {
        leveldb.leveldb_options_set_create_if_missing(options.inner, if (value) 1 else 0);
    }

    /// Sets whether to return an error if the database already exists.
    pub fn setErrorIfExists(options: *Options, value: bool) void {
        leveldb.leveldb_options_set_error_if_exists(options.inner, if (value) 1 else 0);
    }

    /// Sets whether to perform paranoid checks.
    pub fn setParanoidChecks(options: *Options, value: bool) void {
        leveldb.leveldb_options_set_paranoid_checks(options.inner, if (value) 1 else 0);
    }

    /// Sets the environment for file operations.
    pub fn setEnv(options: *Options, env: *Env) void {
        leveldb.leveldb_options_set_env(options.inner, env.inner);
    }

    /// Sets the logger for logging messages.
    pub fn setInfoLog(options: *Options, logger: *Logger) void {
        leveldb.leveldb_options_set_info_log(options.inner, logger.inner);
    }

    /// Sets the write buffer size.
    pub fn setWriteBufferSize(options: *Options, size: usize) void {
        leveldb.leveldb_options_set_write_buffer_size(options.inner, size);
    }

    /// Sets the maximum number of open files.
    pub fn setMaxOpenFiles(options: *Options, count: c_int) void {
        leveldb.leveldb_options_set_max_open_files(options.inner, count);
    }

    /// Sets the cache for block caching.
    pub fn setCache(options: *Options, cache: *Cache) void {
        leveldb.leveldb_options_set_cache(options.inner, cache.inner);
    }

    /// Sets the block size for SST files.
    pub fn setBlockSize(options: *Options, size: usize) void {
        leveldb.leveldb_options_set_block_size(options.inner, size);
    }

    /// Sets the block restart interval.
    pub fn setBlockRestartInterval(options: *Options, interval: c_int) void {
        leveldb.leveldb_options_set_block_restart_interval(options.inner, interval);
    }

    /// Sets the maximum file size.
    pub fn setMaxFileSize(options: *Options, size: usize) void {
        leveldb.leveldb_options_set_max_file_size(options.inner, size);
    }

    /// Sets the compression type.
    pub fn setCompression(options: *Options, compression: c_int) void {
        leveldb.leveldb_options_set_compression(options.inner, compression);
    }
};

/// Represents read options for database operations.
pub const ReadOptions = extern struct {
    inner: *leveldb.leveldb_readoptions_t,

    /// Creates a new read options instance.
    pub fn create() ReadOptions {
        return ReadOptions{
            .inner = leveldb.leveldb_readoptions_create().?,
        };
    }

    /// Destroys the read options instance.
    pub fn destroy(options: *ReadOptions) void {
        leveldb.leveldb_readoptions_destroy(options.inner);
    }

    /// Sets whether to verify checksums during reads.
    pub fn setVerifyChecksums(options: *ReadOptions, value: bool) void {
        leveldb.leveldb_readoptions_set_verify_checksums(options.inner, if (value) 1 else 0);
    }

    /// Sets whether to fill the cache during reads.
    pub fn setFillCache(options: *ReadOptions, value: bool) void {
        leveldb.leveldb_readoptions_set_fill_cache(options.inner, if (value) 1 else 0);
    }

    /// Sets the snapshot to read from.
    pub fn setSnapshot(options: *ReadOptions, snapshot: *const Snapshot) void {
        leveldb.leveldb_readoptions_set_snapshot(options.inner, snapshot.inner);
    }
};

/// Represents a snapshot of the database state.
/// Snapshots are created with DB.createSnapshot() and released with DB.releaseSnapshot().
pub const Snapshot = extern struct {
    inner: *const leveldb.leveldb_snapshot_t,
};

/// Represents a batch of write operations.
pub const WriteBatch = extern struct {
    inner: *leveldb.leveldb_writebatch_t,

    /// Creates a new write batch.
    pub fn create() WriteBatch {
        return WriteBatch{
            .inner = leveldb.leveldb_writebatch_create().?,
        };
    }

    /// Destroys the write batch.
    pub fn destroy(batch: *WriteBatch) void {
        leveldb.leveldb_writebatch_destroy(batch.inner);
    }

    /// Clears all operations from the batch.
    pub fn clear(batch: *WriteBatch) void {
        leveldb.leveldb_writebatch_clear(batch.inner);
    }

    /// Adds a put operation to the batch.
    pub fn put(batch: *WriteBatch, key: []const u8, val: []const u8) void {
        leveldb.leveldb_writebatch_put(
            batch.inner,
            key.ptr,
            key.len,
            @as([*c]const u8, @ptrCast(val.ptr)),
            val.len,
        );
    }

    /// Adds a delete operation to the batch.
    pub fn delete(batch: *WriteBatch, key: []const u8) void {
        leveldb.leveldb_writebatch_delete(
            batch.inner,
            key.ptr,
            key.len,
        );
    }

    /// Iterates over the operations in the batch, calling the provided callbacks.
    /// The callbacks must have callconv(.C).
    pub fn iterate(
        batch: *const WriteBatch,
        state: ?*anyopaque,
        put_fn: ?*const fn (?*anyopaque, [*c]const u8, usize, [*c]const u8, usize) callconv(.C) void,
        deleted_fn: ?*const fn (?*anyopaque, [*c]const u8, usize) callconv(.C) void,
    ) void {
        leveldb.leveldb_writebatch_iterate(
            batch.inner,
            state,
            @ptrCast(put_fn),
            @ptrCast(deleted_fn),
        );
    }

    /// Appends the operations from source to destination.
    pub fn append(destination: *WriteBatch, source: *const WriteBatch) void {
        leveldb.leveldb_writebatch_append(destination.inner, source.inner);
    }
};

/// Represents write options for database operations.
pub const WriteOptions = extern struct {
    inner: *leveldb.leveldb_writeoptions_t,

    /// Creates a new write options instance.
    pub fn create() WriteOptions {
        return WriteOptions{
            .inner = leveldb.leveldb_writeoptions_create().?,
        };
    }

    /// Destroys the write options instance.
    pub fn destroy(options: *WriteOptions) void {
        leveldb.leveldb_writeoptions_destroy(options.inner);
    }

    /// Sets whether to perform synchronous writes.
    pub fn setSync(options: *WriteOptions, value: bool) void {
        leveldb.leveldb_writeoptions_set_sync(options.inner, if (value) 1 else 0);
    }
};

// Global functions (not tied to a specific struct)

/// Destroys a LevelDB database, deleting all its files.
pub fn destroyDB(options: *Options, name: [:0]const u8) Error!void {
    var errptr: ?[*:0]u8 = null;
    leveldb.leveldb_destroy_db(options.inner, @as([*c]const u8, @ptrCast(name.ptr)), @as([*c][*c]u8, @ptrCast(&errptr)));
    try handleError(errptr);
}

/// Repairs a corrupted LevelDB database.
pub fn repairDB(options: *Options, name: [:0]const u8) Error!void {
    var errptr: ?[*:0]u8 = null;
    leveldb.leveldb_repair_db(options.inner, @as([*c]const u8, @ptrCast(name.ptr)), @as([*c][*c]u8, @ptrCast(&errptr)));
    try handleError(errptr);
}

/// Frees memory allocated by LevelDB.
/// Use this to free slices returned by functions like `DB.get()` and `DB.propertyName()`.
pub fn free(ptr: [*]const u8) void {
    leveldb.leveldb_free(@constCast(@ptrCast(ptr)));
}

// Version functions
/// Returns the major version number of LevelDB.
pub fn majorVersion() c_int {
    return leveldb.leveldb_major_version();
}

/// Returns the minor version number of LevelDB.
pub fn minorVersion() c_int {
    return leveldb.leveldb_minor_version();
}

test {
    std.testing.refAllDecls(@This());
}

/// Helper function to create a temporary database path for tests.
/// Caller is responsible for freeing the returned path.
fn tmpDbPath(allocator: std.mem.Allocator, tmp_dir: std.testing.TmpDir) ![:0]const u8 {
    const tmp_dir_path = try tmp_dir.parent_dir.realpathAlloc(allocator, &tmp_dir.sub_path);
    defer allocator.free(tmp_dir_path);

    return try std.fs.path.joinZ(allocator, &[_][]const u8{ tmp_dir_path, "test.db" });
}

test "basic put and get" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    const key = "test_key";
    const value = "test_value";
    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.put(&write_options, key, value);

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    const retrieved = try db.get(&read_options, key) orelse return error.KeyNotFound;
    defer free(retrieved.ptr);
    try std.testing.expectEqualStrings(value, retrieved);
}

test "delete key" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    const key = "test_key";
    const value = "test_value";
    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.put(&write_options, key, value);
    try db.delete(&write_options, key);

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    const retrieved = db.get(&read_options, key);
    try std.testing.expectEqual(null, retrieved);
}

test "non-existent key" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    const retrieved = db.get(&read_options, "nonexistent");
    try std.testing.expectEqual(null, retrieved);
}

test "invalid argument error - missing createIfMissing" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    defer options.destroy();
    // Try to open without setting createIfMissing and the DB doesn't exist
    const result = DB.open(&options, db_path);
    try std.testing.expectError(Error.InvalidArgument, result);
}

test "iterator seek and next" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.put(&write_options, "key1", "value1");
    try db.put(&write_options, "key2", "value2");

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    var iter = db.createIterator(&read_options);
    defer iter.destroy();

    iter.seekToFirst();
    try std.testing.expect(iter.valid());
    try std.testing.expectEqualStrings("key1", iter.key());
    try std.testing.expectEqualStrings("value1", iter.value());

    iter.next();
    try std.testing.expect(iter.valid());
    try std.testing.expectEqualStrings("key2", iter.key());
    try std.testing.expectEqualStrings("value2", iter.value());
}

test "write batch put and delete" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var batch = WriteBatch.create();
    defer batch.destroy();
    batch.put("batch_key", "batch_value");
    batch.delete("batch_key");

    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.write(&write_options, &batch);

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    const retrieved = db.get(&read_options, "batch_key");
    try std.testing.expectEqual(null, retrieved);
}

test "options setters" {
    var options = Options.create();
    defer options.destroy();

    options.setCreateIfMissing(true);
    options.setWriteBufferSize(1024 * 1024);
    options.setCompression(0);
    // Verify no errors (setters don't return values)
}

test "destroy db" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    db.close();

    try destroyDB(&options, db_path);
    // Verify DB directory is deleted (though tmp_dir.cleanup will handle it)
    // Opening again should fail since it was deleted
    options.setCreateIfMissing(false);
    const result = DB.open(&options, db_path);
    try std.testing.expectError(Error.InvalidArgument, result);
}

test "empty key and value" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.put(&write_options, "", "");

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    const retrieved = try db.get(&read_options, "") orelse return error.KeyNotFound;
    defer free(retrieved.ptr);
    try std.testing.expectEqualStrings("", retrieved);
}

test "overwrite key" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    const key = "test_key";
    const value1 = "value1";
    const value2 = "value2";
    var write_options = WriteOptions.create();
    defer write_options.destroy();

    // Put initial value
    try db.put(&write_options, key, value1);

    // Overwrite with new value
    try db.put(&write_options, key, value2);

    // Verify the new value is retrieved
    var read_options = ReadOptions.create();
    defer read_options.destroy();
    const retrieved = try db.get(&read_options, key) orelse return error.KeyNotFound;
    defer free(retrieved.ptr);
    try std.testing.expectEqualStrings(value2, retrieved);
}

test "iterator seek to last and prev" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.put(&write_options, "key1", "value1");
    try db.put(&write_options, "key2", "value2");
    try db.put(&write_options, "key3", "value3");

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    var iter = db.createIterator(&read_options);
    defer iter.destroy();

    iter.seekToLast();
    try std.testing.expect(iter.valid());
    try std.testing.expectEqualStrings("key3", iter.key());
    try std.testing.expectEqualStrings("value3", iter.value());

    iter.prev();
    try std.testing.expect(iter.valid());
    try std.testing.expectEqualStrings("key2", iter.key());
    try std.testing.expectEqualStrings("value2", iter.value());

    iter.prev();
    try std.testing.expect(iter.valid());
    try std.testing.expectEqualStrings("key1", iter.key());
    try std.testing.expectEqualStrings("value1", iter.value());
}

test "iterator seek to specific key" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.put(&write_options, "key1", "value1");
    try db.put(&write_options, "key2", "value2");
    try db.put(&write_options, "key3", "value3");

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    var iter = db.createIterator(&read_options);
    defer iter.destroy();

    iter.seek("key2");
    try std.testing.expect(iter.valid());
    try std.testing.expectEqualStrings("key2", iter.key());
    try std.testing.expectEqualStrings("value2", iter.value());
}

test "iterator validity past end" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.put(&write_options, "key1", "value1");

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    var iter = db.createIterator(&read_options);
    defer iter.destroy();

    iter.seekToFirst();
    try std.testing.expect(iter.valid());

    iter.next();
    try std.testing.expect(!iter.valid()); // Past end
}

test "iterator key/value lifetimes" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var write_options = WriteOptions.create();
    defer write_options.destroy();
    try db.put(&write_options, "key1", "value1");
    try db.put(&write_options, "key2", "value2");

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    var iter = db.createIterator(&read_options);
    defer iter.destroy();

    iter.seekToFirst();
    const key_slice = iter.key();
    const value_slice = iter.value();

    // Modify iterator
    iter.next();

    // The previous slices should still be valid since we haven't modified the DB
    try std.testing.expectEqualStrings("key1", key_slice);
    try std.testing.expectEqualStrings("value1", value_slice);
}

test "iterator get error" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try tmpDbPath(std.testing.allocator, tmp_dir);
    defer std.testing.allocator.free(db_path);

    var options = Options.create();
    options.setCreateIfMissing(true);
    defer options.destroy();
    var db = try DB.open(&options, db_path);
    defer db.close();

    var read_options = ReadOptions.create();
    defer read_options.destroy();
    var iter = db.createIterator(&read_options);
    defer iter.destroy();

    // Normal case: no error
    try iter.getError();

    // To test error, we might need to simulate corruption, but for now, just ensure it doesn't panic
}
