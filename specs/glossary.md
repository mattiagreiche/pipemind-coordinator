# Domain Glossary

Single source of truth for vocabulary across all Coordination Agent specs. When a term or actor changes, update it here.

## Actors

**Developer** *(also: Team Member, Owner)*
An individual contributor on the software team. Receives only help-oriented, private messages from the agent. Approves anything the agent proposes to do on their behalf (e.g. a time entry).
*Cannot:* be scored, ranked, or reported on as an individual; have their individual-level signals (commits, hours, ticket activity, standup content) surfaced to the Team Lead or Client; be messaged by the agent when not scheduled to work; have any action taken on their behalf without their explicit approval.

**Team Lead**
Oversees the software team and is the human accountable for client-facing communications.
*Cannot:* receive individual-level data attributed to a named developer through the agent; receive anything other than aggregated, human-approved, project-level status; cause the agent to auto-send irreversible actions without an approval step.

**Client**
The external stakeholder for whom the team is building software. Receives progress reports by email (saved to Drive) and asks questions / receives answers via Discord. The Client is identified by a recognized Discord user identity; unrecognized Discord users do not receive project status.
*Cannot:* access raw team data, individual-level data, or internal signals; receive any update that has not been human-approved; interrupt or message the team directly through the agent.

**Approver**
The human who reviews a draft and grants the OK before anything leaves the system. The Approver role resolves as follows: client-facing content (reports, Q&A replies) is always approved by the Team Lead; an individual's own time entry, check-in reply, or help offer is approved by that Developer.
*Cannot:* be bypassed, defaulted, or simulated by the agent; approve on behalf of another actor outside their role.

**Coordination Agent** *(also: the agent, the system)*
The automated assistant that drafts updates, answers questions, offers help, ingests standup transcripts, and proposes time entries. Orchestrated by the workflow engine; reasons with a locally hosted language model.
*Cannot:* send, post, email, log, or schedule anything without prior human approval; message a person who is not scheduled to work; produce or store any individual productivity score or ranking; surface individual-level data upward; write to any integration except the explicitly permitted human-approved writes (time entries, Discord/Gmail/Calendar sends).

## Key Terms

**Team roster config**
A configuration file in the project repository that lists every active team member by name and Discord identity. This is the agent's authoritative source for who it knows about. Clockify provides schedule and leave data; Jira provides feature/ticket assignments. The roster config must be kept current by the Team Lead when the team changes.

**Scheduled to work**
A determination made by querying Clockify (assignments and time-off) and Google Calendar (OOO events) live at the moment the check is needed. A person on leave, assigned away, or showing an OOO calendar event is *not* scheduled. If either source marks them unavailable, the stricter result wins. The agent never initiates contact with a person who is not scheduled to work.

**Standup transcript**
The text of the team's daily standup, supplied as a file dropped into a watched folder. If supplied as audio, it is transcribed in-house before processing. Treated as a primary progress signal.

**Progress update (individual)**
What a person reports about their own work — via standup or a direct check-in. The most trusted signal about progress.

**Primary signal vs. supplementary signal**
Primary signal = what people say (standup, check-ins). Supplementary signal = activity data from version control, issue tracking, and time tracking. Supplementary signals are hints only; they are never treated as ground truth and never on their own define whether work is "behind."

**Blocker / stuck**
A condition, inferred primarily from what a person says, that a piece of work appears unable to progress. Low commit count or low logged hours alone never constitute a blocker.

**Help-down, aggregate-up**
The governing privacy rule. Anything concerning a specific individual stays private to that individual ("help-down"). Only aggregated, human-approved, project-level status flows to the Team Lead or Client ("aggregate-up").

**Aggregation boundary**
A two-tier enforced threshold (SC-03):
- **Client boundary** — content reaching the Client must be fully project-level; no individual attribution of any kind (named or anonymised).
- **Team Lead internal boundary** — within the restricted approval channel, anonymised work-area signals are permitted (e.g. "one developer on the auth feature appears blocked"); named attribution is still prohibited.
Neither tier ever carries a productivity score, ranking, commit count, or hours figure attributed to a person.

**Draft**
A proposed artifact (a report, a reply, a help offer, a time entry, a meeting) produced by the agent and held pending human approval. A draft has no external effect until approved.

**Approval gate**
The mandatory checkpoint at which a human reviews a draft and either approves, edits, or rejects it. No outbound or irreversible action occurs before the gate is passed.

**Project-level status**
A description of how the project or a feature is progressing, expressed without attributing specifics to named individuals.

**Time entry / timesheet draft**
A proposed record of how a person's working day was likely spent, assembled from the day's signals, offered to that person to approve, edit, or discard before being logged.

**Watched folder**
A storage location the agent monitors for new inputs (e.g. standup transcripts). New files trigger processing.

**Team Lead approval channel**
A restricted Discord channel visible only to the Team Lead, where the agent posts client-facing drafts (reports, Q&A replies, Client welcome messages) for approval, editing, or rejection.

**Developer DM**
The private Discord direct-message thread between the agent and a specific Developer, used for individual approvals (time entries, check-in offers) and private check-in messages.

**Client question channel**
The Discord channel where the Client posts questions and receives approved answers. The Client is the only non-team member with access to this channel.

**Mute**
A user-controllable setting that suppresses the agent's outreach to that person. The agent must be easy to mute and low-noise by default.

**Outbound/irreversible action**
Any effect visible outside the system: sending an email, posting a message, logging time, creating a calendar event. All such actions are draft-first and human-approved. None are ever auto-sent.
