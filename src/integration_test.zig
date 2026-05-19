const std = @import("std");
const zdbc = @import("zdbc.zig");

test "mysql: connect and query" {
    var conn = try zdbc.open(std.testing.allocator, "mysql://zdbc_test:zdbc_test_pass@127.0.0.1:3306/zdbc_test");
    defer conn.close();

    _ = try conn.exec("DROP TABLE IF EXISTS users", &.{});
    _ = try conn.exec("CREATE TABLE users (id INT AUTO_INCREMENT PRIMARY KEY, name TEXT)", &.{});
    _ = try conn.exec("INSERT INTO users (name) VALUES ('Alice')", &.{});
    _ = try conn.exec("INSERT INTO users (name) VALUES ('Bob')", &.{});

    var result = try conn.query("SELECT id, name FROM users ORDER BY id", &.{});
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) |row| {
        const id_val = try row.get(0);
        const name_val = try row.get(1);
        const id = id_val.asText().?;
        const name = name_val.asText().?;
        const expected_id = if (count == 0) "1" else "2";
        try std.testing.expectEqualStrings(expected_id, id);
        if (count == 0) {
            try std.testing.expectEqualStrings("Alice", name);
        } else {
            try std.testing.expectEqualStrings("Bob", name);
        }
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "mysql: exec with affected rows" {
    var conn = try zdbc.open(std.testing.allocator, "mysql://zdbc_test:zdbc_test_pass@127.0.0.1:3306/zdbc_test");
    defer conn.close();

    _ = try conn.exec("DROP TABLE IF EXISTS test_exec", &.{});
    _ = try conn.exec("CREATE TABLE test_exec (id INT)", &.{});

    const affected = try conn.exec("INSERT INTO test_exec VALUES (1), (2), (3)", &.{});
    try std.testing.expectEqual(@as(usize, 3), affected);

    const affected2 = try conn.exec("DELETE FROM test_exec WHERE id > 1", &.{});
    try std.testing.expectEqual(@as(usize, 2), affected2);
}

test "mysql: ping" {
    var conn = try zdbc.open(std.testing.allocator, "mysql://zdbc_test:zdbc_test_pass@127.0.0.1:3306/zdbc_test");
    defer conn.close();

    try conn.ping();
}

test "postgresql: connect and query" {
    var conn = try zdbc.open(std.testing.allocator, "postgresql://n0x@127.0.0.1:5432/zfinal_pg_test");
    defer conn.close();

    _ = try conn.exec("DROP TABLE IF EXISTS users CASCADE", &.{});
    _ = try conn.exec("CREATE TABLE users (id INT PRIMARY KEY, name TEXT)", &.{});
    _ = try conn.exec("INSERT INTO users (id, name) VALUES (1, 'Charlie')", &.{});
    _ = try conn.exec("INSERT INTO users (id, name) VALUES (2, 'Diana')", &.{});

    var result = try conn.query("SELECT CAST(id AS TEXT), name FROM users ORDER BY id", &.{});
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) |row| {
        const id_val = try row.get(0);
        const name_val = try row.get(1);
        const id = id_val.asText().?;
        const name = name_val.asText().?;
        const expected_id = if (count == 0) "1" else "2";
        try std.testing.expectEqualStrings(expected_id, id);
        if (count == 0) {
            try std.testing.expectEqualStrings("Charlie", name);
        } else {
            try std.testing.expectEqualStrings("Diana", name);
        }
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "postgresql: exec with affected rows" {
    var conn = try zdbc.open(std.testing.allocator, "postgresql://n0x@127.0.0.1:5432/zfinal_pg_test");
    defer conn.close();

    _ = try conn.exec("DROP TABLE IF EXISTS test_exec CASCADE", &.{});
    _ = try conn.exec("CREATE TABLE test_exec (id INT)", &.{});

    const affected = try conn.exec("INSERT INTO test_exec VALUES (1), (2), (3)", &.{});
    try std.testing.expectEqual(@as(usize, 3), affected);

    const affected2 = try conn.exec("DELETE FROM test_exec WHERE id > 1", &.{});
    try std.testing.expectEqual(@as(usize, 2), affected2);
}

test "postgresql: ping" {
    var conn = try zdbc.open(std.testing.allocator, "postgresql://n0x@127.0.0.1:5432/zfinal_pg_test");
    defer conn.close();

    try conn.ping();
}

test "mysql: execParams with parameter binding" {
    var conn = try zdbc.open(std.testing.allocator, "mysql://zdbc_test:zdbc_test_pass@127.0.0.1:3306/zdbc_test");
    defer conn.close();

    _ = try conn.exec("DROP TABLE IF EXISTS test_params", &.{});
    _ = try conn.exec("CREATE TABLE test_params (id INT, name TEXT, value DOUBLE)", &.{});

    _ = try conn.execParams("INSERT INTO test_params (id, name, value) VALUES (?, ?, ?)", &.{
        zdbc.SqlParam.bindInt(1),
        zdbc.SqlParam.bindText("Alice"),
        zdbc.SqlParam.bindReal(3.14),
    });

    _ = try conn.execParams("INSERT INTO test_params (id, name, value) VALUES (?, ?, ?)", &.{
        zdbc.SqlParam.bindInt(2),
        zdbc.SqlParam.bindText("Bob"),
        zdbc.SqlParam.bindReal(2.71828),
    });

    var result = try conn.queryParams("SELECT id, name, value FROM test_params ORDER BY id", &.{});
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) |row| {
        const id_val = try row.get(0);
        const name_val = try row.get(1);
        const id = id_val.asText().?;
        const name = name_val.asText().?;
        if (count == 0) {
            try std.testing.expectEqualStrings("1", id);
            try std.testing.expectEqualStrings("Alice", name);
        } else {
            try std.testing.expectEqualStrings("2", id);
            try std.testing.expectEqualStrings("Bob", name);
        }
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "mysql: queryParams with WHERE clause" {
    var conn = try zdbc.open(std.testing.allocator, "mysql://zdbc_test:zdbc_test_pass@127.0.0.1:3306/zdbc_test");
    defer conn.close();

    _ = try conn.exec("DROP TABLE IF EXISTS test_params_where", &.{});
    _ = try conn.exec("CREATE TABLE test_params_where (id INT, name TEXT)", &.{});

    _ = try conn.execParams("INSERT INTO test_params_where (id, name) VALUES (?, ?)", &.{
        zdbc.SqlParam.bindInt(1),
        zdbc.SqlParam.bindText("Charlie"),
    });
    _ = try conn.execParams("INSERT INTO test_params_where (id, name) VALUES (?, ?)", &.{
        zdbc.SqlParam.bindInt(2),
        zdbc.SqlParam.bindText("Diana"),
    });

    var result = try conn.queryParams("SELECT name FROM test_params_where WHERE id = ?", &.{
        zdbc.SqlParam.bindInt(2),
    });
    defer result.deinit();

    const row = try result.next();
    try std.testing.expect(row != null);
    const name_val = try row.?.get(0);
    try std.testing.expectEqualStrings("Diana", name_val.asText().?);
}

test "postgresql: execParams with parameter binding" {
    var conn = try zdbc.open(std.testing.allocator, "postgresql://n0x@127.0.0.1:5432/zfinal_pg_test");
    defer conn.close();

    _ = try conn.exec("DROP TABLE IF EXISTS test_params CASCADE", &.{});
    _ = try conn.exec("CREATE TABLE test_params (id INT, name TEXT, value DOUBLE PRECISION)", &.{});

    _ = try conn.execParams("INSERT INTO test_params (id, name, value) VALUES ($1, $2, $3)", &.{
        zdbc.SqlParam.bindInt(1),
        zdbc.SqlParam.bindText("Alice"),
        zdbc.SqlParam.bindReal(3.14),
    });

    _ = try conn.execParams("INSERT INTO test_params (id, name, value) VALUES ($1, $2, $3)", &.{
        zdbc.SqlParam.bindInt(2),
        zdbc.SqlParam.bindText("Bob"),
        zdbc.SqlParam.bindReal(2.71828),
    });

    var result = try conn.queryParams("SELECT id::text, name, value::text FROM test_params ORDER BY id", &.{});
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) |row| {
        const id_val = try row.get(0);
        const name_val = try row.get(1);
        const id = id_val.asText().?;
        const name = name_val.asText().?;
        if (count == 0) {
            try std.testing.expectEqualStrings("1", id);
            try std.testing.expectEqualStrings("Alice", name);
        } else {
            try std.testing.expectEqualStrings("2", id);
            try std.testing.expectEqualStrings("Bob", name);
        }
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "postgresql: queryParams with WHERE clause" {
    var conn = try zdbc.open(std.testing.allocator, "postgresql://n0x@127.0.0.1:5432/zfinal_pg_test");
    defer conn.close();

    _ = try conn.exec("DROP TABLE IF EXISTS test_params_where CASCADE", &.{});
    _ = try conn.exec("CREATE TABLE test_params_where (id INT, name TEXT)", &.{});

    _ = try conn.execParams("INSERT INTO test_params_where (id, name) VALUES ($1, $2)", &.{
        zdbc.SqlParam.bindInt(1),
        zdbc.SqlParam.bindText("Charlie"),
    });
    _ = try conn.execParams("INSERT INTO test_params_where (id, name) VALUES ($1, $2)", &.{
        zdbc.SqlParam.bindInt(2),
        zdbc.SqlParam.bindText("Diana"),
    });

    var result = try conn.queryParams("SELECT name FROM test_params_where WHERE id = $1", &.{
        zdbc.SqlParam.bindInt(2),
    });
    defer result.deinit();

    const row = try result.next();
    try std.testing.expect(row != null);
    const name_val = try row.?.get(0);
    try std.testing.expectEqualStrings("Diana", name_val.asText().?);
}
