# Spec: Team & Client Coordination Agent
**Source:** intern-project-brief.md.docx, intern-setup-brief.md.docx
**Epic:** N/A — single spec
**Glossary:** specs/glossary.md
**Generated:** 2026-06-19
**Status:** DRAFT — requires operator review

---

## Product Intent (non-normative)

An assistant that helps a software team and its client stay in sync: it removes status-reporting busywork, helps people get unblocked, and gives the client honest progress updates — without ever becoming a tool that watches or scores people. The single success metric is **adoption**: the team keeps it on and finds it helpful, and the client finds the reports useful. Accuracy of progress tracking is explicitly *not* the success metric.

The five governing rules (binding on every feature):
1. Help first, never punish — every message to a person is an offer of help.
2. Help-down, aggregate-up — individual data stays with the individual; only aggregated, human-approved, project-level status reaches the Lead or Client. (Highest priority.)
3. People are the main signal — standup and check-ins are primary; version control / issue tracking / time tracking are supplementary hints, never ground truth.
4. The agent drafts; a human approves — nothing reaches a person or the Client without a human OK.
5. Earn trust by removing chores first — be useful before clever; low noise, easy to mute, open about what it does.

---

## System Constraints (Non-Behavioral)

- **SC-01**: No outbound or irreversible action (email, message, time log, calendar event) may occur without passing the human approval gate. There is no auto-send path for any irreversible action.
- **SC-02**: The only permitted writes to external integrations are: logging a time entry, sending a message, sending an email, and creating a calendar event — and each is human-approved. All other integration access is read-only.
- **SC-03**: Two distinct aggregation tiers apply:
  - **Client boundary**: Content reaching the Client must be fully project-level — no individual attribution of any kind, named or anonymised. Always human-approved.
  - **Team Lead internal boundary**: Within the Team Lead's restricted Discord channel, the agent may surface anonymised work-area signals (e.g. "one developer on the auth feature has not submitted an update" or "the payments flow appears blocked") without naming the individual. Named individual attribution is still prohibited even in the internal channel.
  - Content that has crossed to the Client can never carry more detail than the Client boundary allows, regardless of the approval channel used.
- **SC-04**: The agent must never produce, store, or expose any productivity score, ranking, or comparative measure of individuals.
- **SC-05**: Low version-control activity or low logged hours must never, on their own, be classified as "behind" or as a blocker.
- **SC-06**: The agent must never initiate contact with a person who is not scheduled to work on the day in question. "Scheduled to work" is determined by consulting Clockify (assignments and time-off records) as the primary source, cross-checked against Google Calendar OOO events as a secondary source. If either source marks a person as unavailable, they are treated as not scheduled.
- **SC-06a**: If Clockify and Google Calendar conflict (e.g. Clockify shows assigned but Calendar shows OOO), the agent treats the person as not scheduled and does not initiate contact. The stricter interpretation always wins.
- **SC-07**: When primary and supplementary signals conflict, the primary signal (what the person said) prevails; supplementary signals may never override it.
- **SC-08**: Every secret/credential is referenced indirectly (e.g. a 1Password-style reference) and resolved at runtime; no real secret is ever written to a file or the repository. [Tech mandated by source.]
- **SC-09**: Each integration credential uses least-privilege scopes: read-only except for the four permitted writes in SC-02.
- **SC-10**: Standup audio, if provided, must be transcribed using an in-house/self-hosted facility so content stays in-house; no third-party transcription service. [Tech approach mandated by source.]
- **SC-11**: Language reasoning runs on a locally hosted model exposed over an OpenAI-compatible interface; no external LLM provider. [Tech mandated by source.]
- **SC-12**: The agent must be low-noise by default and provide a per-person mute that suppresses all outreach to that person. A Developer can self-mute and self-unmute by sending a recognized command to the agent in their Discord DM. The Team Lead can mute or unmute any person from the n8n UI. Mute state persists until explicitly reversed.
- **SC-13**: Any Developer or Team Lead may ask the agent in Discord to explain what it does and what data it used for a recent action. The agent must reply in the same Discord channel without requiring a separate approval step. The explanation must not expose individual-level data of a third party (it may reference what the asker's own data contributed).
- **SC-14**: Persistent memory (project picture, assignments, recent questions/outreach) is the only place individual-derived state is retained, and it remains subject to SC-03/SC-04 when surfaced. [Memory store mandated by source; Phase 1.]
- **SC-15**: If a behavior would amount to surveillance or individual scoring, it must not be built; the ambiguity is escalated to the human lead rather than resolved by the agent.
- **SC-16**: Report delivery targets (Drive folder and Client Gmail address) are required deployment-time configuration values. The spec does not hard-code them; downstream agents must surface them as required config and the system must fail visibly at startup if they are absent.
- **SC-17**: GitHub and Jira are queried as supplementary context only at the moment a report is drafted or a Client question is answered — not on a background schedule. Extraction is limited to feature-level activity hints: which features have recent activity, open/closed ticket counts by feature, and blocked or stale PRs. No individual developer attribution may be extracted from these sources for any purpose.
- **SC-18**: Scheduled-to-work status is evaluated live (on-demand) each time a feature needs it, by querying Clockify and Google Calendar at that moment. There is no daily cached snapshot; every check reflects the current state of both sources. Resilience rule: if one source is unavailable, the agent proceeds using the other source alone. If both sources are unavailable, the agent treats the person as not scheduled (fail-safe: no contact, no time-logging offer) and logs the failure for visibility.
- **SC-19**: The active team roster (who is on the team, their names, and their Discord user identities) is maintained as a configuration file in the project repository. Clockify provides schedule and leave data; Jira provides feature/ticket assignment. The roster config is the authoritative source for who the agent knows about. The agent must fail visibly if the roster config is absent or unparseable at startup.
- **SC-20**: Bot account compromise and Discord channel impersonation are out of scope for this milestone. The system relies on Discord's permission model and 1Password-secured bot credentials. This is acknowledged as a residual risk.
- **SC-21**: All outbound delivery operations (Drive save, Gmail send, Discord post, Clockify write) must be idempotent with respect to retries. A single approved action must never result in a duplicate email sent, duplicate file saved, or duplicate time entry logged, even if the operation is retried after a partial failure.

---

## Feature Specs

Phase tags reflect the source's rollout plan: **P0** = first shippable scope (read-only, drafts, no nudging); **P1** = next (memory, standup ingestion + check-ins, time logging). Out-of-scope items are listed as `WON'T`.

### F-01: Client Progress Report — Draft, Approve, Deliver | MUST | P0

**Requires:** F-03 (Approval Gate), F-08 (Aggregation Boundary)

Reports are triggered in two ways: (a) on a fixed weekly schedule — every Friday at a configurable time (deployment config), the agent drafts automatically and surfaces it to the Team Lead for approval; and (b) on-demand — the Team Lead explicitly requests a report at any time via Discord command or n8n trigger. Both paths go through the same approval gate before any delivery.

**F-01.1: Weekly scheduled report — draft, approve, deliver (happy path)**
- **GIVEN** the weekly Friday schedule fires at the configured time
- **WHEN** the agent composes a project-level progress update and the Team Lead approves it
- **THEN** the report is saved to the designated Drive folder and emailed to the Client via Gmail; the saved/sent artifact matches the approved text exactly

**F-01.2: On-demand report — triggered by Team Lead (happy path)**
- **GIVEN** the Team Lead issues a report-request command in Discord or triggers the workflow manually from n8n (per F-16)
- **WHEN** the agent composes the draft and the Team Lead approves it
- **THEN** the report is saved to Drive and emailed to the Client exactly as in F-01.1

**F-01.3: Team Lead edits before approval**
- **GIVEN** a drafted report awaiting approval
- **WHEN** the Team Lead modifies the draft and then approves
- **THEN** the edited version (not the original draft) is what is saved and sent

**F-01.4: Team Lead rejects the draft (failure)**
- **GIVEN** a drafted report awaiting approval
- **WHEN** the Team Lead rejects it
- **THEN** nothing is saved to Drive or emailed, and the rejection is recorded for the next drafting attempt

**F-01.5: Draft lapses without action (expiry)**
- **GIVEN** a drafted report awaiting approval
- **WHEN** 48 hours elapse without approval, edit, or rejection
- **THEN** the draft lapses, nothing is sent, and the Team Lead is notified so they can request a fresh draft if needed

**F-01.6: Report would expose individual-level data (privacy edge case)**
- **GIVEN** the underlying signals include individual-attributable detail
- **WHEN** the agent composes the report
- **THEN** the draft contains only aggregated, project-level statements with no named-individual attribution, per F-08

**F-01.7: Delivery channel unavailable mid-send (external dependency failure)**
- **GIVEN** an approved report
- **WHEN** the Drive save or Gmail send fails or is interrupted
- **THEN** the failure is surfaced to the Team Lead, the report is not silently dropped, and a retry does not produce a duplicate sent email or duplicate stored file 

**F-01.8: No fresh signals since last report (empty-state edge case)**
- **GIVEN** no meaningful new signals since the previous report
- **WHEN** a report is due
- **THEN** the agent states honestly that there is little new to report rather than fabricating progress 

---

### F-02: Client Question Answering | MUST | P0

**Requires:** F-03 (Approval Gate), F-08 (Aggregation Boundary)

Client questions are received and answered via Discord (the central comms channel for both team and Client). The Client asks in the designated Discord channel; the approved reply is posted back to that same channel. Reports (F-01) are delivered separately by email.

**F-02.1: Answer from existing knowledge (happy path)**
- **GIVEN** the Client posts a question in the designated Discord channel and the agent has sufficient project-level knowledge
- **WHEN** the agent composes an answer
- **THEN** a project-level answer is drafted, approved by the Team Lead, and posted back to the Client in the same Discord channel

**F-02.2: Insufficient knowledge — ask one teammate**
- **GIVEN** the Client posts a question the agent cannot answer from current knowledge
- **WHEN** the agent identifies the right teammate
- **THEN** the agent privately messages that teammate exactly one focused question on Discord (only if scheduled to work), then drafts an answer from the reply for Team Lead approval before posting back to the Client channel

**F-02.3: Teammate is not scheduled or does not respond within 2 hours (edge case)**
- **GIVEN** the needed teammate is not scheduled to work, or has not replied within 2 hours of being privately messaged (within the same working day)
- **WHEN** the agent must respond to the Client
- **THEN** the agent does not contact an unscheduled person, does not invent an answer, and the Client receives an honest "we'll follow up" holding response in Discord after Team Lead approval

**F-02.4: Answer would require exposing individual data (privacy edge case)**
- **GIVEN** the only available answer would attribute work or status to a named individual
- **WHEN** the agent drafts the reply
- **THEN** the reply is reframed to project level with no individual attribution, per F-08

**F-02.5: Wrong actor asks (authorization edge case)**
- **GIVEN** a message arrives in a monitored Discord channel from a user who is not the recognized Client identity 
- **WHEN** the agent receives it
- **THEN** the agent does not disclose project status and does not treat the message as a Client query

**F-02.6: Discord channel or bot unavailable (external dependency failure)**
- **GIVEN** the agent cannot read from or post to the Discord channel
- **WHEN** a Client question needs a reply or a reply is ready to send
- **THEN** the failure is surfaced to the Team Lead and the response is not silently dropped; no reply is attempted to an alternative channel without explicit instruction

---

### F-03: Human Approval Gate | MUST | P0

Cross-cutting control invoked by every feature that produces an outbound or irreversible action. All approval interactions happen via Discord: client-facing drafts (reports, Q&A replies) are posted to a restricted Discord channel visible only to the Team Lead; individual drafts (time entries, check-in offers) are sent to the relevant Developer via Discord DM. The Approver approves, edits, or rejects by responding in Discord.

**F-03.1: Approval precedes every irreversible action (happy path)**
- **GIVEN** any drafted outbound action (report, reply, help offer, time entry, calendar event, message)
- **WHEN** the action is ready to execute
- **THEN** the draft is posted to the appropriate Discord surface (restricted channel for Team Lead, DM for Developer); it executes only after the role-appropriate Approver explicitly approves; with no approval, no external effect occurs

**F-03.2: Correct approver and correct Discord surface by action type (authorization)**
- **GIVEN** a draft of a given type
- **WHEN** approval is sought
- **THEN** client-facing content (reports, Q&A replies) is posted to the Team Lead's restricted Discord channel; an individual's own time entry, check-in reply, or help offer is sent to that individual's Discord DM; no other actor can approve it and no other surface receives the draft

**F-03.3: Approval expires after 48 hours (edge case)**
- **GIVEN** a draft awaiting approval that is never acted upon
- **WHEN** 48 hours elapse without approval, edit, or rejection
- **THEN** the draft is not auto-approved and not auto-sent; it lapses and the appropriate Approver is notified via Discord so they can re-trigger if needed

**F-03.4: Duplicate approval / double submission (edge case)**
- **GIVEN** an already-approved-and-executed action
- **WHEN** an approval signal arrives again for the same draft
- **THEN** the action is not executed a second time

**F-03.5: Discord DM or restricted channel unavailable during approval (external dependency failure)**
- **GIVEN** the agent cannot post or read approval messages in Discord
- **WHEN** a draft is ready for approval
- **THEN** the draft is held, no irreversible action is taken, and the failure is surfaced so it can be retried once the channel is available

---

### F-04: Standup Transcript Ingestion | SHOULD | P1

**Requires:** F-14 (Persistent Memory)

The watched Drive folder accepts files from either source: a team member manually uploading a recording or transcript, or an automated export from a meeting/recording tool. The agent handles common text formats (e.g. txt, docx) and common audio formats (e.g. mp3, m4a, wav). Specific accepted formats are deployment configuration.

**F-04.1: Ingest a dropped text transcript as progress (happy path)**
- **GIVEN** a text transcript file appears in the watched folder (manually uploaded or auto-exported)
- **WHEN** the agent processes it
- **THEN** each person's spoken update is recorded as a primary progress signal in memory, used to update the project picture

**F-04.2: Audio recording supplied instead of text**
- **GIVEN** the dropped file is an audio recording
- **WHEN** the agent processes it
- **THEN** it is transcribed in-house (per SC-10) before being treated as a text transcript; the transcribed text is then processed as in F-04.1

**F-04.3: Transcript is garbled, partial, or unattributable (edge case)**
- **GIVEN** a transcript the agent cannot reliably parse or attribute to roster members
- **WHEN** the agent processes it
- **THEN** it does not fabricate attributions or progress and records only what it can reliably extract, flagging the gap 

**F-04.4: Duplicate or re-dropped transcript (edge case)**
- **GIVEN** a transcript for a day already ingested
- **WHEN** it reappears in the watched folder
- **THEN** the agent does not double-count it as new progress

**F-04.5: Unsupported file format dropped (edge case)**
- **GIVEN** a file appears in the watched folder in an unrecognized format
- **WHEN** the agent attempts to process it
- **THEN** it is skipped with a logged failure notification; the agent does not halt and does not fabricate content from an unreadable file

---

### F-05: Gentle Missing-Update Check-In | SHOULD | P1

**Requires:** F-04 (Standup Ingestion)

Check-ins are low-stakes, private, help-oriented Discord DMs directed at the individual themselves. They are not irreversible actions and do not require a separate human approval step before sending. The mute (SC-12) is the individual's opt-out control.

The absence of a transcript is treated as *unknown* (not as "standup didn't happen"). The agent fires check-ins whenever a scheduled person has not been heard from — regardless of whether a transcript was received. A transcript that was received but is missing a person's update, and a day with no transcript at all, both result in the same behavior: check in with scheduled people who haven't been heard from.

**F-05.1: Scheduled person not heard from (happy path — no transcript or missing from transcript)**
- **GIVEN** a person was scheduled to work and either no transcript arrived or the transcript contains no update from them
- **WHEN** the agent evaluates who has been heard from
- **THEN** it sends that person a single, private, help-oriented check-in via Discord (never a status demand)

**F-05.2: Person not scheduled / on leave (boundary — must not contact)**
- **GIVEN** a person with no update who was not scheduled to work (e.g. on leave or unassigned)
- **WHEN** the agent evaluates check-in
- **THEN** the agent does not contact them and does not treat the absence as a blocker or as "behind"

**F-05.3: Low activity is never a blocker (rule enforcement)**
- **GIVEN** a person submitted an update but has low commit count or low logged hours
- **WHEN** the agent evaluates their status
- **THEN** it does not classify them as behind or blocked on that basis (per SC-05)

**F-05.4: Person mutes the agent (control)**
- **GIVEN** a person has muted the agent
- **WHEN** a check-in condition is met
- **THEN** no check-in is sent to that person

**F-05.5: Schedule check partially or fully unavailable (resilience)**
- **GIVEN** Clockify or Google Calendar is unavailable when the agent needs to determine if a person is scheduled
- **WHEN** the agent evaluates check-in candidates
- **THEN** it uses whichever source is available; if both are unavailable, it treats all persons as not scheduled and sends no check-ins, logging the failure for visibility (per SC-18)

---

### F-06: Unblock Assistance | COULD | beyond Phase 1

**Requires:** F-03 (Approval Gate)

**F-06.1: Offer help when work looks stuck (happy path)**
- **GIVEN** a person's primary signal indicates their work appears stuck and they are scheduled to work
- **WHEN** the agent detects this
- **THEN** it privately offers that person help ("want help?") — framed as an offer, never an instruction or escalation

**F-06.2: Person accepts; pull in a colleague**
- **GIVEN** the person accepts the offer and a relevant colleague is identified
- **WHEN** the agent proposes looping in that colleague
- **THEN** the colleague is contacted only with approval, only if scheduled to work, and the original person's situation is shared only to the extent needed to help (no upward escalation)

**F-06.3: Person accepts; schedule a short meeting or block focus time (write action)**
- **GIVEN** the person accepts a meeting or focus-time block
- **WHEN** the agent proposes the calendar event
- **THEN** the calendar event is created only after approval and only on the calendars of consenting, scheduled participants

**F-06.4: Person declines or ignores the offer (edge case)**
- **GIVEN** an offer of help
- **WHEN** the person declines or does not respond
- **THEN** nothing is escalated upward, no one is told the person is stuck, and the agent does not repeatedly re-prompt (respecting low-noise / mute)

---

### F-07: Time-Logging Helper | SHOULD | P1

**Requires:** F-03 (Approval Gate)

End-of-day is defined as a configurable fixed time per deployment (e.g. 5 pm). At that time, the agent sends a time-entry draft via Discord DM to each person who was scheduled to work and has not yet logged time for the day.

**F-07.1: Draft an end-of-day timesheet and offer it (happy path)**
- **GIVEN** the configured EOD time arrives and a person was scheduled to work and has not yet logged time today
- **WHEN** the agent assembles the day's signals for that person
- **THEN** it drafts a probable time entry and sends it to the person's Discord DM for approval, editing, or discard via F-03

**F-07.2: Person approves the entry**
- **GIVEN** a drafted time entry
- **WHEN** the person approves it (possibly after editing) via Discord DM
- **THEN** the agent logs the approved entry to the time-tracking system on that person's behalf

**F-07.3: Person edits or discards (control)**
- **GIVEN** a drafted time entry
- **WHEN** the person edits the hours/allocation or discards it via Discord DM
- **THEN** the edited entry is logged or nothing is logged, respectively; the draft alone never logs anything

**F-07.4: Person not scheduled (boundary)**
- **GIVEN** a person who was not scheduled to work
- **WHEN** the EOD time arrives
- **THEN** no timesheet is drafted or offered to them

**F-07.5: Duplicate / already-logged day (edge case)**
- **GIVEN** time has already been logged for that person and day
- **WHEN** the EOD time arrives
- **THEN** no draft is offered; the agent surfaces the existing logged state to the person so they are aware 

**F-07.6: Clockify unavailable at EOD (external dependency failure)**
- **GIVEN** the EOD time arrives
- **WHEN** the agent cannot read existing time entries or cannot write a new one
- **THEN** the failure is surfaced to the person via Discord DM; no silent failure and no duplicate attempt when service returns

---

### F-08: Aggregation Boundary Enforcement | MUST | P0

Enforces the two-tier boundary defined in SC-03. Invoked by every upward-facing feature.

- **Tier 1 — Client boundary**: All content reaching the Client is fully project-level; no individual attribution of any kind.
- **Tier 2 — Team Lead internal boundary**: Within the restricted approval channel only, the agent may surface anonymised work-area signals; no named-individual attribution ever.

**F-08.1: Client-bound content is fully aggregated (happy path)**
- **GIVEN** content destined for the Client (report or Q&A reply)
- **WHEN** that content is assembled
- **THEN** it contains only fully project-level statements; no individual attribution (named or anonymised) appears; no commit counts, hours, or standup content attributed to any person

**F-08.2: Team Lead internal answer uses anonymised signals only (happy path)**
- **GIVEN** content surfaced to the Team Lead in the internal approval channel
- **WHEN** that content includes individual-derived context
- **THEN** the signal is presented at work-area level without naming the person (e.g. "one developer on the auth feature has not submitted an update"); no named attribution appears

**F-08.3: Aggregation cannot be defeated by small teams (edge case)**
- **GIVEN** a project small enough that anonymised signals could re-identify an individual
- **WHEN** content is assembled for any upward flow (Lead or Client)
- **THEN** the agent still does not name or attribute specifics and errs toward less detail 

**F-08.4: Lead or Client asks for named individual detail (authorization edge case)**
- **GIVEN** the Team Lead or Client explicitly asks which specific person is behind, blocked, or performing in a particular way
- **WHEN** the agent receives the request
- **THEN** the agent does not provide the named attribution; it re-states the relevant anonymised work-area signal if available, and explains that individual attribution is not surfaced

---

### F-14: Persistent Memory (Project Picture) | MUST | P1

The database-backed memory store that gives the agent continuity between runs. Referenced by F-04, F-05, F-07.

**F-14.1: Record and retrieve the project picture (happy path)**
- **GIVEN** the agent processes a signal (standup transcript, check-in, Q&A interaction)
- **WHEN** it extracts durable project-level context (feature status, open blockers, assignments, recent outreach)
- **THEN** that context is written to persistent memory and available to subsequent agent runs without re-reading raw source data

**F-14.2: Individual-derived state stays behind the aggregation boundary (privacy)**
- **GIVEN** individual-level detail exists in memory (e.g. a Developer's standup text, their recent check-in)
- **WHEN** memory is queried for content destined for the Team Lead or Client
- **THEN** only project-level aggregations are returned; raw individual data is not surfaced upward, per F-08

**F-14.3: Memory survives container/service restart (durability)**
- **GIVEN** the orchestration service restarts or is redeployed
- **WHEN** the agent next runs
- **THEN** the project picture, assignments, and recent-outreach records are intact and the agent does not treat them as lost

**F-14.4: Team member leaves the project (retention)**
- **GIVEN** a person is removed from the active team roster
- **WHEN** the agent runs subsequent jobs
- **THEN** that person's historical data is retained in memory but the agent no longer initiates outreach to them or treats them as scheduled; their records do not influence active progress signals 

**F-14.5: Memory record is stale or contradicted by a newer primary signal (consistency)**
- **GIVEN** a stored memory record about a feature's status conflicts with a fresh standup update
- **WHEN** the agent assembles the project picture
- **THEN** the newer primary signal takes precedence and the memory record is updated accordingly

**F-14.6: Day-1 bootstrapping — memory empty on first run (edge case)**
- **GIVEN** the agent has no project memory (first deployment or fresh reset) and is asked to draft a report or answer a Client question
- **WHEN** it has no standup data yet
- **THEN** it uses only the available supplementary signals (GitHub, Jira) to construct the initial project picture, explicitly states in the draft that no standup data is available yet, and drafts honestly with what it has; it does not block or error, and does not fabricate standup-derived context

---

### F-16: Team Lead Interaction Surface | MUST | P0

**Requires:** F-03 (Approval Gate)

The Team Lead interacts with the agent via two surfaces: (a) Discord commands in the restricted approval channel for day-to-day use (triggering reports, asking the agent to answer a Client question, reviewing pending drafts); and (b) the n8n workflow UI for manual workflow triggers when needed. Both surfaces produce the same downstream behavior — a draft routed through F-03.

**F-16.1: Team Lead requests an on-demand report via Discord command (happy path)**
- **GIVEN** the Team Lead types a recognized command or natural-language request in the approval channel
- **WHEN** the agent processes it
- **THEN** a report draft is created and surfaces in the same approval channel for the Team Lead to review, exactly as the weekly scheduled report would

**F-16.2: Team Lead triggers a report from n8n manually**
- **GIVEN** the Team Lead triggers the report workflow from the n8n UI
- **WHEN** the workflow runs
- **THEN** a report draft is created and posted to the Discord approval channel for review, identical behavior to F-16.1

**F-16.3: Unrecognized command in the approval channel (edge case)**
- **GIVEN** the Team Lead sends a message in the approval channel that the agent does not recognize as a known command
- **WHEN** the agent processes it
- **THEN** the agent acknowledges it cannot act on the message and suggests valid commands; it does not take any irreversible action

**F-16.4: Team Lead asks about project or feature status (internal answer)**
- **GIVEN** the Team Lead poses a question about the project or a feature area in the approval channel
- **WHEN** the agent responds
- **THEN** the answer stays within the approval channel; no separate approval step is required; the agent may include anonymised work-area signals (e.g. "one developer on the auth feature appears blocked") but must not name the individual; the answer uses the Team Lead internal boundary defined in SC-03

**F-16.5: Team Lead asks for named individual detail (boundary enforcement)**
- **GIVEN** the Team Lead explicitly asks which specific person is behind or blocked
- **WHEN** the agent receives the request
- **THEN** the agent does not name the individual and explains that individual attribution is not available in this channel; it may re-state the anonymised signal

---

### F-17: Developer Project-Status Query | SHOULD | P0

A Developer may ask the agent project-level questions in their Discord DM at any time. The agent responds with project-level context only — same rules as F-16.4 but accessible to any team member, not just the Team Lead. No approval step is required for informational replies that stay within the DM.

**F-17.1: Developer asks about a feature's status (happy path)**
- **GIVEN** a Developer sends a question about a feature or project area to the agent in their Discord DM
- **WHEN** the agent responds
- **THEN** it replies with project-level context for that area (no individual attribution about teammates); the response stays in the DM and requires no approval gate

**F-17.2: Developer asks about their own work (happy path)**
- **GIVEN** a Developer asks the agent about their own assigned features or their own status
- **WHEN** the agent responds
- **THEN** it may include relevant detail specific to that Developer's own work (since they are asking about themselves); no third-party individual data is included

**F-17.3: Developer asks who is responsible for a work area (privacy edge case)**
- **GIVEN** a Developer asks a question that would require naming another individual (e.g. "who is assigned to the payments feature?")
- **WHEN** the agent responds
- **THEN** it provides the work-area context without naming individuals, or declines to attribute if naming would expose individual data [ASSUMPTION A-12]

**F-17.4: Developer's DM is unavailable (external dependency failure)**
- **GIVEN** the agent cannot reach a Developer's Discord DM
- **WHEN** a response is needed
- **THEN** the failure is logged; no alternative channel is used without explicit instruction

---

### F-15: Client Welcome Message | SHOULD | P0

**Requires:** F-03 (Approval Gate)

When the Client is first added to the designated Discord channel, the agent sends a brief, human-approved welcome message that explains how to ask questions. This is the Client's introduction to the Q&A surface.

**F-15.1: Client joins the Discord channel — agent drafts welcome (happy path)**
- **GIVEN** the Client's Discord user is added to the designated channel for the first time
- **WHEN** the agent detects the join event
- **THEN** it drafts a short welcome message explaining how to ask questions about the project, and routes it to the Team Lead for approval via F-03 before posting

**F-15.2: Team Lead edits or rejects the welcome draft**
- **GIVEN** the welcome draft awaiting Team Lead approval
- **WHEN** the Team Lead edits it and approves, or rejects it
- **THEN** the edited version is posted (or nothing is posted on rejection); the Client never receives an unapproved message

**F-15.3: Client joins more than once (idempotency)**
- **GIVEN** a Client who has already received a welcome message and leaves and rejoins the channel
- **WHEN** the agent detects the second join
- **THEN** it does not send a duplicate welcome message

**F-15.4: Join event not detected (edge case)**
- **GIVEN** the Discord bot was offline or had insufficient permissions when the Client joined
- **WHEN** the agent comes back online
- **THEN** the missed welcome is flagged to the Team Lead so they can manually trigger one if needed

---

### F-09: Multi-Agent Orchestration | WON'T (this milestone)

Explicitly out of scope per the source. Downstream agents must not build multi-agent setups now.

### F-10: Predictive Risk Scoring / Productivity Ranking | WON'T (this milestone)

Explicitly out of scope and also forbidden by SC-04/SC-05. Never build individual scoring, ranking, or "predictive risk" features.

### F-11: Conversational Agent Shell | WON'T (this milestone)

A free-form "chat with the agent" interface is out of scope per the source.

---

## Open Questions

No blocking open questions remain. The items below are noted for future milestone planning:
- **OQ-08**: When F-06 (Unblock Assistance) is eventually built, what is the maximum number of re-offers before the agent permanently backs off for that blocker?
- **OQ-09**: Should the weekly report fire on a fixed day/time (e.g. Friday 5 pm) or at the end of the sprint cycle? Who configures the day/time?

## Resolved Questions
- **RQ-01** *(was OQ-01)*: Client-facing content is always approved by the Team Lead. → A-01 resolved.
- **RQ-02** *(was OQ-02)*: Report cadence is weekly (agent-triggered) plus on-demand (Team Lead-triggered). → F-01.1 / F-01.2.
- **RQ-03** *(was OQ-03)*: Teammate reply window is 2 hours within the same working day. → F-02.3 resolved.
- **RQ-04** *(was OQ-04)*: Unactioned drafts lapse after 48 hours. → F-03.3 / F-01.5 resolved.
- **RQ-05** *(was OQ-05)*: Client Q&A via Discord; reports via Gmail + Drive. → F-02 resolved.
- **RQ-06** *(was OQ-06)*: Unblock Assistance deferred beyond Phase 1. → F-06 COULD / beyond P1.
- **RQ-07** *(was OQ-07)*: Individual data retained on departure; agent stops treating them as active. → F-14.4 / A-11.
- **RQ-S1** *(standup presence)*: No transcript = unknown → check-ins fire for all scheduled people not heard from. → F-05.1 resolved.
- **RQ-S2** *(schedule source)*: Clockify primary + Google Calendar secondary; stricter interpretation wins on conflict. → SC-06 / SC-06a.
- **RQ-S3** *(timing params)*: Teammate reply window = 2 hours; draft expiry = 48 hours. Fixed in spec.
- **RQ-S4** *(approval surface)*: All approval interactions happen via Discord — restricted channel for Team Lead, DM for each Developer. → F-03 updated.
- **RQ-S5** *(EOD trigger)*: EOD for time-logging is a configurable fixed time per deployment (e.g. 5 pm). → F-07 updated.
- **RQ-S6** *(client setup)*: Client welcome message is in scope for P0 — agent drafts it on first join, Team Lead approves. → F-15 added.
- **RQ-S7** *(transparency)*: Any Developer or Team Lead may ask the agent in Discord to explain itself; agent replies without a separate approval step. → SC-13 updated.
- **RQ-S8** *(report delivery config)*: Drive folder and client email are required deployment config values, not spec constants. → SC-16 added.
- **RQ-S9** *(lead interaction)*: Team Lead interacts via Discord commands in the approval channel for day-to-day use, and n8n manual trigger as an alternative. → F-16 added.
- **RQ-S10** *(schedule eval)*: Scheduled-to-work is evaluated live on-demand at each query, not cached daily. → SC-18 added.
- **RQ-S11** *(supplementary signals)*: GitHub and Jira are queried only at report/Q&A time; extraction limited to feature-level activity hints with no individual attribution. → SC-17 added.
- **RQ-S12** *(transcript drop)*: Agent handles both manual and automated drops; accepts text and audio formats (deployment config). → F-04 updated; F-04.5 added.
- **RQ-S13** *(mute mechanism)*: Developer self-mutes via Discord DM command; Team Lead can mute/unmute any person from n8n. → SC-12 updated.
- **RQ-S14** *(roster source)*: Team roster is a config file in the repo (authoritative); Clockify for schedule/leave; Jira for ticket assignments. → SC-19 added.
- **RQ-S15** *(bot identity)*: Out of scope — rely on Discord permissions and 1Password-secured credentials. Acknowledged residual risk. → SC-20 added.
- **RQ-S16** *(lead vs client detail)*: Team Lead gets anonymised work-area signals internally (e.g. "one developer on auth is blocked"); Client always gets fully project-level only. Named attribution prohibited in both tiers. → SC-03 and F-08 restructured into two tiers.
- **RQ-S17** *(check-in approval)*: Check-ins do not require a separate approval step — they are not irreversible actions. Mute is the individual's opt-out. → F-05 updated; F-03 scope clarified.
- **RQ-S18** *(schedule check failure)*: If one scheduling source is unavailable, proceed with the other. If both unavailable, fail safe (no contact) and log. → SC-18 updated; F-05.5 added.
- **RQ-S19** *(report day/time)*: Weekly report fires every Friday at a configurable time (deployment config). → F-01.1 updated; OQ-09 resolved.
- **RQ-S20** *(dev can query agent)*: Developers can ask project-level status questions in their Discord DM; agent responds without approval gate. No individual data about teammates disclosed. → F-17 added.
- **RQ-S21** *(day-1 bootstrapping)*: On first run with no standup data, agent builds initial project picture from GitHub/Jira supplementary signals only, and states that standup data is not yet available. → F-14.6 added.

## Assumptions
All prior assumptions are resolved. One open item remains:
- **A-12**: When a Developer asks the agent to identify who is assigned to a work area, the agent provides work-area context without naming individuals if doing so would expose individual data. The precise boundary (e.g. whether team-lead-visible roster queries are different from developer-visible ones) is an edge case left to the implementing agent's judgment consistent with SC-03. (F-17.3)
