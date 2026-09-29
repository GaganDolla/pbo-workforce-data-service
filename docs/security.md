# Security considerations and priorities

The prototype handles aggregate workforce figures, not individual employee
records. Its classification and authorized staff audience still need confirmation
before deployment. Integrity matters because incorrect figures may enter analysis.
The import operator and workbook are a separate trust boundary from API callers.

| Priority and risk | Implemented control | Remaining production work |
| --- | --- | --- |
| High: incorrect or partially published workforce data | Explicit identity/metric validation, raw source provenance, issue report, database constraints, full transaction rollback | Confirm business rules with analysts. Add review gates for unusual changes and versioned releases |
| High: unauthorized access or accidental exposure | Loopback default. Launcher blocks non-loopback without key. Optional key required on all routes. No raw-data routes | Organizational SSO/authorization, TLS, key rotation/secret store, network policy and confirmed data classification |
| High: SQL injection or unintended writes | Parameterized ID/year/tenure values. Strict validation. API SQLite connection opened read-only with `query_only`. Extension loading disabled | Separate OS service accounts and file permissions. Database roles after PostgreSQL migration |
| Medium: resource exhaustion | Bounded year/ID/filter vocabulary, small department registry, indexed queries, 25 MiB workbook and declared 200 MiB expanded-content limits, no HTTP uploads | Proxy timeouts/rate/request-size limits, monitored worker capacity, stricter parser isolation if accepting untrusted uploads |
| Medium: secrets/data leaking in failures | API returns generic 500 errors. Credentials come from environment and are not logged. `.Renviron`, DB and local libraries ignored by Git | Structured restricted-access logs with correlation IDs and retention policy. Secret scanning |
| Medium: dependency compromise or vulnerable packages | Reviewed package list, `renv.lock`, no runtime package installation inside request handlers | Scan pinned versions, assess advisories, update and retest. Reproducibility is not a vulnerability audit |
| Medium: loss of current data or inability to reproduce published figures | Original workbook, checksum, run metadata, raw values for current snapshot | Tested backups, immutable source retention, versioned observations/releases and disaster recovery |

Prioritize integrity and authorization before optimizations or cosmetic refactors:
both can directly affect confidential access or published analysis. If source data
later contain personal information, reassess logging, retention and permissions.

The shared key is a prototype control, not a multi-user identity system. Its
SHA-256 digest is compared rather than comparing a variable-length secret prefix.
This is not a claim of formally constant-time authentication. High-entropy keys,
TLS, throttling and a supported identity provider remain the production direction.
On the same machine, an unauthenticated loopback service is accessible to other
local processes: enable the key on shared machines.

File-size checks are defensive bounds for an operator-run importer. ZIP metadata
is not a guarantee against every malicious compressed file. Do not expose this
importer as an untrusted upload service without additional isolation and limits.

### Implementation and tests

- [R/import.R](../R/import.R): `read_source_workbook()`, `prepare_import()`, `publish_import()`.
- [R/database.R](../R/database.R): `connect_database()` enables foreign keys,
  disables extension loading and enforces read-only mode for API calls.
- [R/api.R](../R/api.R): `validate_listener()`, security filter and error handler.
- [R/service.R](../R/service.R): filter allowlists and bound SQL parameters.
- [test-import.R](../tests/testthat/test-import.R): malformed input and rollback.
- [test-service.R](../tests/testthat/test-service.R): injection strings, constraints and read-only access.
- [test-http.R](../tests/testthat/test-http.R): real 401/400/404/500 responses,
  JSON nulls, security headers and no key disclosure in server logs.

Tests cover these behaviours. No penetration test or external dependency security
audit is claimed.
