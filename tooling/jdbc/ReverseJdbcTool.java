import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.Driver;
import java.sql.DriverManager;
import java.sql.DriverPropertyInfo;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;

public final class ReverseJdbcTool {
  private static void log(String message) {
    System.out.println(message);
    System.out.flush();
  }

  public static void main(String[] args) throws Exception {
    if (args.length < 2) {
      String outputPathValue = args.length >= 2 ? args[1] : "jdbc-output.json";
      writeJson(Paths.get(outputPathValue),
          error("invalid_args", "缺少输入或输出参数。").toJson());
      System.exit(2);
      return;
    }

    Path inputPath = Paths.get(args[0]);
    Path outputPath = Paths.get(args[1]);

    try {
      Request request = Request.fromJson(readUtf8(inputPath));
      Response response;
      if ("testConnection".equals(request.mode)) {
        response = testConnection(request);
      } else if ("reverse".equals(request.mode)) {
        response = reverse(request);
      } else {
        response = error("unsupported_mode", "不支持的执行模式：" + request.mode);
      }
      writeJson(outputPath, response.toJson());
    } catch (Throwable error) {
      writeJson(outputPath, error("unexpected_error", stackTraceToString(error)).toJson());
      System.exit(1);
    }
  }

  private static Response testConnection(Request request) {
    try {
      log("开始加载 JDBC 驱动...");
      loadDriver(request);
      log("JDBC 驱动加载完成。");
      log("开始建立数据库连接...");
      try (Connection connection = openConnection(request)) {
        log("数据库连接成功。");
        return Response.success(new LinkedHashMap<String, Object>() {{
          put("message", "连接成功");
        }});
      }
    } catch (Throwable error) {
      return error("connection_failed", stackTraceToString(error));
    }
  }

  private static Response reverse(Request request) {
    try {
      log("开始加载 JDBC 驱动...");
      loadDriver(request);
      log("JDBC 驱动加载完成。");
      log("开始建立数据库连接...");
      try (Connection connection = openConnection(request)) {
        log("数据库连接成功。");
        SqlContext sqlContext = SqlContext.from(connection, request);
        List<String> logs = new ArrayList<String>();
        logs.add("开始逆向数据源：" + request.dataSourceName);
        logs.add("数据库类型：" + request.databaseType);
        logs.add("解析后的用户：" + sqlContext.user);
        logs.add("解析后的 Schema：" + sqlContext.schema);
        logs.add("解析后的 Catalog：" + sqlContext.catalog);
        String resolvedTableSql = sqlContext.resolve(request.tableSql);
        String resolvedColumnSql = sqlContext.resolve(request.columnSql);
        String resolvedColumnCommentSql = sqlContext.resolve(request.columnCommentSql);
        String resolvedPrimaryKeySql = sqlContext.resolve(request.primaryKeySql);
        log("开始查询表元数据...");
        long startedAt = System.nanoTime();
        List<Map<String, Object>> tables = queryRows(
            connection,
            resolvedTableSql,
            request.tableParams());
        log("表元数据查询完成，返回 " + tables.size() + " 行，耗时 " + elapsedMillis(startedAt) + " ms。");
        log("开始查询字段元数据...");
        startedAt = System.nanoTime();
        List<Map<String, Object>> columns = queryRows(
            connection,
            resolvedColumnSql,
            request.columnParams());
        log("字段元数据查询完成，返回 " + columns.size() + " 行，耗时 " + elapsedMillis(startedAt) + " ms。");
        List<Map<String, Object>> columnComments = Collections.emptyList();
        if (resolvedColumnCommentSql != null && !resolvedColumnCommentSql.trim().isEmpty()) {
          log("开始查询字段注释...");
          startedAt = System.nanoTime();
          columnComments = queryRows(
              connection,
              resolvedColumnCommentSql,
              request.columnCommentParams());
          log("字段注释查询完成，返回 " + columnComments.size() + " 行，耗时 " + elapsedMillis(startedAt) + " ms。");
        }
        log("开始查询主键元数据...");
        startedAt = System.nanoTime();
        List<Map<String, Object>> primaryKeys = queryRows(
            connection,
            resolvedPrimaryKeySql,
            request.primaryKeyParams());
        log("主键元数据查询完成，返回 " + primaryKeys.size() + " 行，耗时 " + elapsedMillis(startedAt) + " ms。");
        logs.add("表查询返回行数：" + tables.size());
        logs.add("字段查询返回行数：" + columns.size());
        logs.add("主键查询返回行数：" + primaryKeys.size());
        validateColumns(tables, Arrays.asList("table_name", "table_code", "table_comment"));
        validateColumns(columns, Arrays.asList(
            "table_name",
            "column_name",
            "column_code",
            "data_type",
            "length",
            "precision",
            "nullable",
            "default_value",
            "column_comment",
            "ordinal_position"));
        if (!columnComments.isEmpty()) {
          validateColumns(columnComments, Arrays.asList(
              "table_name",
              "column_name",
              "column_comment"));
        }
        validateColumns(primaryKeys, Arrays.asList("table_name", "column_name"));

        Map<String, String> columnCommentMap = new HashMap<String, String>();
        for (Map<String, Object> row : columnComments) {
          String tableName = stringValue(row.get("table_name"));
          String columnName = stringValue(row.get("column_name"));
          if (tableName.isEmpty() || columnName.isEmpty()) {
            continue;
          }
          columnCommentMap.put(commentKey(tableName, columnName), stringValue(row.get("column_comment")));
        }

        Map<String, List<String>> primaryKeyMap = new HashMap<String, List<String>>();
        for (Map<String, Object> row : primaryKeys) {
          String tableName = stringValue(row.get("table_name"));
          String columnName = stringValue(row.get("column_name"));
          if (tableName.isEmpty() || columnName.isEmpty()) {
            continue;
          }
          List<String> list = primaryKeyMap.get(tableName);
          if (list == null) {
            list = new ArrayList<String>();
            primaryKeyMap.put(tableName, list);
          }
          list.add(columnName);
        }

        Map<String, Map<String, Object>> tableMap = new LinkedHashMap<String, Map<String, Object>>();
        for (Map<String, Object> row : tables) {
          String tableName = stringValue(row.get("table_name"));
          if (tableName.isEmpty()) {
            continue;
          }
          Map<String, Object> table = new LinkedHashMap<String, Object>();
          table.put("name", defaultValue(stringValue(row.get("table_comment")), tableName));
          table.put("code", defaultValue(stringValue(row.get("table_code")), tableName));
          table.put("comment", stringValue(row.get("table_comment")));
          table.put("schemaName", request.schemaName);
          table.put("rawIdentifier", request.schemaName.isEmpty() ? tableName : request.schemaName + "." + tableName);
          table.put("columns", new ArrayList<Map<String, Object>>());
          tableMap.put(tableName, table);
        }

        for (Map<String, Object> row : columns) {
          String tableName = stringValue(row.get("table_name"));
          Map<String, Object> table = tableMap.get(tableName);
          if (table == null) {
            continue;
          }
          @SuppressWarnings("unchecked")
          List<Map<String, Object>> tableColumns = (List<Map<String, Object>>) table.get("columns");
          String columnName = defaultValue(stringValue(row.get("column_name")), "");
          List<String> pkColumns = primaryKeyMap.containsKey(tableName)
              ? primaryKeyMap.get(tableName)
              : Collections.<String>emptyList();
          Map<String, Object> column = new LinkedHashMap<String, Object>();
          String mergedComment = stringValue(row.get("column_comment"));
          if (mergedComment.isEmpty() && !columnCommentMap.isEmpty()) {
            mergedComment = defaultValue(columnCommentMap.get(commentKey(tableName, columnName)), "");
          }
          column.put("name", defaultValue(mergedComment, columnName));
          column.put("code", defaultValue(stringValue(row.get("column_code")), columnName));
          column.put("dataType", stringValue(row.get("data_type")));
          column.put("length", stringValue(row.get("length")));
          column.put("precision", stringValue(row.get("precision")));
          column.put("nullable", parseNullable(row.get("nullable")));
          column.put("defaultValue", stringValue(row.get("default_value")));
          column.put("isPrimaryKey", pkColumns.contains(columnName));
          column.put("comment", mergedComment);
          column.put("ordinalPosition", parseInt(row.get("ordinal_position"), tableColumns.size() + 1));
          tableColumns.add(column);
        }

        for (Map<String, Object> table : tableMap.values()) {
          @SuppressWarnings("unchecked")
          List<Map<String, Object>> tableColumns = (List<Map<String, Object>>) table.get("columns");
          Collections.sort(tableColumns, (left, right) -> parseInt(left.get("ordinalPosition"), 0) - parseInt(right.get("ordinalPosition"), 0));
        }
        log("元数据组装完成，表数量：" + tableMap.size() + "。");

        LinkedHashMap<String, Object> payload = new LinkedHashMap<String, Object>();
        payload.put("databaseType", request.databaseType);
        payload.put("dataSourceName", request.dataSourceName);
        payload.put("schemaName", request.schemaName);
        payload.put("catalogName", request.catalogName);
        payload.put("tables", new ArrayList<Map<String, Object>>(tableMap.values()));
        payload.put("logs", logs);
        return Response.success(payload);
      }
    } catch (Throwable error) {
      return error("reverse_failed", stackTraceToString(error));
    }
  }

  private static void loadDriver(Request request) throws Exception {
    Driver driver = (Driver) Class.forName(request.driverClass).getDeclaredConstructor().newInstance();
    DriverManager.registerDriver(new DriverShim(driver));
  }

  private static Connection openConnection(Request request) throws SQLException {
    Properties properties = new Properties();
    properties.setProperty("user", request.username);
    properties.setProperty("password", request.password);
    return DriverManager.getConnection(request.jdbcUrl, properties);
  }

  private static List<Map<String, Object>> queryRows(Connection connection, String sql, List<Object> parameters)
      throws SQLException {
    if (sql == null || sql.trim().isEmpty()) {
      return Collections.emptyList();
    }
    String trimmed = sql.trim();
    log("执行 JDBC SQL：\n" + trimmed);
    if (!parameters.isEmpty()) {
      try (PreparedStatement statement = connection.prepareStatement(trimmed)) {
        statement.setFetchSize(resolveFetchSize(connection));
        for (int index = 0; index < parameters.size(); index++) {
          statement.setObject(index + 1, parameters.get(index));
        }
        try (ResultSet resultSet = statement.executeQuery()) {
          return collectRows(resultSet);
        }
      }
    }
    try (Statement statement = connection.createStatement()) {
      statement.setFetchSize(resolveFetchSize(connection));
      try (ResultSet resultSet = statement.executeQuery(trimmed)) {
        return collectRows(resultSet);
      }
    }
  }

  private static int resolveFetchSize(Connection connection) {
    try {
      String productName = connection.getMetaData().getDatabaseProductName();
      if (productName != null) {
        String normalized = productName.toLowerCase(Locale.ROOT);
        if (normalized.contains("oracle")) {
          return 500;
        }
        if (normalized.contains("postgres")) {
          return 1000;
        }
        if (normalized.contains("mysql")) {
          return 1000;
        }
      }
    } catch (Throwable error) {
      // Fall through to default fetch size.
    }
    return 500;
  }

  private static long elapsedMillis(long startedAt) {
    return (System.nanoTime() - startedAt) / 1_000_000L;
  }

  private static String commentKey(String tableName, String columnName) {
    return tableName + "\u0001" + columnName;
  }

  private static List<Map<String, Object>> collectRows(ResultSet resultSet) throws SQLException {
    ResultSetMetaData metadata = resultSet.getMetaData();
    int columnCount = metadata.getColumnCount();
    List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
    while (resultSet.next()) {
      Map<String, Object> row = new LinkedHashMap<String, Object>();
      for (int index = 1; index <= columnCount; index++) {
        row.put(metadata.getColumnLabel(index).toLowerCase(Locale.ROOT), resultSet.getObject(index));
      }
      rows.add(row);
    }
    return rows;
  }

  private static void validateColumns(List<Map<String, Object>> rows, List<String> requiredColumns) {
    if (rows.isEmpty()) {
      return;
    }
    Map<String, Object> first = rows.get(0);
    for (String column : requiredColumns) {
      if (!first.containsKey(column)) {
        throw new IllegalArgumentException("查询结果缺少列：" + column);
      }
    }
  }

  private static String readUtf8(Path path) throws IOException {
    StringBuilder builder = new StringBuilder();
    try (BufferedReader reader = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
      char[] buffer = new char[4096];
      int read;
      while ((read = reader.read(buffer)) >= 0) {
        builder.append(buffer, 0, read);
      }
    }
    return builder.toString();
  }

  private static void writeJson(Path path, String content) throws IOException {
    if (path.getParent() != null) {
      Files.createDirectories(path.getParent());
    }
    try (BufferedWriter writer = Files.newBufferedWriter(path, StandardCharsets.UTF_8)) {
      writer.write(content);
    }
  }

  private static boolean parseNullable(Object value) {
    String text = stringValue(value).trim().toLowerCase(Locale.ROOT);
    return !("0".equals(text) ||
        "n".equals(text) ||
        "no".equals(text) ||
        "false".equals(text) ||
        "not null".equals(text));
  }

  private static int parseInt(Object value, int fallback) {
    try {
      String text = stringValue(value).trim();
      if (text.isEmpty()) {
        return fallback;
      }
      return Integer.parseInt(text);
    } catch (NumberFormatException error) {
      return fallback;
    }
  }

  private static String stringValue(Object value) {
    return value == null ? "" : String.valueOf(value).trim();
  }

  private static String defaultValue(String primary, String fallback) {
    return primary == null || primary.trim().isEmpty() ? fallback : primary.trim();
  }

  private static Response error(String code, String message) {
    return Response.error(code, message);
  }

  private static String stackTraceToString(Throwable error) {
    StringBuilder builder = new StringBuilder();
    builder.append(error.toString()).append('\n');
    for (StackTraceElement element : error.getStackTrace()) {
      builder.append("  at ").append(element.toString()).append('\n');
    }
    return builder.toString().trim();
  }
}

final class Request {
  final String mode;
  final String databaseType;
  final String dataSourceName;
  final String driverClass;
  final String jdbcUrl;
  final String username;
  final String password;
  final String schemaName;
  final String catalogName;
  final String tableSql;
  final String columnSql;
  final String columnCommentSql;
  final String primaryKeySql;

  private Request(Map<String, Object> data) {
    this.mode = string(data, "mode");
    this.databaseType = string(data, "databaseType");
    this.dataSourceName = string(data, "dataSourceName");
    this.driverClass = string(data, "driverClass");
    this.jdbcUrl = string(data, "jdbcUrl");
    this.username = string(data, "username");
    this.password = string(data, "password");
    this.schemaName = string(data, "schemaName");
    this.catalogName = string(data, "catalogName");
    this.tableSql = string(data, "tableSql");
    this.columnSql = string(data, "columnSql");
    this.columnCommentSql = string(data, "columnCommentSql");
    this.primaryKeySql = string(data, "primaryKeySql");
  }

  static Request fromJson(String content) {
    Object root = new JsonParser(content).parse();
    @SuppressWarnings("unchecked")
    Map<String, Object> data = (Map<String, Object>) root;
    return new Request(data);
  }

  List<Object> tableParams() {
    return parseParameters(tableSql);
  }

  List<Object> columnParams() {
    return parseParameters(columnSql);
  }

  List<Object> primaryKeyParams() {
    return parseParameters(primaryKeySql);
  }

  List<Object> columnCommentParams() {
    return parseParameters(columnCommentSql);
  }

  private List<Object> parseParameters(String sql) {
    String normalizedSql = sql == null ? "" : sql.toUpperCase(Locale.ROOT);
    if (normalizedSql.contains("%SCHEMA%") ||
        normalizedSql.contains("%CATALOG%") ||
        normalizedSql.contains("%USERNAME%") ||
        normalizedSql.contains("%USER%")) {
      return Collections.emptyList();
    }
    int placeholderCount = 0;
    for (int index = 0; index < sql.length(); index++) {
      if (sql.charAt(index) == '?') {
        placeholderCount++;
      }
    }
    if (placeholderCount == 0) {
      return Collections.emptyList();
    }

    List<Object> params = new ArrayList<Object>();
    List<String> pool = Arrays.asList(catalogName, catalogName, schemaName, schemaName, schemaName, schemaName);
    for (int index = 0; index < placeholderCount; index++) {
      params.add(index < pool.size() ? pool.get(index) : schemaName);
    }
    return params;
  }

  private static String string(Map<String, Object> data, String key) {
    Object value = data.get(key);
    return value == null ? "" : String.valueOf(value);
  }
}

final class SqlContext {
  final String schema;
  final String catalog;
  final String user;

  private SqlContext(String schema, String catalog, String user) {
    this.schema = schema;
    this.catalog = catalog;
    this.user = user;
  }

  static SqlContext from(Connection connection, Request request) {
    String currentUser = firstNonBlank(
        safeMetaDataUserName(connection),
        request.username,
        "");
    currentUser = normalizeIdentifier(currentUser);

    String currentSchema = firstNonBlank(
        request.schemaName,
        safeConnectionSchema(connection),
        currentUser);
    currentSchema = normalizeIdentifier(currentSchema);

    String currentCatalog = firstNonBlank(
        request.catalogName,
        safeConnectionCatalog(connection),
        "");
    currentCatalog = normalizeIdentifier(currentCatalog);

    return new SqlContext(currentSchema, currentCatalog, currentUser);
  }

  String resolve(String sql) {
    if (sql == null || sql.trim().isEmpty()) {
      return sql;
    }
    return sql
        .replace("%SCHEMA%", schema)
        .replace("%CATALOG%", catalog)
        .replace("%USERNAME%", user)
        .replace("%USER%", user);
  }

  private static String safeConnectionSchema(Connection connection) {
    try {
      String value = connection.getSchema();
      return value == null ? "" : value;
    } catch (Throwable error) {
      return "";
    }
  }

  private static String safeConnectionCatalog(Connection connection) {
    try {
      String value = connection.getCatalog();
      return value == null ? "" : value;
    } catch (Throwable error) {
      return "";
    }
  }

  private static String safeMetaDataUserName(Connection connection) {
    try {
      String value = connection.getMetaData().getUserName();
      return value == null ? "" : value;
    } catch (Throwable error) {
      return "";
    }
  }

  private static String firstNonBlank(String... values) {
    for (String value : values) {
      if (value != null && !value.trim().isEmpty()) {
        return value.trim();
      }
    }
    return "";
  }

  private static String normalizeIdentifier(String value) {
    String text = value == null ? "" : value.trim();
    if (text.isEmpty()) {
      return "";
    }
    int atIndex = text.indexOf('@');
    if (atIndex > 0) {
      text = text.substring(0, atIndex);
    }
    int slashIndex = text.indexOf('/');
    if (slashIndex > 0) {
      text = text.substring(0, slashIndex);
    }
    return text.trim().toUpperCase(Locale.ROOT);
  }
}

final class Response {
  private final boolean success;
  private final String errorCode;
  private final String errorMessage;
  private final Map<String, Object> payload;

  private Response(boolean success, String errorCode, String errorMessage, Map<String, Object> payload) {
    this.success = success;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
    this.payload = payload;
  }

  static Response success(Map<String, Object> payload) {
    return new Response(true, "", "", payload);
  }

  static Response error(String errorCode, String errorMessage) {
    return new Response(false, errorCode, errorMessage, new LinkedHashMap<String, Object>());
  }

  String toJson() {
    Map<String, Object> root = new LinkedHashMap<String, Object>();
    root.put("success", success);
    if (success) {
      root.put("payload", payload);
    } else {
      root.put("errorCode", errorCode);
      root.put("errorMessage", errorMessage);
    }
    return JsonWriter.write(root);
  }
}

final class DriverShim implements Driver {
  private final Driver driver;

  DriverShim(Driver driver) {
    this.driver = driver;
  }

  public boolean acceptsURL(String u) throws SQLException { return driver.acceptsURL(u); }
  public Connection connect(String u, Properties p) throws SQLException { return driver.connect(u, p); }
  public int getMajorVersion() { return driver.getMajorVersion(); }
  public int getMinorVersion() { return driver.getMinorVersion(); }
  public java.util.logging.Logger getParentLogger() throws java.sql.SQLFeatureNotSupportedException { return driver.getParentLogger(); }
  public DriverPropertyInfo[] getPropertyInfo(String u, Properties p) throws SQLException { return driver.getPropertyInfo(u, p); }
  public boolean jdbcCompliant() { return driver.jdbcCompliant(); }
}

final class JsonWriter {
  static String write(Object value) {
    StringBuilder builder = new StringBuilder();
    append(builder, value);
    return builder.toString();
  }

  private static void append(StringBuilder builder, Object value) {
    if (value == null) {
      builder.append("null");
      return;
    }
    if (value instanceof String) {
      builder.append('"').append(escape((String) value)).append('"');
      return;
    }
    if (value instanceof Number || value instanceof Boolean) {
      builder.append(value.toString());
      return;
    }
    if (value instanceof Map) {
      @SuppressWarnings("unchecked")
      Map<String, Object> map = (Map<String, Object>) value;
      builder.append('{');
      boolean first = true;
      for (Map.Entry<String, Object> entry : map.entrySet()) {
        if (!first) {
          builder.append(',');
        }
        first = false;
        builder.append('"').append(escape(entry.getKey())).append('"').append(':');
        append(builder, entry.getValue());
      }
      builder.append('}');
      return;
    }
    if (value instanceof Iterable) {
      builder.append('[');
      boolean first = true;
      for (Object item : (Iterable<?>) value) {
        if (!first) {
          builder.append(',');
        }
        first = false;
        append(builder, item);
      }
      builder.append(']');
      return;
    }
    builder.append('"').append(escape(String.valueOf(value))).append('"');
  }

  private static String escape(String value) {
    return value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t");
  }
}

final class JsonParser {
  private final String source;
  private int index = 0;

  JsonParser(String source) {
    this.source = source;
  }

  Object parse() {
    skipWhitespace();
    Object value = readValue();
    skipWhitespace();
    return value;
  }

  private Object readValue() {
    skipWhitespace();
    if (index >= source.length()) {
      throw new IllegalStateException("JSON 内容为空。");
    }
    char current = source.charAt(index);
    if (current == '{') {
      return readObject();
    }
    if (current == '[') {
      return readArray();
    }
    if (current == '"') {
      return readString();
    }
    if (current == 't' || current == 'f') {
      return readBoolean();
    }
    if (current == 'n') {
      readNull();
      return null;
    }
    return readNumber();
  }

  private Map<String, Object> readObject() {
    expect('{');
    Map<String, Object> result = new LinkedHashMap<String, Object>();
    skipWhitespace();
    if (peek('}')) {
      expect('}');
      return result;
    }
    while (true) {
      String key = readString();
      skipWhitespace();
      expect(':');
      Object value = readValue();
      result.put(key, value);
      skipWhitespace();
      if (peek('}')) {
        expect('}');
        return result;
      }
      expect(',');
    }
  }

  private List<Object> readArray() {
    expect('[');
    List<Object> result = new ArrayList<Object>();
    skipWhitespace();
    if (peek(']')) {
      expect(']');
      return result;
    }
    while (true) {
      result.add(readValue());
      skipWhitespace();
      if (peek(']')) {
        expect(']');
        return result;
      }
      expect(',');
    }
  }

  private String readString() {
    expect('"');
    StringBuilder builder = new StringBuilder();
    while (index < source.length()) {
      char current = source.charAt(index++);
      if (current == '"') {
        return builder.toString();
      }
      if (current == '\\') {
        if (index >= source.length()) {
          throw new IllegalStateException("非法 JSON 转义。");
        }
        char escape = source.charAt(index++);
        switch (escape) {
          case '"': builder.append('"'); break;
          case '\\': builder.append('\\'); break;
          case '/': builder.append('/'); break;
          case 'b': builder.append('\b'); break;
          case 'f': builder.append('\f'); break;
          case 'n': builder.append('\n'); break;
          case 'r': builder.append('\r'); break;
          case 't': builder.append('\t'); break;
          case 'u':
            String hex = source.substring(index, index + 4);
            builder.append((char) Integer.parseInt(hex, 16));
            index += 4;
            break;
          default:
            throw new IllegalStateException("不支持的转义：" + escape);
        }
        continue;
      }
      builder.append(current);
    }
    throw new IllegalStateException("字符串未闭合。");
  }

  private Boolean readBoolean() {
    if (source.startsWith("true", index)) {
      index += 4;
      return Boolean.TRUE;
    }
    if (source.startsWith("false", index)) {
      index += 5;
      return Boolean.FALSE;
    }
    throw new IllegalStateException("非法布尔值。");
  }

  private void readNull() {
    if (!source.startsWith("null", index)) {
      throw new IllegalStateException("非法 null。");
    }
    index += 4;
  }

  private Number readNumber() {
    int start = index;
    while (index < source.length()) {
      char current = source.charAt(index);
      if ((current >= '0' && current <= '9') || current == '-' || current == '+' || current == '.' || current == 'e' || current == 'E') {
        index++;
        continue;
      }
      break;
    }
    String value = source.substring(start, index);
    if (value.contains(".") || value.contains("e") || value.contains("E")) {
      return Double.valueOf(value);
    }
    return Long.valueOf(value);
  }

  private void skipWhitespace() {
    while (index < source.length()) {
      char current = source.charAt(index);
      if (current == ' ' || current == '\n' || current == '\r' || current == '\t') {
        index++;
        continue;
      }
      break;
    }
  }

  private boolean peek(char expected) {
    skipWhitespace();
    return index < source.length() && source.charAt(index) == expected;
  }

  private void expect(char expected) {
    skipWhitespace();
    if (index >= source.length() || source.charAt(index) != expected) {
      throw new IllegalStateException("期望字符 " + expected + "，当前位置：" + index);
    }
    index++;
  }
}
