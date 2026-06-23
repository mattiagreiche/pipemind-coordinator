# Pipemind — Coordination Agent

## What This Is
An AI assistant that helps a software team and its client stay in sync: status reporting, client Q&A, standup ingestion, and time-logging help — with strict privacy and human-in-the-loop controls. Success metric is **adoption**, not tracking accuracy.

## Architecture
Workflow-driven agent orchestrated by **n8n**. The LLM reasons locally (Ollama in dev, vLLM in prod) over an OpenAI-compatible interface. Persistent state lives in **Postgres**. Secrets are resolved at runtime via **1Password CLI** — never stored in files or the repo.

Integrations (all read-only except the four permitted writes):
- **Discord** — primary interaction surface (restricted Team Lead channel, Developer DMs, Client channel)
- **Google Drive** — watched folder for standup transcripts; report delivery destination
- **Gmail** — client report delivery (write: send email)
- **GitHub / Jira** — supplementary signals at report/Q&A time only; feature-level, no individual attribution
- **Clockify** — schedule/leave data + time entry writes (human-approved only)
- **Google Calendar** — OOO cross-check for schedule determination

## Project Structure
```
specs/                          # Behavioral specs and glossary (source of truth)
  coordination-agent.md         # Full feature specs with all scenarios
  glossary.md                   # Canonical actor and term definitions
.claude/agents/                 # Claude Code subagents
CLAUDE.md                       # This file
```

## The Five Non-Negotiable Rules
1. **Help first, never punish** — every message to a person is an offer of help
2. **Help-down, aggregate-up** — individual data stays private; only aggregated, human-approved status flows up (HIGHEST PRIORITY)
3. **People are the main signal** — standup/check-ins are primary; Git/Jira/Clockify are hints only, never ground truth
4. **The agent drafts; a human approves** — no auto-send ever; no irreversible action without explicit human OK
5. **Earn trust by removing chores first** — low noise, easy to mute, transparent about what it does

## Privacy Constraints (Absolute — Never Violate)
- No productivity scores, rankings, or comparisons of individuals (SC-04)
- No contact with anyone not scheduled to work that day (SC-06); stricter source wins if Clockify/Calendar conflict
- Client-bound content: fully project-level, zero individual attribution of any kind
- Team Lead internal: anonymised work-area signals only (e.g. "one developer on auth appears blocked") — never named attribution
- Low Git activity or low logged hours alone never equal "behind" or blocker (SC-05)
- All secrets as `op://` references only; real values never touch files (SC-08)

## Approval Gate Pattern (SC-01/F-03)
Every irreversible action follows: **draft → post to Discord surface → human approves/edits/rejects → execute**.
- Client-facing drafts → restricted Team Lead Discord channel
- Individual drafts (time entries, check-in offers) → that person's Discord DM
- Drafts expire after 48 hours without action
- All delivery operations must be idempotent (no duplicate sends on retry)

## Build Phases
- **P0** (build first): client reports (F-01), client Q&A (F-02), approval gate (F-03), aggregation boundary (F-08), Team Lead interaction (F-16), Client interaction (F-15), Developer queries (F-17)
- **P1** (next): persistent memory/Postgres (F-14), standup ingestion (F-04), check-ins (F-05), time-logging helper (F-07)
- **Beyond P1**: unblock assistance (F-06)

## Key Config Values (Required at Startup)
- `DRIVE_FOLDER_ID` — report delivery destination
- `CLIENT_EMAIL` — Gmail recipient for reports
- `EOD_TIME` — end-of-day trigger for time-logging (e.g. 17:00)
- `REPORT_DAY_TIME` — weekly report schedule (e.g. Friday 17:00)
- Roster config file — authoritative list of team members + Discord identities (agent fails visibly if absent)
