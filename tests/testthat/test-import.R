testthat::test_that("normalization is explicit and raw values remain auditable", {
  sheets <- fixture_sheets()
  sheets$Departments <- rbind(sheets$Departments, sheets$Departments[1, ])
  sheets$`Federal Public Service`$department[1] <- "  Privy   Council Office  "
  sheets$`Federal Public Service`$department[2] <- "Privy Council Officee"
  sheets$`Federal Public Service`$tenure[1] <- " Indeterminate "
  sheets$`Federal Public Service`$tenure[2] <- NA
  sheets$`Federal Public Service`$headcount[1] <- "-20"
  sheets$`Federal Public Service`$fte[3] <- "not-a-number"
  prepared <- prepare_import(sheets)
  testthat::expect_equal(nrow(prepared$departments), 3)
  testthat::expect_equal(prepared$observations$department[1:2], rep("Privy Council Office", 2))
  testthat::expect_equal(prepared$observations$tenure[2], "missing")
  testthat::expect_true(is.na(prepared$observations$headcount[1]))
  testthat::expect_equal(prepared$observations$fte[1], 10)
  testthat::expect_true(is.na(prepared$observations$fte[3]))
  testthat::expect_match(prepared$observations$raw_record[1], "-20", fixed = TRUE)
  testthat::expect_true(all(c("duplicate_reference", "department_alias", "missing_tenure", "invalid_metric") %in% prepared$issues$code))
  testthat::expect_true(all(is.na(prepared$observations$fte[prepared$observations$tenure == "combined"])))
})

testthat::test_that("ambiguous identities, dates and duplicate observations fail closed", {
  sheets <- fixture_sheets()
  sheets$Departments <- rbind(sheets$Departments, transform(sheets$Departments[1, ], short_name_en = "DIFFERENT"))
  testthat::expect_error(prepare_import(sheets), "Conflicting reference")
  for (bad in c("202413", "202400", "2024", "202401.5", NA)) {
    sheets <- fixture_sheets()
    sheets$`Federal Public Service`$date[1] <- bad
    testthat::expect_error(prepare_import(sheets), "Invalid reporting month")
  }
  sheets <- fixture_sheets()
  sheets$`Federal Public Service`$department[1] <- "Unknown department"
  testthat::expect_error(prepare_import(sheets), "Unknown department")
  sheets <- fixture_sheets()
  sheets$`Federal Public Service`$tenure[1] <- "Typo"
  testthat::expect_error(prepare_import(sheets), "Unknown tenure")
  sheets <- fixture_sheets()
  sheets$`Federal Public Service` <- rbind(sheets$`Federal Public Service`, sheets$`Federal Public Service`[1, ])
  testthat::expect_error(prepare_import(sheets), "Duplicate observation key")
  sheets <- fixture_sheets()
  sheets$`Federal Public Service`$fte <- NULL
  testthat::expect_error(prepare_import(sheets), "headers")
})

testthat::test_that("metric validation preserves zeros and flags unusual FTE", {
  sheets <- fixture_sheets()
  sheets$`Federal Public Service`$headcount[1:4] <- c("1.5", "2147483648", "Inf", "abc")
  sheets$`Federal Public Service`$fte[1:4] <- c("NaN", "Inf", "-1", "101")
  prepared <- prepare_import(sheets)
  testthat::expect_true(all(is.na(prepared$observations$headcount[1:4])))
  testthat::expect_true(all(is.na(prepared$observations$fte[1:3])))
  testthat::expect_equal(prepared$observations$fte[5], 0)
  sheets <- fixture_sheets()
  sheets$`Federal Public Service`$fte[1] <- "101"
  prepared <- prepare_import(sheets)
  testthat::expect_equal(prepared$observations$fte[1], 101)
  testthat::expect_true("fte_above_headcount" %in% prepared$issues$code)
})

testthat::test_that("imports are idempotent, preserve IDs, and roll back on failure", {
  con <- fixture_database()
  on.exit(DBI::dbDisconnect(con))
  before <- DBI::dbGetQuery(con, "SELECT * FROM workforce_observations")
  ids <- DBI::dbGetQuery(con, "SELECT * FROM departments ORDER BY dept_id")
  same <- publish_import(con, prepare_import(fixture_sheets()), "fixture.xlsx", "fixture-hash")
  testthat::expect_equal(same$status, "unchanged")
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM import_runs")$n, 1)
  bad <- prepare_import(fixture_sheets())
  bad$observations$headcount[1] <- -1L
  bad$departments$long_name_fr[1] <- "Changed name"
  testthat::expect_error(publish_import(con, bad, "bad.xlsx", "different-hash"), "CHECK constraint")
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT * FROM workforce_observations"), before)
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT * FROM departments ORDER BY dept_id"), ids)
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM import_runs")$n, 1)
  good <- prepare_import(fixture_sheets())
  good$observations$fte[1] <- 99
  publish_import(con, good, "revision.xlsx", "revision-hash")
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM workforce_observations")$n, nrow(before))
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT * FROM departments ORDER BY dept_id"), ids)
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM import_runs")$n, 2)
})

testthat::test_that("real workbook adapter imports all sheets and reimport is safe", {
  input <- tempfile(fileext = ".xlsx")
  database <- tempfile(fileext = ".sqlite")
  on.exit(unlink(c(input, database)))
  writexl::write_xlsx(fixture_sheets(), input)
  result <- import_workbook(input, database, migration_path)
  testthat::expect_equal(result$observations, 9)
  testthat::expect_equal(import_workbook(input, database, migration_path)$status, "unchanged")
  sheets <- fixture_sheets()
  sheets$CAF <- NULL
  writexl::write_xlsx(sheets, input)
  testthat::expect_error(import_workbook(input, database, migration_path), "missing a required worksheet")
  con <- connect_database(database, TRUE)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM workforce_observations")$n, 9)
})
