# Import and database design

## Flow and boundaries

`Data/data.xlsx` → `read_source_workbook()` → `prepare_import()` →
`publish_import()` → SQLite → `get_departments()` / `get_quarterly_fte()` → Plumber.

The Excel adapter, normalization/validation, transactional persistence, query
logic, and HTTP routing are separate functions. Tests exercise them independently.
An external API adapter could later produce the same source structures, while
revision handling would need the additions described in [Question 2](design-questions.md).
The prototype accepts the supplied XLSX layout, not arbitrary formats.

## Relational model

The schema is in [001_initial.sql](../migrations/001_initial.sql).

| Table | Purpose and constraints |
| --- | --- |
| `departments` | Surrogate `dept_id`, unique normalized English long name, required English/French long names, nullable abbreviations |
| `workforce_observations` | One department/month/tenure measurement. Primary key `(dept_id, year, month, tenure)`. Source sheet/Excel row, import run and raw cell values |
| `import_runs` | Successful publication timestamp in UTC, workbook basename and SHA-256, row and issue counts |
| `import_issues` | Run, worksheet, Excel row, severity, issue code, field, original value and action taken |
| `schema_version` | Initial schema version. Unsupported versions fail explicitly |

Department and import references are foreign keys, enabled on each connection.
Headcount must be a nonnegative integer or NULL. FTE must be a nonnegative number or NULL.
Year/month and tenure constraints provide a second layer behind importer validation.
The primary-key index supports department/year range queries. No separate redundant
index is added. Tenure is a checked value rather than an unnecessary lookup table
for this small fixed vocabulary.

Year and month preserve the source's monthly meaning without inventing a day or
timezone. Quarter is derived, not stored. FTE is SQLite REAL. Binary floating-point
precision is retained in responses, with tolerance in comparison checks. This is
not a currency calculation. A future requirement for exact decimal arithmetic
would justify a PostgreSQL NUMERIC column and an agreed decimal scale.

IDs are assigned once and retained on subsequent imports through name-based
upserts. Reordering the worksheet does not change existing IDs. Previously known
departments remain in the registry even if omitted from a later workbook. Their
old observations are removed by the full replacement. A genuine department rename
needs an explicit identity mapping: names are not a permanent organization ID.

## Import rules

Implemented in [R/import.R](../R/import.R):

1. Accept a local `.xlsx` file up to 25 MiB and 200 MiB of declared expanded ZIP
   content. Require the four named worksheets and their required, unique headers.
   Additional worksheets/columns are ignored for modelling. Extra columns on a
   workforce sheet remain in its raw record. These are prototype limits, not a
   general-purpose hostile-file sandbox.
2. Read cells as text with whitespace trimming disabled. Retain these parsed
   values in `raw_record` JSON for every observation. Retain the original workbook
   separately. JSON stores parsed cell values, not formulas, styles or original
   XLSX XML. Hash the file before and after reading to detect concurrent changes.
3. Trim and collapse whitespace in identity fields. Normalize tenure to lowercase.
   Map the single explicit alias `Privy Council Officee` → `Privy Council Office`.
   No fuzzy organization matching is performed.
4. Remove identical department reference rows, recording an issue. Reject
   conflicting bilingual reference rows, unknown departments, invalid reporting
   months, unknown tenure labels and duplicate normalized observation keys.
   Identity errors abort the entire import instead of guessing which row to use.
5. Map a blank tenure to `missing`, with a warning. Preserve the source's `Missing`
   category separately from missing numeric values. RCMP/CAF use `combined`.
6. For missing or invalid measurements, store NULL for that field, retain valid
   measurements on the same row, and record an issue. Negative headcount is not
   converted to positive. Fractional/non-finite/over-32-bit headcounts and negative
   or non-finite FTE are invalid. This preserves all supplied workforce rows while
   preventing invalid measurements from being treated as valid numbers.
7. Keep FTE above valid headcount, with a warning. The source definitions do not
   establish that this is impossible, so the importer does not invent a correction.
8. RCMP/CAF lack FTE: store NULL and record one source-level informational issue
   per sheet. Missing reference abbreviations also remain NULL.
9. Publish all observations and reference updates in one transaction. Store the
   successful run and issue records in the same transaction. Any database error
   rolls everything back. Failed attempts exit nonzero and print the reason.
   They are not recorded as successful `import_runs`.

`import_issues` distinguishes informational normalization, warnings needing
review, and invalid numeric fields. A successful import can therefore contain
`error` issues at field level. It means the dataset was safely published under
these rules, not that every source value passed validation. Operators should run
`scripts/import_report.R` and resolve issues with the source owner.

## Repeat imports and revisions

When the current dataset's workbook SHA-256 matches the incoming file, publication
returns `unchanged` and creates no extra observations or run. Otherwise, the full
observation snapshot is replaced transactionally, including source deletions.
Reference IDs remain stable. Successful run metadata and issues remain available.
Validation still runs before the no-op check.

This strategy is deliberately for complete workbook snapshots. It is not an
incremental merge and would be unsafe for a partial API response. Historical
observations and old raw records are not retained after replacement, so old
published analyses cannot be recreated from the database alone. The original
workbook must be retained. Versioned observations are future work in Question 2.
To reprocess unchanged bytes after changing transformation rules, use a fresh
database. The prototype does not maintain a transformation-version migration.

## Quarterly interpretation

In [R/service.R](../R/service.R), `get_quarterly_fte()` groups by calendar quarter
and uses only that quarter's final month. `MAX(CASE ...)` selects the one eligible
value. The unique observation key prevents two values for the same month/tenure.
It is not the maximum FTE across all three months.

Quarter-end FTE is a documented assumption, selected because these records are
monthly workforce levels. Before real use, confirm whether analysts instead need
an average, fiscal quarters, or another definition. Do not silently change the
definition after clients depend on it.

See [API semantics](api.md) for absent categories, missing months and filters.
Coverage is in [import tests](../tests/testthat/test-import.R) and
[service tests](../tests/testthat/test-service.R).
