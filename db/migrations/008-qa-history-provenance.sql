-- LOW: qa_history had no way to trace which workflow wrote a given row.
-- No workflow writes to qa_history yet (F-14.1 write path not wired up), so this
-- is schema-level future-proofing, not a fix for an active gap. Nullable because
-- existing rows (if any) have no known writer, and because the column has no
-- meaning until F-14.1 actually inserts into this table.

ALTER TABLE pipemind.qa_history
    ADD COLUMN IF NOT EXISTS written_by_workflow TEXT
        CHECK (
            written_by_workflow IS NULL
            OR (
                char_length(written_by_workflow) BETWEEN 1 AND 100
                AND written_by_workflow ~ '^[A-Za-z0-9\-]+$'
            )
        );
