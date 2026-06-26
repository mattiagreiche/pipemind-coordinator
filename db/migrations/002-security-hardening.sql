-- Security hardening — apply after 001-init-pipemind-schema.sql
-- Addresses MED-1 (name Unicode lookalikes) and MED-3 (discord_id format).

-- ---------------------------------------------------------------
-- MED-1: Restrict roster.name to ASCII printable characters only.
-- The original constraint used \w which matches Unicode word chars,
-- allowing lookalike characters that could confuse identity checks.
-- ---------------------------------------------------------------
ALTER TABLE pipemind.roster
  DROP CONSTRAINT IF EXISTS roster_name_check;

ALTER TABLE pipemind.roster
  ADD CONSTRAINT roster_name_check
  CHECK (
    char_length(name) BETWEEN 1 AND 100
    AND name ~ '^[A-Za-z0-9 \-''\.]+$'
  );

-- ---------------------------------------------------------------
-- MED-3: Enforce Discord snowflake format on discord_id.
-- Snowflake IDs are 17–19 digit numeric strings.
-- The original constraint only checked length (1–32), allowing
-- arbitrary strings to be stored as "discord IDs".
-- ---------------------------------------------------------------
ALTER TABLE pipemind.roster
  DROP CONSTRAINT IF EXISTS roster_discord_id_check;

ALTER TABLE pipemind.roster
  ADD CONSTRAINT roster_discord_id_check
  CHECK (
    char_length(discord_id) BETWEEN 17 AND 19
    AND discord_id ~ '^\d+$'
  );

-- Also harden the approval_drafts approver and channel ID columns
-- (these come from roster lookups, but defense-in-depth).
ALTER TABLE pipemind.approval_drafts
  DROP CONSTRAINT IF EXISTS approval_drafts_approver_discord_id_check;

ALTER TABLE pipemind.approval_drafts
  ADD CONSTRAINT approval_drafts_approver_discord_id_check
  CHECK (char_length(approver_discord_id) BETWEEN 17 AND 19
         AND approver_discord_id ~ '^\d+$');
