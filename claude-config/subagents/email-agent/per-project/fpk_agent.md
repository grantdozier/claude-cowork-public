# FPK — Email Agent instruction file

> **Gold example.** Other project agent.md files follow this shape. Some fields below were auto-filled from the handover package (`PROJECTS\fpk\CLAUDE.md` + `FPK Handover\*`) — those are marked **(verify)** and Chase should confirm before they're treated as canonical.

## 1. Identity

- **Slug:** `fpk`
- **Project number / contract #:** `24-088` (confirmed)
- **Owner / client:** **FPLJ, LLC** (confirmed by Chase 2026-04-28). Owner-side contacts: **Mitchell Rotolo** (aka Mitch Rotolo), **Jason Dulin**, **Adam Johnson**. *Earlier handover memo also referenced "KW Development / Kent" — open question whether KW Development is a separate stakeholder (e.g., developer/dev partner) or stale reference; Chase to clarify.*
- **Site address:** **6004 Johnston St, Lafayette, LA 70508** — explains "Johnston" in folder name
- **Architect:** **Ritter Maher Architects**
- **Superintendent on site:** TODO:
- **PM of record:** TODO:

## 2. Routing — what emails belong to FPK

Driven by `Email.Projects[fpk]` in `appsettings.json`. Unambiguous tells:

- **Project tells:** "FPK", "24-088", "24088", "F.P.K." — already in keywords list
- **Owner / client names:** "FPLJ", "FPLJ LLC", "Mitchell Rotolo", "Mitch Rotolo", "Rotolo", "Jason Dulin", "Dulin", "Adam Johnson". *(Adam Johnson is a high-false-positive name on its own — only auto-route when paired with another FPK tell. Same caution for "Dulin" alone.)* "KW Development" / "KW Dev" kept as legacy keyword pending Chase clarification.
- **Site address:** "6004 Johnston St", "6004 Johnston", "Johnston St", "Johnston Street", "70508"
- **Architect names:** "Ritter Maher", "Ritter Maher Architects"
- **Key sub firms (confirmed by Chase + handover):**
  - **Rite-Hite** (doors; MSA documentation status open)
  - **Curtis Equipment** (rooftop curb / penetration specs)
  - **Grizzly** (roofing — blocked on Curtis specs)
  - **Patio Center** (framing — blocked on Curtis specs)
  - **Clopay** (door pricing comparison vs Rite-Hite)
  - **Maxtec**
  - **Lambright**
  - **Chalico** (FPK-related — files in temp folder)
- **Key sub contacts (from handover):**
  - **Philip Laperouse** → Rite-Hite
  - **Dustin Davis** → Curtis Equipment
- **Brand / franchise:** n/a
- **Other keywords:** "Pay App 4", "Pay App 5", "G703", "AIA G703" — high-signal for FPK when combined with any FPK sub

Route **away from FPK** when: any other project's unambiguous tell appears AND there is no FPK tell in the same email. A single first-name reference (Kent, Philip, Dustin) alone is NOT enough — require the firm name or another FPK keyword. — PH-005

## 3. Naming conventions

From observed files in `PROJECTS\fpk\` and the Handover folder:

- **Rolling action items:** `FPK_24-088_Rolling_Action_Items_v<N>.xlsx`
- **Architect action items:** `FPK_24-088_Architect_Action_Items.xlsx`
- **Handover artifacts:** `FPK_Handover_<artifact>.<ext>`
- **Pay apps:** TODO: (infer once the first one is seen — e.g., `FPK_24-088_PayApp_04.pdf`?)
- **RFIs:** TODO:
- **Submittals:** TODO:
- **COs:** TODO:

## 4. Related SharePoint paths — "when asked X, check here"

| Ask pattern | First place | Second place |
|---|---|---|
| "what's the latest on FPK action items" | `Chase's Email Agent\FPK_24-088_Rolling_Action_Items_v2.xlsx` | `PROJECTS\fpk\CLAUDE.md` (auto-regenerated daily) |
| "pay app status" | `CGC Operations Team\FPK Project\13_Pay_Apps\` (once folder template migration lands) | owner invoices folder flagged in `PROJECTS\fpk\CLAUDE.md` |
| "door pricing (Rite-Hite vs Clopay)" | latest email from Philip Laperouse | `FPK Handover\FPK_Handover_Memo.docx` |
| "rooftop curb / penetration specs" | latest email from Dustin Davis (Curtis Equipment) | blocks Grizzly + Patio Center — flag in response |
| "Rite-Hite MSA status" | Rite-Hite subcontract folder (TODO: locate) | `PROJECTS\fpk\CLAUDE.md` risk flag |
| "what's stale in FPK SharePoint" | `Estimating/From Old File System` — legacy files flagged in handover | duplicate OneDrive FPK tree (handover flagged cleanup) |

## 5. Expected output format

1. **Direct answer.**
2. **Source** (file path + mod date OR email sender + received date).
3. **Confidence**: `confirmed` / `derived` / `guess`.
4. **Related** (1-3 adjacent items).
5. **Open question back to Chase** if needed.

## 6. Known answered questions

| Question | Answer + source | Last confirmed |
|---|---|---|
| TODO: seed first few as they come up | | |

## 7. Known blockers / hot issues (pulled from handover 2026-04-17)

1. **Pay App #4→#5 reconciliation** — AIA G703 column mismatch with Kent (KW Development). Priority.
2. **Rite-Hite / Clopay door pricing decision** — manual vs automatic; Philip Laperouse sent analysis 4/17.
3. **Rooftop curb / penetration specs** — from Curtis Equipment (Dustin Davis); blocks Grizzly roofing and Patio Center framing.
4. **Rite-Hite subcontract documentation** — Derek asked if MSA was ever issued; possible open contract risk.
5. **SharePoint stale areas** — `/Estimating/From Old File System` may be stale; duplicate OneDrive FPK tree needs cleanup; `/Owner Invoices` critical for Pay App 4→5.

## 8. FPK-specific rules for the agent

- **Pay apps must reconcile to KW's G703 before being considered final.** If a pay app number is quoted without reconciliation status, state "reconciliation unconfirmed" in the answer.
- **When a Rite-Hite / Curtis / Grizzly / Patio Center item appears, explicitly check whether it blocks another trade.** The rooftop curb issue already blocks two trades — the agent should always surface cross-trade dependencies on this job.
- TODO: anything else FPK-specific Chase wants enforced.

---

**Ledger references:** PH-001 (owner — answered 2026-04-28), PH-002 (address — answered 2026-04-28: 6004 Johnston St), PH-003 (architect — answered 2026-04-28: Ritter Maher), PH-004 (subs — answered + extended with Maxtec, Lambright, Chalico), PH-005 (keywords — answered 2026-04-28).
