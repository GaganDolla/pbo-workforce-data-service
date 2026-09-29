# Run entry-point scripts from the repository root.
if (!file.exists("DESCRIPTION") || !dir.exists("R")) stop("Run this command from the project root.")
for (file in c("database.R", "import.R", "service.R", "api.R")) source(file.path("R", file))
