# Project Manager Agent

**Role:** Consume Email Agent signals + SharePoint state + QuickBooks export + schedule workbook. Produce the daily `Project Update Review` per `commercial_pm_duties BRIDGE TO TRIMBLE.txt`. Maintain the 7-column budget and trend log per project. Feed the weekly budget review + schedule review meetings.

## Authoritative sources

- **PM duties spec:** `PM Duties\commercial_pm_duties BRIDGE TO TRIMBLE.txt` — this is the contract. Follow its output format exactly.
- **PM duties (earlier version):** `instructions_for_project_manager_agent.txt` — shorter; BRIDGE TO TRIMBLE supersedes.
- **Project registry:** `C:\Users\ChaseLandry\Personal Workspace\NuclearSystemChase\backend\appsettings.json` → `Email.Projects`
- **SharePoint folder template:** `C:\Users\ChaseLandry\Personal Workspace\NuclearSystemChase\docs\sharepoint_project_template.md`
- **Email signals (input):** `NuclearSystemChase\PROJECTS\<slug>\CLAUDE.md` and the Email Agent API (`GET /api/email/emails`)
- **Backend services (future home for PM logic):** `NuclearSystemChase\backend\Services\`

## Skills in this folder

- `cashflow-forecaster.skill` — cash flow projection (used by monthly executive report)
- `gantt-chart.skill` — produce Gantt views (will migrate to P6-lite in Phase 3)
- `reconciliation-check.skill` — budget reconciliation (committed vs actual vs billed)
- `site-report-skill.zip` — structured site reports
- `construction-takeoff.zip` / `Claude-CoWork_Code-Quantity-Takeoff.zip` — quantity takeoff helpers

## Phase 2 deliverables (pending)

1. **Daily Project Update Review** per project, posted to `CGC Operations Team\<Project>\_agent\YYYY-MM-DD.md`, following the exact output format in the duties spec (New Info → Budget Impact → Schedule Impact → Scope Impact → Estimating/CO Impact → Risks → Recommended Actions → Items Needing Verification).
2. **7-column budget store** (original / approved / pending / revised / committed / actual / forecast) per project, in the NuclearSystemChase backend, surfaced in the React dashboard.
3. **Vendor/sub pricing ledger** — every `pricing_received` signal from Email Agent becomes a row: project, cost code, vendor, amount, date, email link. Answers "did we ever get a price on X from Y."
4. **QuickBooks export watcher** — treat forecast as `FRESH` / `STALE (N days)` based on last export timestamp; nag in morning briefing when stale.
5. **Weekly rollups** feeding the budget review + schedule review meetings.
6. **Trend log** per project — item, date identified, status, rough estimate, final price, approval date.

## Open TODOs (from Phase 0 planning)

- **QuickBooks export cadence:** Chase to decide in practice; system tolerates variable cadence and flags staleness.
- **Scheduler v1 scope:** activity-only CPM, no resource loading. Resource loading is a later phase.
- **Trimble Sight cutover:** treat QuickBooks/Excel/Precon Suite as authoritative until formally cut over; design every workflow to run on both stacks.

## Non-negotiables (from the duties spec)

- Priorities in order: Safety → Contract compliance → Schedule & Budget → Relationships.
- Never hide an overrun by moving dollars between cost codes — document cause + recoverability.
- Pending COs stay OUT of revised budget until signed.
- Tie every recommendation to dollars, days, or contract risk.
- Call out missing info instead of guessing.
