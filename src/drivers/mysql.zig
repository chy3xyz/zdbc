//! MySQL database driver
//!
//! This driver wraps the myzql library to provide MySQL/MariaDB support
//! through the ZDBC VTable interface.
//!
//! Dependencies: https://github.com/speed2exe/myzql

const std = @import("std");
const myzql = @import("myzql");
const Connection = @import("../connection.zig").Connection;
const ConnectionVTable = @import("../connection.zig").ConnectionVTable;
const Result = @import("../result.zig").Result;
const ResultVTable = @import("../result.zig").ResultVTable;
const Statement = @import("../statement.zig").Statement;
const value = @import("../value.zig");
const Value = value.Value;
const SqlParam = value.SqlParam;
const Error = @import("../error.zig").Error;
const Uri = @import("../uri.zig").Uri;

var global_io_threaded: std.Io.Threaded = undefined;
var global_io_initialized: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn getGlobalIo() std.Io {
    if (global_io_initialized.load(.acquire)) {
        return global_io_threaded.io();
    }

    const gpa = std.heap.page_allocator;
    const single_threaded = @import("builtin").single_threaded;
    global_io_threaded = std.Io.Threaded.init(gpa, .{
        .async_limit = if (single_threaded) .nothing else null,
    });
    global_io_initialized.store(true, .release);
    return global_io_threaded.io();
}

pub const MysqlContext = struct {
    allocator: std.mem.Allocator,
    conn: myzql.conn.Conn,
    io: std.Io,
    last_error: ?[]const u8 = null,
    affected_rows: usize = 0,
    last_insert_id: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, uri: Uri) !*MysqlContext {
        const host = uri.host orelse "127.0.0.1";
        const port = uri.port orelse 3306;

        const io = getGlobalIo();

        const ip_address = std.Io.net.IpAddress.parse(host, port) catch {
            return error.ConnectionFailed;
        };

        const username = if (uri.username) |u| try allocator.dupeZ(u8, u) else try allocator.dupeZ(u8, "root");
        defer allocator.free(username);
        const password = if (uri.password) |p| p else "";
        const database = try allocator.dupeZ(u8, uri.database);
        defer allocator.free(database);

        const config = myzql.config.Config{
            .username = username,
            .address = .{ .ip = ip_address },
            .password = password,
            .database = database,
        };

        const conn = myzql.conn.Conn.init(allocator, io, &config) catch {
            return error.ConnectionFailed;
        };

        const ctx = try allocator.create(MysqlContext);
        ctx.* = MysqlContext{
            .allocator = allocator,
            .conn = conn,
            .io = io,
        };
        return ctx;
    }

    pub fn deinit(self: *MysqlContext) void {
        self.conn.deinit(self.allocator, self.io);
        self.allocator.destroy(self);
    }
};

pub const MysqlResultContext = struct {
    allocator: std.mem.Allocator,
    table: myzql.result.TableTexts,
    column_names: []const []const u8,
    current_row: usize = 0,

    pub fn init(allocator: std.mem.Allocator, table: myzql.result.TableTexts, column_names: []const []const u8) !*MysqlResultContext {
        const ctx = try allocator.create(MysqlResultContext);
        ctx.* = MysqlResultContext{
            .allocator = allocator,
            .table = table,
            .column_names = column_names,
        };
        return ctx;
    }

    pub fn deinit(self: *MysqlResultContext) void {
        self.table.deinit(self.allocator);
        self.allocator.free(self.column_names);
        self.allocator.destroy(self);
    }
};

const mysqlResultVTable = ResultVTable{
    .next = mysqlResultNext,
    .columnCount = mysqlResultColumnCount,
    .columnName = mysqlResultColumnName,
    .getValue = mysqlResultGetValue,
    .getValueByName = mysqlResultGetValueByName,
    .affectedRows = mysqlResultAffectedRows,
    .reset = null,
    .deinit = mysqlResultDeinit,
};

fn mysqlResultNext(ctx: *anyopaque) Error!bool {
    const result_ctx: *MysqlResultContext = @ptrCast(@alignCast(ctx));
    if (result_ctx.current_row < result_ctx.table.table.len) {
        result_ctx.current_row += 1;
        return true;
    }
    return false;
}

fn mysqlResultColumnCount(ctx: *anyopaque) usize {
    const result_ctx: *MysqlResultContext = @ptrCast(@alignCast(ctx));
    return result_ctx.column_names.len;
}

fn mysqlResultColumnName(ctx: *anyopaque, index: usize) ?[]const u8 {
    const result_ctx: *MysqlResultContext = @ptrCast(@alignCast(ctx));
    if (index < result_ctx.column_names.len) {
        return result_ctx.column_names[index];
    }
    return null;
}

fn mysqlResultGetValue(ctx: *anyopaque, index: usize) Error!Value {
    const result_ctx: *MysqlResultContext = @ptrCast(@alignCast(ctx));
    if (result_ctx.current_row == 0 or result_ctx.current_row > result_ctx.table.table.len) {
        return Error.NoMoreRows;
    }
    const row_index = result_ctx.current_row - 1;
    if (row_index < result_ctx.table.table.len and index < result_ctx.table.table[row_index].len) {
        const val = result_ctx.table.table[row_index][index];
        if (val) |v| {
            return Value.initText(v);
        }
        return Value.initNull();
    }
    return Error.NoMoreRows;
}

fn mysqlResultGetValueByName(_: *anyopaque, _: []const u8) Error!Value {
    return Error.NotImplemented;
}

fn mysqlResultAffectedRows(ctx: *anyopaque) usize {
    const result_ctx: *MysqlResultContext = @ptrCast(@alignCast(ctx));
    _ = result_ctx;
    return 0;
}

fn mysqlResultDeinit(ctx: *anyopaque) void {
    const result_ctx: *MysqlResultContext = @ptrCast(@alignCast(ctx));
    result_ctx.deinit();
}

const mysqlConnectionVTable = ConnectionVTable{
    .exec = mysqlExec,
    .query = mysqlQuery,
    .prepare = mysqlPrepare,
    .begin = mysqlBegin,
    .commit = mysqlCommit,
    .rollback = mysqlRollback,
    .close = mysqlClose,
    .lastInsertId = mysqlLastInsertId,
    .affectedRows = mysqlAffectedRows,
    .ping = mysqlPing,
    .lastError = mysqlLastError,
};

fn mysqlExec(ctx: *anyopaque, allocator: std.mem.Allocator, sql: []const u8, params: []const SqlParam) Error!usize {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));

    var sql_to_use: []const u8 = sql;
    var need_to_free = false;

    if (params.len > 0) {
        sql_to_use = value.interpolateSqlParam(allocator, sql, params) catch return Error.InvalidParameter;
        need_to_free = true;
    }

    errdefer if (need_to_free) allocator.free(sql_to_use);

    const result = mysql_ctx.conn.query(mysql_ctx.io, sql_to_use) catch {
        return Error.ExecutionFailed;
    };

    if (need_to_free) {
        allocator.free(sql_to_use);
    }

    switch (result) {
        .ok => |ok| {
            mysql_ctx.affected_rows = @as(usize, @intCast(ok.affected_rows));
            mysql_ctx.last_insert_id = @intCast(ok.last_insert_id);
            return @as(usize, @intCast(ok.affected_rows));
        },
        .err => |err| {
            mysql_ctx.last_error = err.error_message;
            return Error.ExecutionFailed;
        },
    }
}

fn mysqlQuery(ctx: *anyopaque, allocator: std.mem.Allocator, sql: []const u8, params: []const SqlParam) Error!Result {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));

    var sql_to_use: []const u8 = sql;
    var need_to_free = false;

    if (params.len > 0) {
        sql_to_use = value.interpolateSqlParam(allocator, sql, params) catch return Error.InvalidParameter;
        need_to_free = true;
    }

    errdefer if (need_to_free) allocator.free(sql_to_use);

    const result = mysql_ctx.conn.queryRows(allocator, mysql_ctx.io, sql_to_use) catch {
        return Error.ExecutionFailed;
    };

    if (need_to_free) {
        allocator.free(sql_to_use);
    }

    switch (result) {
        .rows => |row_result| {
            var result_set = row_result;
            const table = result_set.tableTexts(allocator, mysql_ctx.io) catch {
                return Error.ExecutionFailed;
            };
            const col_defs = result_set.col_defs;
            const column_names = try allocator.alloc([]const u8, col_defs.len);
            for (col_defs, 0..) |col, i| {
                column_names[i] = col.name;
            }
            const result_ctx = MysqlResultContext.init(allocator, table, column_names) catch return Error.OutOfMemory;
            return Result.init(@ptrCast(result_ctx), &mysqlResultVTable);
        },
        .err => |err| {
            mysql_ctx.last_error = err.error_message;
            return Error.ExecutionFailed;
        },
    }
}

fn mysqlPrepare(_: *anyopaque, _: std.mem.Allocator, _: []const u8) Error!Statement {
    return Error.NotImplemented;
}

fn mysqlBegin(ctx: *anyopaque) Error!void {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));
    _ = mysql_ctx.conn.query(mysql_ctx.io, "BEGIN") catch return Error.TransactionError;
}

fn mysqlCommit(ctx: *anyopaque) Error!void {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));
    _ = mysql_ctx.conn.query(mysql_ctx.io, "COMMIT") catch return Error.TransactionError;
}

fn mysqlRollback(ctx: *anyopaque) Error!void {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));
    _ = mysql_ctx.conn.query(mysql_ctx.io, "ROLLBACK") catch return Error.TransactionError;
}

fn mysqlClose(ctx: *anyopaque) void {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));
    mysql_ctx.deinit();
}

fn mysqlLastInsertId(ctx: *anyopaque) ?i64 {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));
    return mysql_ctx.last_insert_id;
}

fn mysqlAffectedRows(ctx: *anyopaque) usize {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));
    return mysql_ctx.affected_rows;
}

fn mysqlPing(ctx: *anyopaque) Error!void {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));
    mysql_ctx.conn.ping(mysql_ctx.io) catch return Error.ConnectionFailed;
}

fn mysqlLastError(ctx: *anyopaque) ?[]const u8 {
    const mysql_ctx: *MysqlContext = @ptrCast(@alignCast(ctx));
    return mysql_ctx.last_error;
}

pub fn open(allocator: std.mem.Allocator, uri: Uri) Error!Connection {
    const ctx = MysqlContext.init(allocator, uri) catch return Error.ConnectionFailed;
    return Connection{
        .ctx = @ptrCast(ctx),
        .vtable = &mysqlConnectionVTable,
        .allocator = allocator,
        .uri = uri,
    };
}

test "mysql driver interface" {
    const uri = Uri.parse("mysql://user:pass@localhost:3306/testdb") catch unreachable;
    _ = uri;
}
