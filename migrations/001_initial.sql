CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
INSERT OR IGNORE INTO schema_version(version) VALUES (1);
CREATE TABLE IF NOT EXISTS departments (
  dept_id INTEGER PRIMARY KEY,
  long_name_en TEXT NOT NULL UNIQUE,
  long_name_fr TEXT NOT NULL,
  short_name_en TEXT,
  short_name_fr TEXT
);
CREATE TABLE IF NOT EXISTS import_runs (
  run_id INTEGER PRIMARY KEY,
  file_name TEXT NOT NULL,
  file_sha256 TEXT NOT NULL,
  imported_at TEXT NOT NULL,
  observation_count INTEGER NOT NULL,
  issue_count INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS workforce_observations (
  dept_id INTEGER NOT NULL REFERENCES departments(dept_id),
  year INTEGER NOT NULL CHECK (year BETWEEN 1900 AND 2100),
  month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  tenure TEXT NOT NULL CHECK (tenure IN ('indeterminate','term','casual','student','missing','combined')),
  headcount INTEGER CHECK (headcount IS NULL OR (typeof(headcount) = 'integer' AND headcount >= 0)),
  fte REAL CHECK (fte IS NULL OR (typeof(fte) IN ('integer','real') AND fte >= 0)),
  source_sheet TEXT NOT NULL,
  source_row INTEGER NOT NULL CHECK (source_row >= 2),
  run_id INTEGER NOT NULL REFERENCES import_runs(run_id),
  raw_record TEXT NOT NULL,
  PRIMARY KEY (dept_id, year, month, tenure)
);
CREATE TABLE IF NOT EXISTS import_issues (
  issue_id INTEGER PRIMARY KEY,
  run_id INTEGER NOT NULL REFERENCES import_runs(run_id),
  source_sheet TEXT NOT NULL,
  source_row INTEGER,
  severity TEXT NOT NULL CHECK (severity IN ('info','warning','error')),
  code TEXT NOT NULL,
  field TEXT NOT NULL,
  raw_value TEXT,
  action TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_issues_run ON import_issues(run_id);
