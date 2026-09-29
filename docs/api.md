# REST API contract

Base URL for local development: `http://127.0.0.1:8000`. Both routes are GET-only
and return JSON. Query names and tenure values are case-sensitive. Unsupported
or repeated query parameters return 400. A configured API key is sent in the
`X-API-Key` header on every request. Local development without a key is restricted
by the launcher to a loopback listener.

## GET /api/departments

Returns every registered department ordered by ID. No query parameters.

```json
{
  "departments": [
    {
      "dept_id": 1,
      "dept_long": {"en": "Accessibility Standards Canada", "fr": "Normes d’accessibilité Canada"},
      "dept_short": {"en": "ASC", "fr": "NAC"}
    }
  ]
}
```

Names come from the reference sheet. Accents and punctuation are preserved.
Missing abbreviations are `null`. The array contains 101 entries for the supplied
workbook after one identical reference row is removed. IDs are local database
identifiers, not government organization codes.

## GET /api/departments/{id}/fte

| Parameter | Rules |
| --- | --- |
| `id` path | Positive integer, at most 2147483647. Unknown valid ID returns 404 |
| `year` query, optional | Single integer from 1900 to 2100. Calendar year |
| `tenure` query, optional | One of `indeterminate`, `term`, `casual`, `student`, `missing` |

Calendar quarter-end FTE: Q1 March, Q2 June, Q3 September, Q4 December. Data are
ordered by year and quarter. Values retain decimals. No display rounding is applied.

Illustrative response, not a claim about a particular source department:

```json
{
  "fte_per_quarter": [
    {"year": 2024, "quarter": 1, "indeterminate": 30.125, "term": null, "casual": null, "student": null, "missing": null}
  ]
}
```

With `?year=2024&tenure=indeterminate`, the same illustrative row is:

```json
{
  "fte_per_quarter": [
    {"year": 2024, "quarter": 1, "indeterminate": 30.125}
  ]
}
```

The tenure filter returns only that tenure's field and quarters with at least one
observation for that tenure. This avoids presenting excluded categories as zero.
Without it, all five specified tenure fields appear in every returned row.

- A quarter appears if at least one FPS observation matches the department and
  filters during that quarter. Completely unobserved quarters are omitted.
- A missing quarter-end month or missing/invalid FTE produces `null`. Earlier
  months are not carried forward. A category absent at quarter-end is also `null`.
- Reported numeric zero remains `0`. The sample requirement's `missing: 0` is not
  interpreted as permission to turn unknown data into zero.
- RCMP and CAF records have only headcount and `combined` tenure. Their FTE result
  is `{"fte_per_quarter":[]}`. `combined` is not a supported FTE filter.
- A known department with no matching data returns 200 with an empty array.
  Even a single result remains an array.

## Errors

```json
{"error":{"code":"invalid_parameter","message":"year must be a single whole number."}}
```

| Status | Meaning |
| --- | --- |
| 200 | Successful response, including empty results |
| 400 | Invalid ID/filter syntax, out-of-range values, unknown/repeated query parameters |
| 401 | Missing/incorrect API key when authentication is enabled |
| 404 | Unknown department or route |
| 500 | Unexpected failure. Generic message with no database path or stack trace |

The API sets `Cache-Control: no-store` to avoid serving a stale dataset after
replacement and `X-Content-Type-Options: nosniff`. It does not enable cross-origin
browser access or expose the workbook, import audit, database or raw records.

Implementation: [R/api.R](../R/api.R) and [R/service.R](../R/service.R).
Contract verification: [test-http.R](../tests/testthat/test-http.R).
