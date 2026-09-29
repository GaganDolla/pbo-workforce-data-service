testthat::test_that("real HTTP routes enforce authentication and the JSON contract", {
  database <- tempfile(fileext = ".sqlite")
  log <- tempfile(fileext = ".log")
  con <- fixture_database(database)
  DBI::dbDisconnect(con)
  key <- strrep("test-only-key-", 3)
  port <- httpuv::randomPort()
  server <- processx::process$new(file.path(R.home("bin"), "Rscript"), "scripts/run_api.R",
    wd = project_root, stdout = log, stderr = log,
    env = c("current", WORKFORCE_DB = database, WORKFORCE_HOST = "127.0.0.1",
            WORKFORCE_PORT = as.character(port), WORKFORCE_API_KEY = key))
  on.exit({ server$kill(); unlink(c(database, log)) }, add = TRUE)
  base <- paste0("http://127.0.0.1:", port)
  request <- function(path, credential = key) {
    handle <- curl::new_handle(timeout = 3)
    if (!is.null(credential)) curl::handle_setheaders(handle, "X-API-Key" = credential)
    response <- curl::curl_fetch_memory(paste0(base, path), handle)
    list(status = response$status_code,
         body = jsonlite::fromJSON(rawToChar(response$content), simplifyVector = FALSE),
         text = rawToChar(response$content), headers = rawToChar(response$headers))
  }
  ready <- FALSE
  for (attempt in seq_len(100)) {
    if (!server$is_alive()) stop("API startup failed: ", paste(readLines(log, warn = FALSE), collapse = "\n"))
    probe <- try(request("/api/departments"), silent = TRUE)
    if (!inherits(probe, "try-error")) { ready <- TRUE; break }
    Sys.sleep(0.1)
  }
  testthat::expect_true(ready)
  if (!ready) stop("API did not start within 10 seconds.")
  testthat::expect_equal(request("/api/departments", NULL)$status, 401)
  testthat::expect_equal(request("/api/departments", "wrong-key")$status, 401)
  all <- request("/api/departments")
  testthat::expect_equal(all$status, 200)
  testthat::expect_length(all$body$departments, 3)
  testthat::expect_match(all$headers, "application/json", fixed = TRUE)
  testthat::expect_match(all$headers, "nosniff", fixed = TRUE)
  testthat::expect_null(all$body$departments[[3]]$dept_short$en)
  fte <- request("/api/departments/1/fte?year=2024&tenure=indeterminate")
  testthat::expect_equal(fte$status, 200)
  testthat::expect_equal(fte$body$fte_per_quarter[[1]]$indeterminate, 30.125)
  testthat::expect_named(fte$body$fte_per_quarter[[1]], c("year", "quarter", "indeterminate"))
  testthat::expect_null(fte$body$fte_per_quarter[[2]]$indeterminate)
  testthat::expect_equal(fte$body$fte_per_quarter[[3]]$indeterminate, 0)
  single <- request("/api/departments/1/fte?year=2025")
  testthat::expect_match(single$text, '"fte_per_quarter":[', fixed = TRUE)
  testthat::expect_length(single$body$fte_per_quarter, 1)
  testthat::expect_equal(request("/api/departments/2/fte")$text, '{"fte_per_quarter":[]}')
  for (path in c("/api/departments/1/fte?year=2024.5", "/api/departments/1/fte?tenure=combined",
                 "/api/departments/1/fte?year=2024&year=2025", "/api/departments?surprise=1",
                 "/api/departments/1/fte?year=2024%20OR%201%3D1")) {
    response <- request(path)
    testthat::expect_equal(response$status, 400, info = path)
    testthat::expect_equal(response$body$error$code, "invalid_parameter")
  }
  testthat::expect_equal(request("/api/departments/999/fte")$status, 404)
  testthat::expect_equal(request("/not-a-route")$status, 404)
  # A lost database must produce a generic error, without paths or stack traces.
  unlink(database)
  failure <- request("/api/departments")
  testthat::expect_equal(failure$status, 500)
  testthat::expect_equal(failure$body$error$message, "Internal server error.")
  testthat::expect_false(grepl(database, failure$text, fixed = TRUE))
  testthat::expect_false(any(grepl(key, readLines(log, warn = FALSE), fixed = TRUE)))
})
