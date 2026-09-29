source("scripts/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 2L) stop("Usage: Rscript scripts/import.R [workbook.xlsx] [database.sqlite]")
input <- if (length(args) >= 1L) args[1] else "Data/data.xlsx"
database <- if (length(args) >= 2L) args[2] else Sys.getenv("WORKFORCE_DB", "var/workforce.sqlite")
result <- import_workbook(input, database)
cat(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE), "\n")
