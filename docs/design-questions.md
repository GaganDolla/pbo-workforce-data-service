# Design questions

The changes below are proposed extensions to the prototype.

## Question 1: Tens of millions of records

The first thing I would change is the import. It currently reads the workbook
into memory and replaces all observations in one transaction
([R/import.R](../R/import.R)). That is manageable for this file, but would become
expensive with millions of rows.

I would move to PostgreSQL and load data in batches into staging tables. Each
batch would be validated before it becomes available through the API. Recording
completed batches would let an interrupted import resume without creating
duplicates. I would also keep the original source files and rejection reports
so problems can be traced back to the input.

Imports would run separately from API requests. I would measure query times and
memory use, check that department/date filters use indexes, and load-test the
expected number of users. Date partitioning or stored quarterly summaries could
help, but I would add them only if the measurements justify the extra complexity.
Monitoring, backups and a tested restore procedure would also be needed.

## Question 2: Daily updates and historical revisions

### 1. Synchronization and data quality

I would first confirm how the source API identifies records, reports changes and
handles deletions. A daily job would fetch all pages into staging, with timeouts
and a limited number of retries that respect the provider's rate limits.

Historical revisions are the main concern. Fetching only recent reporting dates
could miss a correction to an older month. I would use the source's last-updated
timestamp or change cursor, recheck an overlapping period, and save the new
checkpoint only after the import succeeds. If the source cannot reliably report
all changes, periodic full comparisons would be necessary. A record missing from
one response would not automatically be treated as deleted.

I would reuse the existing validation rules and add checks for missing pages,
duplicate records, changed fields and unusually large changes in totals. Failed
checks would leave the current dataset available and notify the team. Only one
job would publish updates at a time.

The current importer replaces old observations, so its import log cannot reproduce
an earlier dataset. I would retain revisions and publish numbered dataset releases.
That would let analysts use current figures for new work while keeping a specific
release for an already-published analysis.

### 2. Working with analysts

I would ask analysts which scripts and reports use the service, when they refresh,
and which results must stay reproducible. We would agree how revisions should be
handled before changing the source.

During the transition, I would compare the old and new data with them and investigate
differences with the source owner. I would preserve the existing response format
and department IDs where possible, provide examples for selecting a dataset release,
and give notice of any required script changes.

For material revisions, I would share the affected departments and periods, the old
and new figures, and the reason for the change. Analysts and the people responsible
for publication should decide whether a published report needs correcting. A short
walkthrough and a named contact would help resolve problems during the transition.

### 3. Reviewing the synchronization pull request

I would review the highest-risk behaviour first:

1. **Could it publish incorrect data or expose information?** Check record matching,
   historical revisions, deletions, pagination, credentials, SQL parameters and
   logging. A failed fetch must not erase valid data or advance the checkpoint.
   These issues would block approval.
2. **Can it recover safely, and will existing analysis still work?** Look for tests
   covering interrupted requests, retries, duplicate updates, overlapping jobs and
   historical corrections. Check that previous releases remain accessible, clients
   keep working, and failures produce useful alerts. I would test these cases with
   a simulated source API.
3. **Will the team be able to maintain it?** Check batch sizes, query performance,
   separation of fetching from validation, and instructions for recovery. Minor
   style comments would be non-blocking. For required changes, I would explain the
   impact and suggest a practical fix.

## Question 3: Power BI and Python

I would add a flat export with one row per department, quarter and tenure. The
current response is easy to read, but a table is easier to load into Power BI or
pandas. It should include stable department IDs, bilingual labels, FTE, quality
flags and the dataset release. Missing values must remain different from zero.

For Python, I would provide a short example using `requests` and pandas, including
authentication, timeouts and pagination. CSV would cover simple downloads. Parquet
would be useful for larger extracts. For Power BI, I would provide a tested Power
Query example with the correct column types, credential setup and refresh steps.
Date filters and revision information would help support incremental refreshes.

Both groups would benefit from a data dictionary, API documentation, filters for
multiple departments, and a way to select a fixed dataset release. I would try
these additions with a few analysts before deciding whether a dedicated connector
is worth maintaining.
