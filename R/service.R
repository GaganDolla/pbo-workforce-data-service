api_error <- function(status, code, message) {
  stop(structure(list(message = message, call = NULL, status = status, code = code),
                 class = c("workforce_api_error", "error", "condition")))
}

parse_integer_parameter <- function(value, name, minimum, maximum) {
  if (length(value) != 1L || is.na(value) || !is.character(value) ||
      !grepl("^[0-9]+$", value) || nchar(value) > 10L) {
    api_error(400L, "invalid_parameter", paste(name, "must be a single whole number."))
  }
  value <- suppressWarnings(as.numeric(value))
  if (!is.finite(value) || value < minimum || value > maximum) {
    api_error(400L, "invalid_parameter", paste(name, "is outside the supported range."))
  }
  as.integer(value)
}

get_departments <- function(con) {
  data <- DBI::dbGetQuery(con, "SELECT * FROM departments ORDER BY dept_id")
  list(departments = lapply(seq_len(nrow(data)), function(i) {
    list(dept_id = data$dept_id[i],
         dept_long = list(en = data$long_name_en[i], fr = data$long_name_fr[i]),
         dept_short = list(en = data$short_name_en[i], fr = data$short_name_fr[i]))
  }))
}

get_quarterly_fte <- function(con, id, year = NULL, tenure = NULL) {
  id <- parse_integer_parameter(id, "id", 1, .Machine$integer.max)
  if (!is.null(year)) year <- parse_integer_parameter(year, "year", 1900, 2100)
  categories <- c("indeterminate", "term", "casual", "student", "missing")
  if (!is.null(tenure)) {
    if (length(tenure) != 1L || is.na(tenure) || !is.character(tenure) || !tenure %in% categories) {
      api_error(400L, "invalid_parameter", paste("tenure must be one of:", paste(categories, collapse = ", ")))
    }
  }
  exists <- DBI::dbGetQuery(con, "SELECT dept_id FROM departments WHERE dept_id = ?", params = list(id))
  if (!nrow(exists)) api_error(404L, "department_not_found", "Department not found.")
  # Quarter-end stock measure. A CASE preserves NULL for missing quarter-end data.
  sql <- paste("SELECT year, CAST((month + 2) / 3 AS INTEGER) AS quarter, tenure,",
               "MAX(CASE WHEN month IN (3,6,9,12) THEN fte END) AS fte",
               "FROM workforce_observations WHERE dept_id = ? AND source_sheet = 'Federal Public Service'")
  params <- list(id)
  if (!is.null(year)) { sql <- paste(sql, "AND year = ?"); params <- c(params, list(year)) }
  if (!is.null(tenure)) { sql <- paste(sql, "AND tenure = ?"); params <- c(params, list(tenure)) }
  sql <- paste(sql, "GROUP BY year, quarter, tenure ORDER BY year, quarter, tenure")
  data <- DBI::dbGetQuery(con, sql, params = params)
  periods <- unique(data[c("year", "quarter")])
  fields <- if (is.null(tenure)) categories else tenure
  list(fte_per_quarter = lapply(seq_len(nrow(periods)), function(i) {
    part <- data[data$year == periods$year[i] & data$quarter == periods$quarter[i], ]
    row <- list(year = periods$year[i], quarter = periods$quarter[i])
    for (field in fields) {
      value <- part$fte[part$tenure == field]
      row[[field]] <- if (!length(value) || is.na(value)) NA_real_ else value
    }
    row
  }))
}
