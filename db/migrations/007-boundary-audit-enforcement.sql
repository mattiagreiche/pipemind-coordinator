-- MEDIUM: boundary_audit_passed was only a column comment (CRIT-01 claimed it was
-- enforced before approval, but check_status_transition() never actually checked it).
-- Every current write path already sets it correctly before a draft can reach
-- status='approved' (F-08 audit for client-facing content_types, TRUE at insert
-- time for individual-only content_types), but nothing at the database layer
-- stopped a future workflow bug or a manual UPDATE from bypassing that.

CREATE OR REPLACE FUNCTION pipemind.check_status_transition()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status IN ('approved', 'rejected', 'expired') THEN
        RAISE EXCEPTION 'Draft % is already settled (%), cannot transition to %.',
            OLD.draft_id, OLD.status, NEW.status;
    END IF;
    -- Require discord_message_id when approving (MED-04)
    IF NEW.status = 'approved' AND NEW.discord_message_id IS NULL THEN
        RAISE EXCEPTION 'Draft % cannot be approved without a discord_message_id.',
            NEW.draft_id;
    END IF;
    -- CRIT-01: boundary_audit_passed must be TRUE before approval is accepted.
    IF NEW.status = 'approved' AND NEW.boundary_audit_passed IS NOT TRUE THEN
        RAISE EXCEPTION 'Draft % cannot be approved: boundary_audit_passed is not TRUE.',
            NEW.draft_id;
    END IF;
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;
