project_root <- Sys.getenv("WORKFORCE_PROJECT_ROOT")
for (file in c("database.R", "import.R", "service.R", "api.R")) source(file.path(project_root, "R", file))
migration_path <- file.path(project_root, "migrations", "001_initial.sql")

fixture_sheets <- function() {
  ref <- data.frame(long_name_en = c("Privy Council Office", "RCMP Members", "Canadian Armed Forces"),
                    long_name_fr = c("Bureau du Conseil privé", "Membres GRC", "Forces armées canadiennes"),
                    short_name_en = c("PCO", "RCMP", NA), short_name_fr = c("BCP", "GRC", NA))
  fps <- data.frame(date = c("202401", "202402", "202403", "202406", "202409", "202412", "202503"),
                    tenure = "Indeterminate", department = "Privy Council Office",
                    headcount = "100", fte = c("10", "20", "30.125", NA, "0", "40", "50"))
  list(Departments = ref, `Federal Public Service` = fps,
       RCMP = data.frame(date = "202403", tenure = "Combined", department = "RCMP Members", headcount = "200"),
       CAF = data.frame(date = "202403", tenure = "Combined", department = "Canadian Armed Forces", headcount = "300"))
}

fixture_database <- function(path = ":memory:") {
  con <- connect_database(path)
  migrate_database(con, migration_path)
  publish_import(con, prepare_import(fixture_sheets()), "fixture.xlsx", "fixture-hash")
  con
}
