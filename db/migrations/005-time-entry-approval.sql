-- F-07: add 'time_entry' content_type for developer-level timesheet approvals
-- Drops and recreates the CHECK constraint to include the new value.
-- The approver_role_valid function already returns TRUE for non-client-facing types,
-- so developers can approve their own time entries (no additional function change needed).
DO $$
BEGIN
    ALTER TABLE pipemind.approval_drafts
        DROP CONSTRAINT IF EXISTS approval_drafts_content_type_check;
    ALTER TABLE pipemind.approval_drafts
        ADD CONSTRAINT approval_drafts_content_type_check
            CHECK (content_type IN ('report', 'qa_reply', 'welcome', 'time_entry'));
EXCEPTION WHEN duplicate_object THEN NULL;  -- constraint already exists with this name
       WHEN undefined_object   THEN NULL;  -- constraint did not exist (DROP IF EXISTS returned nothing)
       -- Note: other errors (permission denied, schema not found) are NOT swallowed here
END $$;
