library(readxl)
library(dplyr)

workbook_path <- "Data/data.xlsx"

workforce <- read_excel(
  workbook_path,
  sheet = "Federal Public Service"
)

departments <- readxl::read_excel(
  workbook_path,
  sheet = "Departments"
)

# Inspect column types and sample values.
glimpse(workforce)
glimpse(departments)

# Count records for each tenure label.
# Brackets make surrounding spaces visible.
workforce |>
  mutate(tenure_label = paste0("[", tenure, "]")) |>
  count(tenure_label, sort = TRUE)

# Count missing values in each column.
workforce |>
  summarise(across(everything(), ~ sum(is.na(.x))))

# Inspect negative headcounts.
workforce |>
  filter(headcount < 0)

# Workforce department names absent from the reference sheet.
unmatched_departments <- workforce |>
  distinct(department) |>
  anti_join(
    departments,
    by = c("department" = "long_name_en")
  )

unmatched_departments

# Inspect the reference entry with the CAF abbreviation.
departments |>
  filter(short_name_en == "CAF")

# Check whether English department names are unique.
departments |>
  count(long_name_en) |>
  filter(n > 1)
