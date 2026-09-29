# Verification record

Verified locally on September 28, 2026, using R 4.4.2 on macOS ARM64 with the
versions in `renv.lock`. No cloud deployment or Linux/Windows execution is claimed.

The full test suite was run again on September 29, 2026 and passed with the same
12 test cases and 112 assertions.

## Automated tests

`Rscript scripts/test.R` passed **12 test cases and 112 assertions**, with no test
failures or skipped tests. This includes a temporary real HTTP server, not only
direct function calls:

- Import normalization, explicit alias, duplicate reference handling and raw values.
- Missing/invalid numbers, actual zero, out-of-range dates, unknown departments,
  conflicting reference rows and duplicate observation keys.
- XLSX adapter reading every required sheet and rejecting a missing sheet.
- Same-file idempotency, stable IDs, replacement without duplicate rows, and
  rollback of both observations and reference changes on database failure.
- Quarter-end selection, decimals, absent quarter-end months, NULL versus zero,
  year/tenure filters, empty results and bilingual department names.
- SQL-injection-like inputs, foreign keys, database checks and read-only connections.
- HTTP authentication, JSON arrays including singleton/empty arrays, JSON nulls,
  response headers, repeated/unsupported parameters, 400/401/404/500 responses,
  and no database-path or API-key leakage in the checked responses/logs.

The HTTP tests require permission to open a local loopback socket.

## Provided workbook

`Rscript scripts/import.R` successfully imported:

| Dataset | Observation rows |
| --- | ---: |
| Federal Public Service | 44,408 |
| RCMP | 26 |
| CAF | 26 |
| Total | 44,460 |

There are 101 department reference records after deduplicating one identical row.
The import reports 66 issue/normalization events. Multiple events can refer to
the same source row, so this is not a count of rejected records.

| Issue | Events |
| --- | ---: |
| Invalid headcount set to NULL | 1 |
| Missing headcount | 9 |
| Missing FTE in FPS | 8 |
| FTE above valid headcount, retained with warning | 33 |
| Blank tenure mapped to missing | 1 |
| Explicit department spelling correction | 1 |
| Identical department reference duplicate | 1 |
| Whitespace normalization across source/reference fields | 10 |
| Headcount-only source sheets | 2 |

The earlier raw comparison found 34 FTE-above-headcount rows. After the invalid
negative headcount becomes NULL, 33 comparisons against valid headcounts remain.
The negative value is recorded separately as an invalid headcount.

Reimporting the unchanged workbook returned `status: unchanged`, `run_id: 1`.
SQLite `PRAGMA integrity_check` returned `ok`. `PRAGMA foreign_key_check` returned
no violations. A direct source check confirmed the 2015 Q1 student FTE for Housing,
Infrastructure and Communities Canada equals the original March FTE (approximately
8.84, retaining the source's floating-point precision).

`renv::status()` reported a consistent project. `renv::restore(prompt = FALSE)`
confirmed the local library is synchronized with the lockfile. Dependency restore
on a clean remote host and vulnerability scanning have not been performed.

The supplied workbook was not modified.
