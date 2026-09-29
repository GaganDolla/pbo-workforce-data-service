if (!file.exists("DESCRIPTION")) stop("Run from the project root.")
Sys.setenv(WORKFORCE_PROJECT_ROOT = normalizePath("."))
testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
