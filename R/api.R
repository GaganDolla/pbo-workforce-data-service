build_api <- function(database_path, api_key = "") {
  con <- connect_database(database_path, readonly = TRUE)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  assert_database_ready(con)
  if (nzchar(api_key) && nchar(api_key, type = "bytes") < 32L) stop("WORKFORCE_API_KEY must contain at least 32 bytes.")
  expected_key_hash <- if (nzchar(api_key)) digest::digest(api_key, algo = "sha256", serialize = FALSE) else NULL
  with_database <- function(callback) {
    con <- connect_database(database_path, readonly = TRUE)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    # All queries for one request see the same committed snapshot.
    DBI::dbWithTransaction(con, callback(con))
  }
  router <- plumber::pr()
  router <- plumber::pr_set_debug(router, FALSE)
  router <- plumber::pr_set_docs(router, FALSE)
  router <- plumber::pr_set_serializer(router, plumber::serializer_json(auto_unbox = TRUE, na = "null", null = "null", digits = NA))
  router <- plumber::pr_set_error(router, function(req, res, err) {
    if (inherits(err, "workforce_api_error")) {
      res$status <- err$status
      return(list(error = list(code = err$code, message = err$message)))
    }
    # Do not emit request parameters, credentials, source data, or stack traces.
    message("Internal API error; inspect service/database health.")
    res$status <- 500L
    list(error = list(code = "internal_error", message = "Internal server error."))
  })
  router <- plumber::pr_set_404(router, function(req, res) {
    res$status <- 404L
    list(error = list(code = "not_found", message = "Route not found."))
  })
  router <- plumber::pr_filter(router, "security", function(req, res) {
    res$setHeader("X-Content-Type-Options", "nosniff")
    res$setHeader("Cache-Control", "no-store")
    if (!is.null(expected_key_hash)) {
      supplied <- req$HTTP_X_API_KEY
      if (is.null(supplied) || length(supplied) != 1L || nchar(supplied, type = "bytes") > 1024L ||
          !identical(digest::digest(supplied, algo = "sha256", serialize = FALSE), expected_key_hash)) {
        api_error(401L, "unauthorized", "A valid X-API-Key header is required.")
      }
    }
    plumber::forward()
  })
  validate_query <- function(req, allowed) {
    query <- req$argsQuery
    if (length(setdiff(names(query), allowed))) api_error(400L, "invalid_parameter", "Unsupported query parameter.")
    if (anyDuplicated(names(query))) api_error(400L, "invalid_parameter", "Repeated query parameters are not supported.")
  }
  router <- plumber::pr_get(router, "/api/departments", function(req, res) {
    validate_query(req, character())
    with_database(get_departments)
  })
  router <- plumber::pr_get(router, "/api/departments/<id>/fte", function(req, res, id) {
    validate_query(req, c("year", "tenure"))
    with_database(function(con) get_quarterly_fte(con, id, req$argsQuery$year, req$argsQuery$tenure))
  })
  router
}

validate_listener <- function(host, api_key) {
  if (!host %in% c("127.0.0.1", "localhost", "::1") && !nzchar(api_key)) {
    stop("Non-loopback binding requires WORKFORCE_API_KEY. Deploy behind TLS and access controls.")
  }
  if (nzchar(api_key) && nchar(api_key, type = "bytes") < 32L) stop("WORKFORCE_API_KEY must contain at least 32 bytes.")
  invisible(TRUE)
}
