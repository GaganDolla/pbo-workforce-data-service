normalize_text <- function(x) {
  x <- trimws(gsub("[[:space:]\u00a0]+", " ", as.character(x)))
  x[!is.na(x) & x == ""] <- NA_character_
  x
}

empty_issues <- function() {
  data.frame(source_sheet = character(), source_row = integer(), severity = character(),
             code = character(), field = character(), raw_value = character(), action = character())
}

read_source_workbook <- function(path) {
  if (!file.exists(path)) stop("Workbook does not exist: ", path)
  if (tolower(tools::file_ext(path)) != "xlsx") stop("Expected an .xlsx workbook.")
  if (file.info(path)$size > 25 * 1024^2) stop("Workbook exceeds the prototype's 25 MiB limit.")
  zip_entries <- utils::unzip(path, list = TRUE)
  if (sum(zip_entries$Length) > 200 * 1024^2) stop("Expanded workbook exceeds 200 MiB.")
  expected <- c("Departments", "Federal Public Service", "RCMP", "CAF")
  if (!all(expected %in% readxl::excel_sheets(path))) stop("Workbook is missing a required worksheet.")
  # Text reads retain malformed numbers and spaces for validation and auditing.
  setNames(lapply(expected, function(sheet) {
    as.data.frame(readxl::read_excel(path, sheet = sheet, col_types = "text",
                                  trim_ws = FALSE, .name_repair = "minimal"))
  }), expected)
}

prepare_import <- function(sheets) {
  issues <- list()
  add_issue <- function(sheet, rows, severity, code, field, raw, action) {
    if (!length(rows)) return(invisible(NULL))
    issues[[length(issues) + 1L]] <<- data.frame(
      source_sheet = sheet, source_row = as.integer(rows), severity = severity,
      code = code, field = field, raw_value = as.character(raw), action = action)
  }
  require_columns <- function(data, columns, sheet) {
    if (anyDuplicated(names(data)) || !all(columns %in% names(data))) {
      stop("Invalid or missing headers in worksheet: ", sheet)
    }
    if (!nrow(data)) stop("Empty required worksheet: ", sheet)
  }
  clean_field <- function(x, sheet, field, rows) {
    clean <- normalize_text(x)
    changed <- which(!is.na(x) & (is.na(clean) | x != clean))
    add_issue(sheet, rows[changed], "info", "normalized_text", field, x[changed],
              "Collapsed whitespace and converted empty text to missing.")
    clean
  }
  ref <- sheets[["Departments"]]
  ref_columns <- c("long_name_en", "long_name_fr", "short_name_en", "short_name_fr")
  require_columns(ref, ref_columns, "Departments")
  ref <- ref[ref_columns]
  for (field in ref_columns) ref[[field]] <- clean_field(ref[[field]], "Departments", field, seq_len(nrow(ref)) + 1L)
  if (anyNA(ref$long_name_en) || anyNA(ref$long_name_fr)) stop("Department long names are required in both languages.")
  duplicate <- duplicated(ref)
  add_issue("Departments", which(duplicate) + 1L, "info", "duplicate_reference", "department",
            ref$long_name_en[duplicate], "Removed identical reference row.")
  ref <- ref[!duplicate, , drop = FALSE]
  if (anyDuplicated(ref$long_name_en)) stop("Conflicting reference records for the same department name.")
  # Explicit reviewed correction; no fuzzy matching of organization identities.
  aliases <- c("Privy Council Officee" = "Privy Council Office")
  observations <- list()
  for (sheet in c("Federal Public Service", "RCMP", "CAF")) {
    raw <- sheets[[sheet]]
    required <- c("date", "tenure", "department", "headcount")
    if (sheet == "Federal Public Service") required <- c(required, "fte")
    require_columns(raw, required, sheet)
    rows <- seq_len(nrow(raw)) + 1L
    data <- raw
    for (field in c("date", "tenure", "department")) data[[field]] <- clean_field(raw[[field]], sheet, field, rows)
    date_ok <- !is.na(data$date) & grepl("^[0-9]{6}$", data$date)
    year <- suppressWarnings(as.integer(substr(data$date, 1, 4)))
    month <- suppressWarnings(as.integer(substr(data$date, 5, 6)))
    date_ok <- date_ok & !is.na(year) & year >= 1900 & year <= 2100 & !is.na(month) & month >= 1 & month <= 12
    if (any(!date_ok)) stop("Invalid reporting month in ", sheet, " at Excel row ", rows[which(!date_ok)[1]])
    mapped <- which(!is.na(data$department) & data$department %in% names(aliases))
    add_issue(sheet, rows[mapped], "info", "department_alias", "department", data$department[mapped], "Mapped explicit spelling correction.")
    data$department[mapped] <- unname(aliases[data$department[mapped]])
    unknown <- which(is.na(data$department) | !data$department %in% ref$long_name_en)
    if (length(unknown)) stop("Unknown department in ", sheet, " at Excel row ", rows[unknown[1]], ": ", data$department[unknown[1]])
    missing_tenure <- which(is.na(data$tenure))
    add_issue(sheet, rows[missing_tenure], "warning", "missing_tenure", "tenure", raw$tenure[missing_tenure], "Mapped blank tenure to missing.")
    tenure <- tolower(data$tenure)
    tenure[is.na(tenure)] <- "missing"
    allowed <- if (sheet == "Federal Public Service") c("indeterminate", "term", "casual", "student", "missing") else "combined"
    if (any(!tenure %in% allowed)) stop("Unknown tenure in ", sheet, " at Excel row ", rows[which(!tenure %in% allowed)[1]])
    parse_metric <- function(field, integer_only = FALSE) {
      text <- normalize_text(raw[[field]])
      number <- suppressWarnings(as.numeric(text))
      missing <- which(is.na(text))
      invalid <- which(!is.na(text) & (!is.finite(number) | number < 0 |
                        (integer_only & (number != floor(number) | number > .Machine$integer.max))))
      add_issue(sheet, rows[missing], "warning", "missing_metric", field, raw[[field]][missing], "Stored NULL; retained other valid fields.")
      add_issue(sheet, rows[invalid], "error", "invalid_metric", field, raw[[field]][invalid], "Stored NULL; original value retained in raw_record.")
      number[c(missing, invalid)] <- NA_real_
      if (integer_only) as.integer(number) else number
    }
    headcount <- parse_metric("headcount", TRUE)
    if ("fte" %in% names(raw)) {
      fte <- parse_metric("fte")
    } else {
      fte <- rep(NA_real_, nrow(raw))
      add_issue(sheet, NA_integer_, "info", "fte_not_provided", "fte", NA_character_, "Source supplies headcount only; FTE stored NULL.")
    }
    above <- which(!is.na(fte) & !is.na(headcount) & fte > headcount + 1e-8)
    add_issue(sheet, rows[above], "warning", "fte_above_headcount", "fte", raw$fte[above], "Retained reported FTE; business definition needs confirmation.")
    raw_json <- vapply(seq_len(nrow(raw)), function(i) {
      as.character(jsonlite::toJSON(as.list(raw[i, , drop = FALSE]), auto_unbox = TRUE, na = "null"))
    }, character(1))
    observations[[sheet]] <- data.frame(department = data$department, year = year, month = month,
      tenure = tenure, headcount = headcount, fte = fte, source_sheet = sheet,
      source_row = rows, raw_record = raw_json, stringsAsFactors = FALSE)
  }
  observations <- do.call(rbind, observations)
  key <- observations[c("department", "year", "month", "tenure")]
  if (anyDuplicated(key)) stop("Duplicate observation key after normalization; resolve before importing.")
  list(departments = ref, observations = observations,
       issues = if (length(issues)) do.call(rbind, issues) else empty_issues())
}

publish_import <- function(con, prepared, file_name, sha256) {
  # Validate first, then atomically publish all sources together.
  DBI::dbWithTransaction(con, {
    latest <- DBI::dbGetQuery(con, "SELECT run_id, file_sha256 FROM import_runs ORDER BY run_id DESC LIMIT 1")
    if (nrow(latest) && latest$file_sha256 == sha256) {
      result <- list(status = "unchanged", run_id = latest$run_id)
    } else {
      ref <- prepared$departments
      for (i in seq_len(nrow(ref))) {
        DBI::dbExecute(con, paste(
          "INSERT INTO departments(long_name_en, long_name_fr, short_name_en, short_name_fr) VALUES (?, ?, ?, ?)",
          "ON CONFLICT(long_name_en) DO UPDATE SET long_name_fr=excluded.long_name_fr,",
          "short_name_en=excluded.short_name_en, short_name_fr=excluded.short_name_fr"), params = unname(as.list(ref[i, ])))
      }
      DBI::dbExecute(con, "INSERT INTO import_runs(file_name,file_sha256,imported_at,observation_count,issue_count) VALUES(?,?,?,?,?)",
        params = list(basename(file_name), sha256, format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                      nrow(prepared$observations), nrow(prepared$issues)))
      run_id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id
      ids <- DBI::dbGetQuery(con, "SELECT dept_id,long_name_en FROM departments")
      obs <- prepared$observations
      obs$dept_id <- ids$dept_id[match(obs$department, ids$long_name_en)]
      obs$department <- NULL
      obs$run_id <- run_id
      DBI::dbExecute(con, "DELETE FROM workforce_observations")
      DBI::dbAppendTable(con, "workforce_observations", obs)
      if (nrow(prepared$issues)) {
        issues <- prepared$issues
        issues$run_id <- run_id
        DBI::dbAppendTable(con, "import_issues", issues)
      }
      result <- list(status = "imported", run_id = run_id, departments = nrow(ref),
                     observations = nrow(obs), issues = nrow(prepared$issues))
    }
    result
  })
}

import_workbook <- function(path, database_path, migration = "migrations/001_initial.sql") {
  # Hash both before and after reading to catch a workbook changed during import.
  sha256 <- digest::digest(file = path, algo = "sha256")
  prepared <- prepare_import(read_source_workbook(path))
  if (digest::digest(file = path, algo = "sha256") != sha256) stop("Workbook changed while reading; retry with a stable copy.")
  con <- connect_database(database_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  migrate_database(con, migration)
  publish_import(con, prepared, basename(path), sha256)
}
