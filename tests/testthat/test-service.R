testthat::test_that("department response preserves bilingual structure and null abbreviations", {
  con <- fixture_database()
  on.exit(DBI::dbDisconnect(con))
  result <- get_departments(con)
  testthat::expect_named(result, "departments")
  testthat::expect_length(result$departments, 3)
  testthat::expect_named(result$departments[[1]], c("dept_id", "dept_long", "dept_short"))
  testthat::expect_equal(result$departments[[1]]$dept_long$fr, "Bureau du Conseil privé")
  testthat::expect_true(is.na(result$departments[[3]]$dept_short$en))
})

testthat::test_that("quarter-end values are neither summed nor averaged and null differs from zero", {
  con <- fixture_database()
  on.exit(DBI::dbDisconnect(con))
  result <- get_quarterly_fte(con, "1", "2024")$fte_per_quarter
  testthat::expect_length(result, 4)
  testthat::expect_equal(result[[1]]$indeterminate, 30.125)
  testthat::expect_true(is.na(result[[1]]$student))
  testthat::expect_true(is.na(result[[2]]$indeterminate))
  testthat::expect_equal(result[[3]]$indeterminate, 0)
  testthat::expect_equal(result[[4]]$quarter, 4)
  testthat::expect_equal(get_quarterly_fte(con, "1", "2025")$fte_per_quarter[[1]]$indeterminate, 50)
  testthat::expect_length(get_quarterly_fte(con, "1", "2020")$fte_per_quarter, 0)
  testthat::expect_length(get_quarterly_fte(con, "2")$fte_per_quarter, 0)
  testthat::expect_length(get_quarterly_fte(con, "3")$fte_per_quarter, 0)
  filtered <- get_quarterly_fte(con, "1", "2024", "indeterminate")$fte_per_quarter
  testthat::expect_named(filtered[[1]], c("year", "quarter", "indeterminate"))
  testthat::expect_length(get_quarterly_fte(con, "1", tenure = "student")$fte_per_quarter, 0)
})

testthat::test_that("absent quarter-end observations are not carried forward", {
  con <- fixture_database()
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "DELETE FROM workforce_observations WHERE dept_id=1 AND year=2024 AND month=3")
  testthat::expect_true(is.na(get_quarterly_fte(con, "1", "2024")$fte_per_quarter[[1]]$indeterminate))
})

testthat::test_that("invalid filters, unknown IDs and SQL injection are rejected", {
  con <- fixture_database()
  on.exit(DBI::dbDisconnect(con))
  for (id in c("0", "-1", "1.5", "1 OR 1=1", "999999999999", "abc")) {
    testthat::expect_error(get_quarterly_fte(con, id), class = "workforce_api_error")
  }
  testthat::expect_error(get_quarterly_fte(con, "999"), "Department not found")
  for (year in list("2024.5", "2024 OR 1=1", "1899", "2101", "", c("2024", "2025"))) {
    testthat::expect_error(get_quarterly_fte(con, "1", year), class = "workforce_api_error")
  }
  for (tenure in list("combined", "Student", "anything", "' OR 1=1 --", c("term", "casual"))) {
    testthat::expect_error(get_quarterly_fte(con, "1", tenure = tenure), class = "workforce_api_error")
  }
  testthat::expect_length(get_departments(con)$departments, 3)
})

testthat::test_that("database relationships and read-only access are enforced", {
  path <- tempfile(fileext = ".sqlite")
  con <- fixture_database(path)
  on.exit(unlink(path))
  testthat::expect_error(DBI::dbExecute(con, "UPDATE workforce_observations SET dept_id=999 WHERE dept_id=1"), "FOREIGN KEY")
  DBI::dbDisconnect(con)
  con <- connect_database(path, TRUE)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  testthat::expect_error(DBI::dbExecute(con, "DELETE FROM departments"), "readonly")
})

testthat::test_that("remote binding needs authentication", {
  testthat::expect_silent(validate_listener("127.0.0.1", ""))
  testthat::expect_error(validate_listener("0.0.0.0", ""), "requires")
  testthat::expect_error(validate_listener("127.0.0.1", "short"), "32 bytes")
  testthat::expect_silent(validate_listener("0.0.0.0", strrep("x", 32)))
})
