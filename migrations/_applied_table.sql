-- Migration tracking table. Created once, shared by all migrations.
CREATE TABLE IF NOT EXISTS __migrations (
    version TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
