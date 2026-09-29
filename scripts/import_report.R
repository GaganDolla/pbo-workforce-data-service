source("scripts/bootstrap.R")
con <- connect_database(Sys.getenv("WORKFORCE_DB", "var/workforce.sqlite"), readonly = TRUE)
tryCatch({
  print(DBI::dbGetQuery(con, "SELECT * FROM import_runs ORDER BY run_id DESC LIMIT 1"))
  print(DBI::dbGetQuery(con, paste(
    "SELECT severity, code, field, COUNT(*) AS count FROM import_issues",
    "WHERE run_id = (SELECT MAX(run_id) FROM import_runs)",
    "GROUP BY severity, code, field ORDER BY severity, code, field")))
}, finally = DBI::dbDisconnect(con))
