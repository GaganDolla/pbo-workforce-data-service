# The primary-key index starts with department/year, matching the FTE query.
connect_database <- function(path, readonly = FALSE) {
  if (readonly && !file.exists(path)) stop("Database not found. Run scripts/import.R first.")
  if (!readonly && path != ":memory:") dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = path,
                       flags = if (readonly) RSQLite::SQLITE_RO else RSQLite::SQLITE_RWC,
                       synchronous = "full", loadable.extensions = FALSE)
  tryCatch({
    DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
    DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
    if (readonly) DBI::dbExecute(con, "PRAGMA query_only = ON")
    con
  }, error = function(e) { DBI::dbDisconnect(con); stop(e) })
}

migrate_database <- function(con, migration = "migrations/001_initial.sql") {
  if (DBI::dbExistsTable(con, "schema_version")) {
    version <- DBI::dbGetQuery(con, "SELECT version FROM schema_version")$version
    if (!identical(version, 1L)) stop("Unsupported database schema version.")
    return(invisible(NULL))
  }
  statements <- strsplit(paste(readLines(migration, warn = FALSE), collapse = "\n"), ";", fixed = TRUE)[[1]]
  DBI::dbWithTransaction(con, {
    for (sql in statements[nzchar(trimws(statements))]) DBI::dbExecute(con, sql)
  })
  invisible(NULL)
}

assert_database_ready <- function(con) {
  if (!DBI::dbExistsTable(con, "schema_version") ||
      !identical(DBI::dbGetQuery(con, "SELECT version FROM schema_version")$version, 1L)) {
    stop("Database schema is missing or unsupported.")
  }
  if (DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM import_runs")$n == 0) {
    stop("Database has no successful import.")
  }
  invisible(TRUE)
}
