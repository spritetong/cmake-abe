const std = @import("std");
const builtin = @import("builtin");
const ArgIteratorGeneral = std.process.ArgIteratorGeneral(.{});

const ZigCommand = enum {
    const Self = @This();
    ar,
    cc,
    cxx,
    dlltool,
    ld,
    lib,
    objcopy,
    ranlib,
    rc,
    strip,

    fn fromStr(str: []const u8) ?Self {
        const map = std.StaticStringMap(ZigCommand).initComptime(.{
            .{ "ar", .ar },
            .{ "cc", .cc },
            .{ "c++", .cxx },
            .{ "dlltool", .dlltool },
            .{ "ld", .ld },
            .{ "lib", .lib },
            .{ "objcopy", .objcopy },
            .{ "ranlib", .ranlib },
            .{ "strip", .strip },
            .{ "rc", .rc },
            .{ "clang", .cc },
            .{ "clang++", .cxx },
            .{ "gcc", .cc },
            .{ "g++", .cxx },
        });
        return map.get(str);
    }

    fn toName(self: Self) []const u8 {
        return switch (self) {
            .cxx => "c++",
            .ld => "ld.lld",
            else => @tagName(self),
        };
    }

    fn toFlagsName(self: Self) ?[]const u8 {
        return switch (self) {
            .ar => "ARFLAGS",
            .cc => "CFLAGS",
            .cxx => "CXXFLAGS",
            .ld => "LDFLAGS",
            .ranlib => "RANLIBFLAGS",
            else => null,
        };
    }
};

pub const ZigArgFilter = union(enum) {
    const Self = @This();
    replace: []const []const u8,
    match_next_and_replace: struct { []const u8, []const []const u8 },

    pub const FilterTable = std.StaticStringMap([]const Self);
    pub const cc_filters = FilterTable.initComptime(.{
        // Linux system include paths
        .{ "-I/usr/include", &.{Self.replace_with(&.{ "-idirafter", "/usr/include" })} },
        .{ "-I/usr/local/include", &.{Self.replace_with(&.{ "-idirafter", "/usr/local/include" })} },
        // MSVC
        .{ "-Xlinker", &.{
            Self.skip_next("/MANIFEST:EMBED"),
            Self.skip_next("/version:0.0"),
        } },
        // --target <target>
        .{ "--target", &.{Self.skip_two} },
        // -m <target>, unknown Clang option: '-m'
        .{ "-m", &.{Self.skip_two} },
        // strip local symbols
        .{ "-Wl,-x", &.{Self.replace_with(&.{"-Wl,--strip-debug"})} },
        .{ "-Wl,-v", &.{Self.skip} },
        // x265
        .{ "-march=i586", &.{Self.skip} },
        .{ "-march=i686", &.{Self.skip} },
    });

    pub const windows_gnu_cc_filters = FilterTable.initComptime(.{
        .{ "-Wl,--disable-auto-image-base", &.{Self.skip} },
        .{ "-lgcc", &.{Self.skip} },
        .{ "-lgcc_eh", &.{Self.skip} },
        .{ "-lmsvcrt", &.{Self.skip} },
        .{ "-lwinapi_synchronization", &.{Self.skip} },
        .{ "-lwindows", &.{Self.skip} },
    });

    const skip: Self = .{ .replace = &.{} };
    const skip_two: Self = .{ .match_next_and_replace = .{ "", &.{} } };

    fn replace_with(comptime args: []const []const u8) Self {
        return .{ .replace = args };
    }

    fn skip_next(comptime next_arg: []const u8) Self {
        return .{ .match_next_and_replace = .{ next_arg, &.{} } };
    }

    fn replace_next(comptime next_arg: []const u8, comptime replacement: []const []const u8) Self {
        return .{ .match_next_and_replace = .{ next_arg, replacement } };
    }
};

pub const Deallcator = union(enum) {
    const Self = @This();
    arg_iter: std.process.ArgIterator,
    arg_iter_gen: ArgIteratorGeneral,
    string: struct { std.mem.Allocator, []u8 },

    pub fn deinit(self: Self) void {
        switch (self) {
            .arg_iter => |v| @constCast(&v).deinit(),
            .arg_iter_gen => |v| @constCast(&v).deinit(),
            .string => |v| v[0].free(v[1]),
        }
    }
};

pub const BufferedAllocator = struct {
    const Self = @This();
    const ArgIteratorInitError = std.process.ArgIterator.InitError;

    items: std.ArrayList(Deallcator),

    pub fn init(allocator_: std.mem.Allocator) Self {
        return .{ .items = std.ArrayList(Deallcator).init(allocator_) };
    }

    pub fn deinit(self: Self) void {
        @constCast(&self).clear();
        self.items.deinit();
    }

    pub inline fn allocator(self: *Self) std.mem.Allocator {
        return self.items.allocator;
    }

    pub fn clear(self: *Self) void {
        while (self.items.popOrNull()) |*de| {
            @constCast(de).deinit();
        }
        self.items.clearRetainingCapacity();
    }

    /// Add a string to the registry and it will be freed on `deinit()` automatically.
    pub fn addString(self: *Self, string: []u8) void {
        self.items.append(.{
            .string = .{ self.allocator(), string },
        }) catch unreachable;
    }

    pub fn allocString(self: *Self, n: usize) std.mem.Allocator.Error![]u8 {
        const value = try self.allocator().alloc(u8, n);
        self.addString(value);
        return value;
    }

    /// Remove a string from the registry and free it.
    pub fn freeString(self: *Self, string: []const u8) void {
        if (self._removeString(string)) |v| {
            v.deinit();
        }
    }

    /// Remove a string from the registry but do not free it.
    ///
    /// Do not forget to free the string manually.
    pub fn forgetString(self: *Self, string: []const u8) void {
        _ = self._removeString(string);
    }

    /// Remove a string from the registry and free it.
    fn _removeString(self: *Self, string: []const u8) ?Deallcator {
        var i = self.items.items.len;
        while (i > 0) : (i -= 1) {
            const de = &self.items.items[i - 1];
            if (de.* == .string and de.string[1].ptr == string.ptr) {
                return self.items.swapRemove(i - 1);
            }
        }
        return null;
    }

    /// Get the value of the environment variable `key`, abandon empty value.
    pub fn getEnvVar(self: *Self, key: []const u8) std.process.GetEnvVarOwnedError![]u8 {
        const val = try std.process.getEnvVarOwned(self.allocator(), key);
        const s = strTrimRight(val);
        if (s.len > 0) {
            self.addString(val);
            return val[0..s.len];
        }
        self.allocator().free(val);
        return std.process.GetEnvVarOwnedError.EnvironmentVariableNotFound;
    }

    pub fn argIterator(self: *Self) ArgIteratorInitError!std.process.ArgIterator {
        const value = try std.process.argsWithAllocator(self.allocator());
        self.items.append(.{
            .arg_iter = value,
        }) catch unreachable;
        return value;
    }

    pub fn argIteratorTakeOwnership(self: *Self, cmd_line: []const u8) !ArgIteratorGeneral {
        const value = try ArgIteratorGeneral.initTakeOwnership(
            self.allocator(),
            cmd_line,
        );
        self.items.append(.{
            .arg_iter_gen = value,
        }) catch unreachable;
        return value;
    }
};

pub const ZigLog = struct {
    const Self = @This();
    file: ?std.fs.File,

    pub fn init(path_: ?[]const u8) !Self {
        if (path_) |path| {
            if (std.fs.cwd().createFile(path, .{
                .read = true,
                .truncate = false,
            })) |file| {
                errdefer file.close();

                // Lock file.
                try file.lock(.exclusive);

                // Seek to the end.
                try file.seekFromEnd(0);

                return .{ .file = file };
            } else |_| {}
        }
        return .{ .file = null };
    }

    pub fn deinit(self: *Self) void {
        if (self.file) |file| {
            file.sync() catch {};
            file.unlock();
            file.close();
            self.file = null;
        }
    }

    pub fn write(self: *Self, bytes: []const u8) void {
        if (self.file) |file| {
            _ = file.writeAll(bytes) catch {};
        }
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
        if (self.file) |file| {
            file.writer().print(fmt, args) catch {};
        }
    }
};

pub const ZigWrapper = struct {
    const Self = @This();
    alloc: BufferedAllocator,
    sys_argv: std.ArrayList([]const u8),
    log: ZigLog,
    zig_exe: []const u8,
    command: ZigCommand,
    /// <arch>-<os>-<abi>
    zig_target: []const u8,
    /// <arch>-<vendor>-<os>-<abi>
    clang_target: []const u8,
    target_is_windows: bool,
    target_is_linux: bool,
    target_is_android: bool,
    target_is_apple: bool,
    target_is_wasm: bool,
    target_is_msvc: bool,
    target_is_musl: bool,
    args: std.ArrayList([]const u8),
    at_file_path: ?[]const u8,

    pub fn init(allocator_: std.mem.Allocator) !Self {
        var alloc = BufferedAllocator.init(allocator_);
        errdefer alloc.deinit();

        // log the `argv[0]`
        var log = blk: {
            const log_path = alloc.getEnvVar("ZIG_WRAPPER_LOG") catch null;
            defer if (log_path) |v| alloc.freeString(v);
            const v = try ZigLog.init(log_path);
            break :blk v;
        };
        errdefer log.deinit();

        var at_file_path: ?[]const u8 = null;
        var sys_argv = std.ArrayList([]const u8).init(alloc.allocator());
        errdefer sys_argv.deinit();
        var arg_iter = try alloc.argIterator();

        // Collect `argv[0..]`...
        while (arg_iter.next()) |arg| {
            // Parse the linker flag file.
            if (strStartsWith(arg, "@") and sys_argv.items.len > 0) {
                if (Self.parseFileFlags(&alloc, arg[1..])) |flags| {
                    at_file_path = arg;
                    try sys_argv.appendSlice(flags.items);
                    continue;
                } else |_| {}
            }
            try sys_argv.append(arg);
        }

        // Parse the command type from `argv[0]`.
        const stem = std.fs.path.stem(sys_argv.items[0]);
        const command = ZigCommand.fromStr(
            stem[if (std.mem.lastIndexOfScalar(u8, stem, '-')) |s| s + 1 else 0..],
        ) orelse return error.InvalidZigCommand;

        // zig[.exe]
        const zig_exe = alloc.getEnvVar("ZIG_EXECUTABLE") catch blk: {
            const str = try std.fmt.allocPrint(
                alloc.allocator(),
                "zig{s}",
                .{builtin.os.tag.exeFileExt(builtin.cpu.arch)},
            );
            alloc.addString(str);
            break :blk str;
        };

        const zig_target = alloc.getEnvVar("ZIG_WRAPPER_TARGET") catch "";
        const clang_target = alloc.getEnvVar("ZIG_WRAPPER_CLANG_TARGET") catch zig_target;
        const is_windows = std.mem.indexOf(u8, clang_target, "-windows") != null;
        const is_linux = std.mem.indexOf(u8, clang_target, "-linux") != null;
        const is_android = std.mem.indexOf(u8, clang_target, "-android") != null;
        const is_apple = std.mem.indexOf(u8, clang_target, "-apple") != null;
        const is_wasm = strStartsWith(clang_target, "wasm") or
            strEndsWith(clang_target, "-emscripten");
        const is_msvc = strEndsWith(clang_target, "-msvc");
        const is_musl = strEndsWith(clang_target, "-musl");

        return .{
            .alloc = alloc,
            .sys_argv = sys_argv,
            .log = log,
            .zig_exe = zig_exe,
            .command = command,
            .zig_target = zig_target,
            .clang_target = clang_target,
            .target_is_windows = is_windows,
            .target_is_linux = is_linux,
            .target_is_android = is_android,
            .target_is_apple = is_apple,
            .target_is_wasm = is_wasm,
            .target_is_msvc = is_msvc,
            .target_is_musl = is_musl,
            .args = std.ArrayList([]const u8).init(alloc.allocator()),
            .at_file_path = at_file_path,
        };
    }

    pub inline fn allocator(self: *Self) std.mem.Allocator {
        return self.alloc.allocator();
    }

    pub fn run(self: *Self) !u8 {
        // Zig executable
        try self.args.append(self.zig_exe);
        // Zig command
        try self.args.append(self.command.toName());
        // `cc`, `c++`: -target <target>
        try self.targetInit(self.zig_target);

        // Parse Zig flags in the environment variables and append them to `sys_argv`.
        self.parseEnvFlags() catch {};

        var skip: usize = 0;
        self.log.print("{s}", .{self.sys_argv.items[0]});
        for (self.sys_argv.items[1..], 1..) |arg, i| {
            self.log.write(" ");
            self.log.write(arg);
            if (skip > 0) {
                skip -= 1;
            } else {
                skip = try self.appendArgument(
                    arg,
                    self.sys_argv.items[i + 1 ..],
                );
            }
        }
        self.log.write("\n");
        self.log.write("    -->");
        for (self.args.items) |arg| {
            self.log.write(" ");
            self.log.write(arg);
        }
        self.log.write("\n");

        // Write to the `@<file_path>` file if present.
        if (self.at_file_path) |at_file_path| {
            // Write flags to buffer.
            var buffer = try std.ArrayList(u8).initCapacity(
                self.allocator(),
                64 * 1024,
            );
            defer buffer.deinit();
            for (self.args.items[2..]) |arg| {
                if (std.mem.indexOfAny(u8, arg, " \t") != null) {
                    if (arg[0] != '\"') try buffer.appendSlice("\"");
                    try buffer.appendSlice(arg);
                    if (arg[arg.len - 1] != '\"') try buffer.appendSlice("\"");
                } else {
                    try buffer.appendSlice(arg);
                }
                try buffer.appendSlice(" ");
            }

            // Write to file.
            var file = try std.fs.cwd().openFile(
                at_file_path[1..],
                .{ .mode = .read_write },
            );
            defer file.close();
            try file.seekTo(0);
            try file.writeAll(buffer.items);
            try file.setEndPos(try file.getPos());

            // Only keep the executable path and the command type.
            self.args.items.len = 2;
            // Set the @<file_path> flag.
            try self.args.append(at_file_path);
        }

        // Execute the command.
        var proc = std.process.Child.init(self.args.items, self.allocator());
        const term = try proc.spawnAndWait();
        if (term.Exited != 0) {
            self.log.print("***** error code: {d}\n", .{term.Exited});
        }
        return term.Exited;
    }

    pub fn deinit(self: *Self) void {
        self.args.clearAndFree();
        self.log.deinit();
        self.sys_argv.clearAndFree();
        self.alloc.deinit();
    }

    pub fn parseFileFlags(alloc: *BufferedAllocator, path: []const u8) !std.ArrayList([]const u8) {
        // Open the file for reading
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Get the file size
        const file_size = try file.getEndPos();

        // Allocate a buffer to hold the file content
        const flags_str = try alloc.allocString(file_size);
        errdefer alloc.freeString(flags_str);

        // Read the file content into the buffer
        _ = try file.readAll(flags_str);

        var args = std.ArrayList([]const u8).init(alloc.allocator());
        errdefer args.deinit();

        // Parse the flags
        var arg_iter = try alloc.argIteratorTakeOwnership(flags_str);
        alloc.forgetString(flags_str);
        while (arg_iter.next()) |arg| {
            try args.append(arg);
        }
        return args;
    }

    pub fn parseEnvFlags(self: *Self) !void {
        const buf = try self.allocator().alloc(u8, 32 + @max(
            self.zig_target.len,
            self.clang_target.len,
        ));
        defer self.allocator().free(buf);
        var args = std.ArrayList([]const u8).init(self.allocator());
        defer args.deinit();

        // Do not apply the same targets.
        const array = [_][]const u8{ "", self.zig_target, self.clang_target };
        const targets = //
            if (strEql(self.zig_target, self.clang_target)) array[0..2] else array[0..];

        for (targets) |target| {
            for ([_][]const u8{
                self.command.toFlagsName() orelse "",
                if (self.command == .cxx) ZigCommand.cc.toFlagsName().? else "",
            }) |flags_name| {
                if (flags_name.len == 0) continue;

                // Get the compiler flags from the environment variable.
                const key = (if (target.len > 0) std.fmt.bufPrint(
                    buf,
                    "{s}_{s}",
                    .{ flags_name, target },
                ) else std.fmt.bufPrint(
                    buf,
                    "ZIG_WRAPPER_{s}",
                    .{flags_name},
                )) catch unreachable;

                // Try <target> and <target> with underscore.
                for (0..2) |loop| {
                    if (loop == 1) {
                        if (std.mem.indexOf(u8, key, "-") == null) break;
                        _ = std.mem.replace(u8, key, "-", "_", key);
                    }

                    // Parse flags.
                    const flags_str = self.alloc.getEnvVar(key) catch continue;
                    var arg_iter = try self.alloc.argIteratorTakeOwnership(flags_str);
                    self.alloc.forgetString(flags_str);

                    args.clearRetainingCapacity();
                    while (arg_iter.next()) |arg| {
                        try args.append(arg);
                    }

                    // Do not append the same flags.
                    if (!stringsContains(self.sys_argv.items, args.items)) {
                        try self.sys_argv.appendSlice(args.items);
                    }
                }
            }
        }
    }

    pub fn targetInit(self: *Self, target: []const u8) !void {
        switch (self.command) {
            .cc, .cxx => {
                if (target.len > 0) {
                    try self.args.appendSlice(&[_][]const u8{ "-target", target });
                }

                // https://github.com/ziglang/zig/wiki/FAQ#why-do-i-get-illegal-instruction-when-using-with-zig-cc-to-build-c-code
                try self.args.append("-fno-sanitize=undefined");

                // For libmount
                // try self.args.appendSlice(&[_][]const u8{
                //     "-DHAVE_CLOSE_RANGE=1",
                //     "-DHAVE_STATX=1",
                //     "-DHAVE_OPEN_TREE=1",
                //     "-DHAVE_MOVE_MOUNT=1",
                //     "-DHAVE_MOUNT_SETATTR=1",
                //     "-DHAVE_FSCONFIG=1",
                //     "-DHAVE_FSOPEN=1",
                //     "-DHAVE_FSMOUNT=1",
                //     "-DHAVE_FSPICK=1",
                // });
            },
            else => {},
        }
    }

    pub fn appendArgument(self: *Self, arg_: []const u8, remaining: []const []const u8) !usize {
        var arg = arg_;
        switch (self.command) {
            .cc, .cxx => {
                // Strip quotes
                var opt = std.mem.trim(u8, arg, "\"");
                var filters = &ZigArgFilter.cc_filters;

                for (0..3) |loop_for_opt| {
                    for (0..2) |split_kv| {
                        // Get this option
                        const this_opt = if (split_kv == 0) opt else blk: {
                            var opt_kv = std.mem.splitAny(
                                u8,
                                opt,
                                if (self.target_is_msvc) "=:" else "=",
                            );
                            const s = opt_kv.next().?;
                            // Do not continue if the delimiter is not found.
                            if (s.len == opt.len) continue;
                            break :blk s;
                        };

                        if (filters.get(this_opt)) |arg_ops| {
                            for (arg_ops) |arg_op| switch (arg_op) {
                                .replace => |replacement| {
                                    try self.args.appendSlice(replacement);
                                    return 0;
                                },
                                .match_next_and_replace => |item| {
                                    // Get the next option.
                                    const next_opt = if (split_kv == 0)
                                        (if (remaining.len > 0) remaining[0] else "")
                                    else
                                        opt[this_opt.len + 1 ..];
                                    // Match successfully if the pattern is empty.
                                    if (item[0].len == 0 or strEql(item[0], next_opt)) {
                                        try self.args.appendSlice(item[1]);
                                        return if (split_kv == 0) 1 else 0;
                                    }
                                },
                            };
                        }
                    }

                    // Continue for `<arch>-windows-gnu`, break for other targets.
                    if (self.target_is_windows and !self.target_is_msvc) {
                        filters = &ZigArgFilter.windows_gnu_cc_filters;
                        if (loop_for_opt == 1) {
                            const arg_len = arg.len;
                            if (strStartsWith(opt, "-l")) {
                                var lib = opt[2..];
                                // Trim library version like `windows.0.48.5`.
                                if (strStartsWith(lib, "windows")) {
                                    if (std.mem.indexOf(u8, lib, ".")) |i| {
                                        lib = lib[0..i];
                                    }
                                }
                                // Trim prefix `winapi_`.
                                if (strStartsWith(lib, "winapi_")) {
                                    lib = lib[7..];
                                }

                                // Strip `.a` and `.so`.
                                if (strStartsWith(lib, ":")) {
                                    lib = lib[1..];
                                    if (strStartsWith(lib, "lib")) {
                                        lib = lib[3..];
                                    }
                                    if (strEndsWith(lib, ".a")) {
                                        lib = lib[0..(lib.len - 2)];
                                    } else if (strEndsWith(lib, ".so")) {
                                        lib = lib[0..(lib.len - 3)];
                                    }
                                }

                                opt = std.fmt.bufPrint(
                                    @constCast(arg),
                                    "-l{s}",
                                    .{lib},
                                ) catch continue;
                            }
                            if (arg_len == opt.len) continue;
                            arg.len = opt.len;
                        }
                    } else {
                        break;
                    }
                }
            },
            else => {},
        }

        try self.args.append(arg);
        return 0;
    }
};

/// Check if `a` and `b` are equal.
pub inline fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Remove trailing whitespace from `s`.
pub inline fn strTrimRight(s: []const u8) []const u8 {
    return std.mem.trimRight(u8, s, " \t\r\n");
}

/// Check if `haystack` starts with `needle`.
pub fn strStartsWith(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) {
        return false;
    }
    return strEql(haystack[0..needle.len], needle);
}

/// Check if `haystack` ends with `needle`.
pub fn strEndsWith(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) {
        return false;
    }
    return strEql(haystack[haystack.len - needle.len ..], needle);
}

/// Check if `slice` contains `sub_slice`.
pub fn stringsContains(slice: []const []const u8, sub_slice: []const []const u8) bool {
    if (sub_slice.len == 0) return true;
    if (sub_slice.len > slice.len) return false;

    outer: for (0..slice.len - sub_slice.len + 1) |i| {
        for (sub_slice, 0..) |s, j| {
            if (!strEql(slice[i + j], s)) {
                continue :outer;
            }
        }
        return true;
    }
    return false;
}

pub fn main() noreturn {
    var status: u8 = 0;
    defer {
        std.process.exit(status);
    }
    errdefer |err| {
        _ = std.io.getStdErr().writer().print("error: {}\n", .{err}) catch {};
        std.process.exit(1);
    }

    var zig = try ZigWrapper.init(std.heap.c_allocator);
    defer zig.deinit();
    status = try zig.run();
}
