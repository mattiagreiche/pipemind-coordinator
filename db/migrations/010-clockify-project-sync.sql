-- Migration 002: Clockify project sync tables and project-repo linking
-- Features: F-18 (Clockify project sync), F-19 (project-repo linking)
-- Idempotent: DDL uses IF NOT EXISTS; triggers use CREATE OR REPLACE

-- system_state table (may already exist — CREATE IF NOT EXISTS is safe)
CREATE TABLE IF NOT EXISTS pipemind.system_state (
    key        text        NOT NULL,
    value      text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT system_state_pkey PRIMARY KEY (key)
);

CREATE TABLE IF NOT EXISTS pipemind.clockify_projects (
    clockify_project_id   text        NOT NULL,
    name                  text        NOT NULL,
    client_name           text,
    is_active             boolean     NOT NULL DEFAULT true,
    first_seen_at         timestamptz NOT NULL DEFAULT now(),
    last_synced_at        timestamptz NOT NULL DEFAULT now(),
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT clockify_projects_pkey PRIMARY KEY (clockify_project_id),
    CONSTRAINT clockify_projects_name_check
        CHECK (char_length(name) >= 1 AND char_length(name) <= 200),
    CONSTRAINT clockify_projects_client_name_check
        CHECK (client_name IS NULL OR char_length(client_name) <= 200)
);

CREATE INDEX IF NOT EXISTS idx_clockify_projects_active ON pipemind.clockify_projects (is_active);

CREATE TABLE IF NOT EXISTS pipemind.project_memberships (
    membership_id         uuid        NOT NULL DEFAULT gen_random_uuid(),
    clockify_project_id   text        NOT NULL,
    clockify_user_id      text        NOT NULL,
    roster_discord_id     text,
    is_unmapped           boolean     NOT NULL DEFAULT false,
    is_active             boolean     NOT NULL DEFAULT true,
    first_seen_at         timestamptz NOT NULL DEFAULT now(),
    last_synced_at        timestamptz NOT NULL DEFAULT now(),
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT project_memberships_pkey PRIMARY KEY (membership_id),
    CONSTRAINT project_memberships_uq UNIQUE (clockify_project_id, clockify_user_id),
    CONSTRAINT project_memberships_project_fk
        FOREIGN KEY (clockify_project_id)
        REFERENCES pipemind.clockify_projects (clockify_project_id),
    CONSTRAINT project_memberships_clockify_user_id_check
        CHECK (char_length(clockify_user_id) >= 1 AND char_length(clockify_user_id) <= 100),
    CONSTRAINT project_memberships_roster_discord_id_check
        CHECK (roster_discord_id IS NULL
            OR (char_length(roster_discord_id) BETWEEN 17 AND 19
                AND roster_discord_id ~ '^\d+$'))
);

CREATE INDEX IF NOT EXISTS idx_memberships_project ON pipemind.project_memberships (clockify_project_id);
CREATE INDEX IF NOT EXISTS idx_memberships_roster ON pipemind.project_memberships (roster_discord_id)
    WHERE roster_discord_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS pipemind.project_repos (
    repo_id                 uuid        NOT NULL DEFAULT gen_random_uuid(),
    clockify_project_id     text        NOT NULL,
    repo_url                text,
    intentionally_unlinked  boolean     NOT NULL DEFAULT false,
    link_request_posted_at  timestamptz,
    linked_at               timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT project_repos_pkey PRIMARY KEY (repo_id),
    CONSTRAINT project_repos_project_fk
        FOREIGN KEY (clockify_project_id)
        REFERENCES pipemind.clockify_projects (clockify_project_id),
    CONSTRAINT project_repos_repo_url_check
        CHECK (repo_url IS NULL
            OR (char_length(repo_url) >= 5
                AND char_length(repo_url) <= 500
                AND repo_url ~ '^https?://')),
    CONSTRAINT project_repos_consistency
        CHECK (
            (intentionally_unlinked = false)
            OR (intentionally_unlinked = true AND repo_url IS NULL)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_project_repos_url
    ON pipemind.project_repos (clockify_project_id, repo_url)
    WHERE repo_url IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_project_repos_unlinked
    ON pipemind.project_repos (clockify_project_id)
    WHERE intentionally_unlinked = true;

-- touch_updated_at triggers for new tables
-- (touch_updated_at function confirmed present; pattern matches existing tables)

CREATE OR REPLACE TRIGGER trg_clockify_projects_touch
    BEFORE UPDATE ON pipemind.clockify_projects
    FOR EACH ROW EXECUTE FUNCTION pipemind.touch_updated_at();

CREATE OR REPLACE TRIGGER trg_project_memberships_touch
    BEFORE UPDATE ON pipemind.project_memberships
    FOR EACH ROW EXECUTE FUNCTION pipemind.touch_updated_at();

CREATE OR REPLACE TRIGGER trg_project_repos_touch
    BEFORE UPDATE ON pipemind.project_repos
    FOR EACH ROW EXECUTE FUNCTION pipemind.touch_updated_at();
