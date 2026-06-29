# Pipemind Infrastructure Setup

One-page guide to bringing the Coordination Agent stack up from scratch.

---

## Prerequisites

| Tool | Minimum version | Install |
|------|----------------|---------|
| Docker Desktop | 4.x | https://docs.docker.com/get-docker/ |
| 1Password CLI (`op`) | 2.x | https://developer.1password.com/docs/cli/get-started/ |
| Ollama | 0.2.x | https://ollama.com (needed to pull models after stack is up) |

You must be a member of the **CoordinationAgent** 1Password vault. Contact the project owner to be added.

---

## Four Steps to Bring the Stack Up

### Step 1 — Export the service account token

This is the only real secret handled outside of 1Password. Set it in your shell before running any `op run` command:

```bash
export OP_SERVICE_ACCOUNT_TOKEN="<your-1password-service-account-token>"
```

Do not put this value in `.env` or any file. Rotate it immediately if it leaks.

### Step 2 — Copy the roster template and fill it in

```bash
cp roster.example.yml roster.yml
# Edit roster.yml with real Discord snowflake IDs and Clockify user IDs.
# roster.yml is gitignored and must never be committed.
```

The stack will start without `roster.yml` present but n8n workflows will fail visibly on the roster-dependent steps. Fix it before running any workflow.

### Step 3 — Start the stack

```bash
op run --env-file=.env -- docker compose up -d
```

This resolves all `op://CoordinationAgent/...` references at runtime and injects them as environment variables. No real secrets are written to disk.

### Step 4 — Pull the Ollama model

After the stack is up, pull the model that n8n workflows will call:

```bash
docker compose exec ollama ollama pull llama3:8b
# Or whichever model is configured in your n8n workflows.
```

The model files are stored in the `ollama_models` Docker volume and persist across restarts.

---

## Verification Checklist

After `docker compose up -d`, run through these checks:

```bash
# 1. All services should show "healthy" or "running"
docker compose ps

# 2. n8n web UI should be reachable
open http://localhost:5678

# 3. Ollama API should respond
curl http://localhost:11434/api/tags

# 4. Postgres should accept connections
docker compose exec postgres pg_isready -U $POSTGRES_USER -d $POSTGRES_DB

# 5. Confirm no real secrets are in .env (must return empty output)
grep -v "^#" .env | grep -v "op://" | grep "="

# 6. Confirm roster.yml exists and is mounted
docker compose exec n8n ls /data/roster.yml
```

---

## Routine Operations

```bash
# Tail logs for a service
docker compose logs -f n8n
docker compose logs -f postgres

# Restart a single service after a config change
op run --env-file=.env -- docker compose up -d --no-deps n8n

# Stop the stack (data volumes are preserved)
docker compose down
# NEVER use: docker compose down --volumes  (destroys all persistent data)

# Apply a Postgres migration manually
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -f /migrations/<file>.sql
```

---

## Service Ports

| Service | Port | Purpose |
|---------|------|---------|
| n8n | 5678 | Workflow orchestrator web UI |
| Ollama | 11434 | Local LLM API (OpenAI-compatible) |
| Postgres | (internal only) | Not exposed to host by default |

Postgres is intentionally not exposed to the host. Connect via `docker compose exec postgres psql` for admin work.

---

## Post-Import n8n Workflow Setup

After importing the workflow JSON files into n8n (Settings → Workflows → Import), you must wire up the cross-workflow calls. Each `executeWorkflow` node uses a placeholder ID that must be replaced with the actual n8n internal workflow ID.

**How to find a workflow's ID:** Open the workflow in n8n → the URL will contain `/workflow/<id>`. Copy the numeric or UUID-format ID.

| Placeholder in JSON | Target workflow file | Appears in workflows |
|---|---|---|
| `WORKFLOW_02_ID` | `02-post-draft-sub-workflow.json` | 04a, 05a, 05b, 06 |
| `WORKFLOW_04B_ID` | `04b-client-report-deliver.json` | 03 (Branch B/D, client_report delivery) |
| `WORKFLOW_05C_ID` | `05c-client-qa-deliver.json` | 03 (Branch B/D, qa_reply delivery) |
| `WORKFLOW_06B_ID` | `06b-client-welcome-deliver.json` | 03 (Branch B/D, client_welcome delivery) |
| `WORKFLOW_04A_ID` | `04a-client-report-draft.json` | 03 (Branch A — `!report` command) |
| `WORKFLOW_06_ID` | `06-client-welcome-draft.json` | 03 (Branch H — `!welcome` command) |

**Import order:** Import in numeric order (00 → 08) so each workflow exists before the next one references it.

**After wiring:** Activate all workflows except `00-startup-validator.json` (run that manually once to validate config and load the roster).

---

## Integration Environment Variables

The following variables must be present in the `CoordinationAgent` 1Password vault before running any workflow. They are injected into the n8n container at startup via `op run`.

### GitHub

| Variable | 1Password reference | Description |
|----------|--------------------|-|
| `GITHUB_TOKEN` | `op://CoordinationAgent/github/token` | Personal access token with `repo` read scope |
| `GITHUB_REPO` | `op://CoordinationAgent/github/repo` | Repository in `owner/repo` format (e.g. `acme/myapp`) |

### Jira

| Variable | 1Password reference | Description |
|----------|--------------------|-|
| `JIRA_EMAIL` | `op://CoordinationAgent/jira/email` | Jira account email |
| `JIRA_API_TOKEN` | `op://CoordinationAgent/jira/api_token` | Jira API token |
| `JIRA_SITE_URL` | `op://CoordinationAgent/jira/site_url` | Jira site hostname (e.g. `yourorg.atlassian.net`) |
| `JIRA_PROJECT_KEY` | `op://CoordinationAgent/jira/project_key` | Jira project key (e.g. `COORD`) |

### Clockify

| Variable | 1Password reference | Description |
|----------|--------------------|-|
| `CLOCKIFY_API_KEY` | `op://CoordinationAgent/clockify/api_key` | Clockify API key |
| `CLOCKIFY_WORKSPACE_ID` | `op://CoordinationAgent/clockify/workspace_id` | Clockify workspace ID (found in workspace settings) |

---

## Roster Configuration — `client` Section

`roster.yml` must include a `client` section alongside `team` and `team_lead`. This identifies the Client's Discord user so the agent can detect their messages in the client channel and refuse to disclose project status to unrecognised users (F-02.5, F-15).

```yaml
client:
  discord_id: "REPLACE_WITH_CLIENT_DISCORD_ID"  # Discord snowflake ID — right-click user → Copy ID
  name: "Client Name"
```

The agent will fail visibly at startup if the `client` section is absent or missing `discord_id`.

---

## Security Notes

- All credentials in `.env` are `op://` references — the file is safe to commit (no real values).
- `roster.yml` is gitignored — it must never be committed (SC-19).
- Ollama is always local — never configure an external LLM endpoint (SC-11).
- Postgres data persists in the `postgres_data` volume across restarts. Back it up before destructive operations.
