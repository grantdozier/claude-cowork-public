# Chase's Email Agent

**Role:** Ingest + classify + extract signals from incoming email. Feed the PM Agent and Operator with structured output.

> The **engine** is the C# `BackgroundService` inside NuclearSystemChase, not this folder. This folder holds project-facing instruction files (per-project `agent.md`) and the handover artifacts for ongoing projects.

## Authoritative sources

- **Engine code:**
  - `NuclearSystemChase\backend\Services\EmailService.cs` — Graph fetch, classification, Anthropic summarization
  - `NuclearSystemChase\backend\Services\EmailSchedulerService.cs` — 6am daily timer + manual trigger
  - `NuclearSystemChase\backend\Controllers\EmailController.cs` — REST API: status, history, emails, run
  - `NuclearSystemChase\backend\Models\EmailModels.cs` — config and item models
- **Project registry (aliases + keywords):** `NuclearSystemChase\backend\appsettings.json` → `Email.Projects`
- **SharePoint folder template:** `NuclearSystemChase\docs\sharepoint_project_template.md`
- **Per-project live brief (agent writes this daily):** `NuclearSystemChase\PROJECTS\<slug>\CLAUDE.md`

## Mailboxes in scope (Phase 1 target)

- `derek@chasegroupcc.com` — currently the only one wired
- `chase@chasegroupcc.com` (corporate) — TODO: confirm with Chase whether in scope
- Chase's personal mailbox — target for Phase 1
- Brandon Tony — PST only; one-time historical import after IT locates the file
- Gmail Takeout archive — import into historical corpus once the .zip arrives

## Phase 1 deliverables (pending)

1. Multi-mailbox fetch (Derek + Chase-personal + Chase-corporate + historical PST/Gmail).
2. **Structured signal extractors** beyond the current priority/budget/schedule booleans:
   - `pricing_received` — sub/vendor price quote inbound
   - `rfi_raised` / `rfi_answered`
   - `submittal_action` — submittal submitted / returned / rejected
   - `schedule_impact` — stated day impact, reason
   - `co_request` — change-order-triggering event
   - `question_asked` / `question_answered` — with hash-based dedupe so "did we answer this" becomes a query, not a feeling
3. **Per-project `agent.md`** files — one per project under this folder. Template (to be filled in by Chase):
   - Aliases and keywords to expand the registry's matching
   - Naming conventions for documents in this project
   - Related SharePoint paths ("when asked X, check here, here, here")
   - Expected output format (consistency)
   - Known TODO gaps
4. FPK is the **gold example** `agent.md` — other 6 projects start from the same template with `TODO:` placeholders.

## Per-project instruction files (this folder)

- `agent.md` per project — authoritative routing and answering guidance (Phase 1)
- `FPK Handover/` — existing handover artifacts for FPK (preserved)
- `FPK_24-088_Rolling_Action_Items_v2.xlsx` — rolling action log

## Behaviors to preserve

- Never hand-edit files under `NuclearSystemChase\PROJECTS\<slug>\emails\` or `...\CLAUDE.md` or `...\email-digest.md` — they are overwritten by the agent each run. Durable project notes go into `...\notes\`.
