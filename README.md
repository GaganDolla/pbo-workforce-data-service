# Workforce Data Service

An R backend prototype for the PBO recruitment exercise. It imports all four
worksheets of `Data/data.xlsx` into SQLite and serves the two required REST
endpoints with Plumber. There is no frontend or upload endpoint.

## Run locally

Use R **4.4.2**, the version recorded in `renv.lock`. Run commands from the
repository root, not from `R/` or `scripts/`. Internet access is needed for the
initial package restore; later imports and requests run locally.

```sh
Rscript -e 'renv::restore(prompt = FALSE)'
Rscript scripts/import.R
Rscript scripts/import_report.R
Rscript scripts/test.R
Rscript scripts/run_api.R
```

The committed `renv` bootstrap can install its pinned version if necessary.
If bootstrap installation is unavailable, install `renv` in an ordinary R
session and retry. Native package builds on Linux may require a compiler,
`libsodium-dev`, `libcurl4-openssl-dev`, and `libssl-dev`. Restore package versions
from the lockfile rather than installing whatever versions happen to be latest.

The API listens on `http://127.0.0.1:8000`. Stop it with Ctrl+C. In a second terminal:

```sh
curl 'http://127.0.0.1:8000/api/departments'
curl 'http://127.0.0.1:8000/api/departments/1/fte?year=2025'
curl 'http://127.0.0.1:8000/api/departments/1/fte?year=2025&tenure=indeterminate'
```

Look up the department ID in the first response; department 1 may have no
observations for a requested year. Empty results are valid.

In RStudio, open `PBO Job.Rproj`, restart R to activate the project library, and
run `renv::restore(prompt = FALSE)` in the Console. Then use the Terminal for the
commands above. The original exploratory script, `scripts/inspect_data.R`, is preserved;
it is not part of the importer.

## What is implemented

| Requirement | Implementation | Evidence |
| --- | --- | --- |
| Import all datasets | `read_source_workbook()`, `prepare_import()`, `publish_import()` in [R/import.R](R/import.R) | [Import tests](tests/testthat/test-import.R), [verified results](docs/verification.md) |
| Structured database | [Migration](migrations/001_initial.sql), [connection/migration functions](R/database.R) | Foreign keys, checks, primary-key uniqueness, rollback tests |
| Department endpoint | `get_departments()` in [R/service.R](R/service.R), routing in [R/api.R](R/api.R) | Bilingual response and HTTP tests |
| Quarterly FTE + filters | `get_quarterly_fte()` in [R/service.R](R/service.R) | [Service tests](tests/testthat/test-service.R), [HTTP tests](tests/testthat/test-http.R) |
| Setup and design documentation | This guide, [architecture](docs/architecture.md), [API contract](docs/api.md) | Exact runnable commands and implementation references |
| Security assessment | [Prioritized risks](docs/security.md) | Input, authorization, read-only connection and error tests |
| Written design questions | [Design responses](docs/design-questions.md) | Growth, synchronization, analyst workflows, review priorities, Power BI/Python |

## Important interpretation

The exercise does not define how monthly FTE becomes quarterly FTE. This prototype
uses **calendar quarter-end snapshots**: March, June, September and December.
It does not sum or average monthly workforce levels. Confirm this definition with
analysts before operational use; changing it requires updating the query, tests
and documented contract together.

An absent or invalid FTE is JSON `null`, not zero. A reported zero stays zero.
RCMP and CAF provide headcount only; their records are imported but their FTE
endpoint returns an empty array. See [the complete semantics](docs/api.md).

## Configuration and deployment

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `WORKFORCE_DB` | `var/workforce.sqlite` | SQLite file; API refuses to create a missing database |
| `WORKFORCE_HOST` | `127.0.0.1` | Listen address; non-loopback requires an API key |
| `WORKFORCE_PORT` | `8000` | TCP port, 1–65535 |
| `WORKFORCE_API_KEY` | unset | If set, every request requires this value in `X-API-Key`; minimum 32 bytes |

To import another copy explicitly:

```sh
Rscript scripts/import.R 'Data/data.xlsx' 'var/workforce.sqlite'
```

For a protected local demonstration, set a randomly generated API key in the
environment (or an ignored `.Renviron`), then start the API. Clients send it as
an `X-API-Key` header, never as a URL query parameter. Do not commit credentials.

For a shared deployment, restore dependencies on the target host, import the
workbook, and run `scripts/run_api.R` under a process supervisor as an unprivileged
service user. Give the importer write access and the API user read access to the
database directory. Put the service behind an HTTPS reverse proxy with request
size/rate/time limits and organizational authentication. Binding to `0.0.0.0`
requires `WORKFORCE_API_KEY`, but a shared API key alone is not staff SSO or TLS.
These infrastructure controls are deployment prerequisites, not features this
prototype claims to implement. See [security and limitations](docs/security.md).

Keep the workbook and database on local storage. SQLite uses a single writer and
a 5-second busy timeout; schedule imports away from peak activity. A transaction
publishes the full replacement atomically. Requests use a read transaction so
their queries see a consistent committed dataset. For backups, stop the processes
before copying the SQLite file, or use SQLite's online backup mechanism. Verify
restoration before relying on a backup.

## Tests and dependency maintenance

`Rscript scripts/test.R` runs validation, database, query, XLSX integration and
actual HTTP tests. HTTP tests start a temporary loopback server and clean up its
process and database. The test process must be allowed to open a local socket.
Fixtures are synthetic; the test suite does not depend on the supplied workbook.

Dependencies for both application and tests are declared in `DESCRIPTION` and
pinned in `renv.lock`. After intentionally changing dependencies, run
`renv::snapshot(prompt = FALSE)`, review the lockfile diff, and rerun tests.
The existing package versions establish reproducibility, not a claim that all
dependencies have passed a vulnerability audit.

## Scope and submission

All requested prototype features and written responses are included. Limitations
are explicit: one local SQLite writer, workbook-sized in-memory preparation,
no historical observation versions, no automated external-API synchronization,
no organization SSO, and no Power BI connector. The design questions describe
future work rather than claiming those features exist.

See [publishing and submission steps](docs/submission.md) and
[AI-use disclosure](docs/ai-use.md). Review the assumptions and make sure you can
explain and modify the code before submitting.
