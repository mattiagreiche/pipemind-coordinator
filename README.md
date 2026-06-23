# Pipemind — Team & Client Coordination Agent

An assistant that helps a software team and its client stay in sync — takes the busywork out of status reporting, helps people get unblocked, and gives the client honest progress updates — without ever watching or scoring people.

---

## What it does

- **Drafts client reports** — a human approves before anything is sent
- **Answers client questions** — pulls from what it knows, or asks one quick question to the right teammate
- **Helps people get unblocked** — privately offers help when something looks stuck
- **Reads the daily standup** — uses it as the main progress signal
- **Helps log time** — drafts a Clockify timesheet at end of day; person approves before it's logged

## Stack

|               |                                                     |
| ------------- | --------------------------------------------------- |
| **n8n**       | Workflow engine — runs jobs, connects everything    |
| **Postgres**  | Memory — stores project context and recent activity |
| **Local LLM** | Brain — runs via Ollama (dev) or vLLM (prod)        |
| **1Password** | All secrets — never stored in files or the repo     |

Integrations: **Clockify · GitHub · Jira · Discord · Google** (Drive, Gmail, Calendar)

## Setup (quick version)

1. Install Docker, Docker Compose, and the [1Password CLI](https://developer.1password.com/docs/cli)
2. Create a `CoordinationAgent` vault in 1Password and a Service Account for it
3. Add credentials for each integration to the vault (see the setup brief for details)
4. Copy `.env.example` → `.env`, set `OP_SERVICE_ACCOUNT_TOKEN`, and run:

```bash
op run --env-file=.env -- docker compose up -d
```

> **Secret rule:** `.env` contains only `op://` references — never real values. If you paste a real secret into a file, you did it wrong.

## The core rules

- **Help first, never punish.** Everything the agent says is an offer of help.
- **Individual data stays individual.** Only aggregated, human-approved status reaches the lead or client.
- **The agent drafts; a human approves.** Nothing is sent automatically.
- **People are the main signal.** Git/Jira/Clockify are hints, not the truth.

## What to build first

- **Phase 0:** client report + question-answering (read-only, no nudging)
- **Phase 1:** memory layer, standup reading, time-logging helper

When in doubt: _"Does this help the person, and would they be happy knowing it runs?"_ If it feels like surveillance, stop and ask your lead.

---

## Implementation order

1. **Infrastructure** — Docker Compose, Postgres, Ollama, 1Password CLI
2. **F-03 Approval Gate** — cross-cutting foundation; every irreversible action flows through it
3. **F-08 Aggregation Boundary** — enforces privacy rules before anything reaches the lead or client
4. **F-16 Team Lead Interaction** — Discord approval channel
5. **F-01 Client Progress Report** — first end-to-end visible feature (draft → approve → deliver)
6. **F-02 Client Q&A · F-15 Client Welcome · F-17 Developer Queries**
7. **P1** — F-14 Persistent Memory, F-04 Standup Ingestion, F-05 Check-Ins, F-07 Time-Logging Helper
