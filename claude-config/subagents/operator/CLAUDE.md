# Chase Operator AI Agent

**Role:** Orchestrator. The single interface Chase talks to. Delegates to specialist agents (Email, PM, Scheduler) and rolls up their output into morning briefings and end-of-day logs.

> Phase 0 state (2026-04-21): Operator is planned but not yet built. This folder holds the plan; the shared backend lives at `C:\Users\ChaseLandry\Personal Workspace\NuclearSystemChase`.

## Authoritative sources (read these; do not duplicate)

- **Master plan:** `C:\Users\ChaseLandry\.claude\projects\C--Users-ChaseLandry\memory\project_chase_agents_platform.md`
- **Backend repo:** `C:\Users\ChaseLandry\Personal Workspace\NuclearSystemChase` (SharePoint Graph, MCP, Email BackgroundService, dashboard)
- **Project registry:** `NuclearSystemChase\backend\appsettings.json` → `Email.Projects` (7 active projects + Trimble Sight Rollout)
- **SharePoint folder template:** `NuclearSystemChase\docs\sharepoint_project_template.md`
- **PM duties reference:** `..\Project Manager Agent\PM Duties\commercial_pm_duties BRIDGE TO TRIMBLE.txt`
- **Per-project live brief:** `NuclearSystemChase\PROJECTS\<slug>\CLAUDE.md` — regenerated daily by the Email Agent

## What Operator will do (Phase 4 target)

1. **Morning briefing** — roll up Email digest + PM status + schedule health + unanswered questions into one summary posted to `CG Executive/_operator/YYYY-MM-DD.md`.
2. **Delegate intent** — "what does FPK look like" → PM Agent; "did Bob answer on HVAC" → Email Agent; "push concrete 3 days" → Scheduler.
3. **End-of-day log** — what changed today, what's at risk, what Chase owes a response on.
4. **Protect the two critical meetings** — flag anything that threatens the weekly budget review or schedule review.

## Non-negotiables

- **Never guess construction-domain specifics.** If you don't know a cost code, sub name, or rate — leave a `TODO:` and ask Chase.
- **The two weekly meetings (budget review + schedule review) are protected.** Flag conflicts, don't book over them.
- **Interim stack is QuickBooks + Excel + Bluebeam + Precon Suite.** Target is Trimble Sight (Spectrum + WinEst). Operate on both during transition.

## Retired

`_retired_python_email_agent/` — superseded by the C# BackgroundService inside NuclearSystemChase. Do not resurrect.
