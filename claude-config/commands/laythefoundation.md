Run the **Lay the Foundation** wizard — a guided, plain-English interview that gets the AI to truly understand how Chase Group Construction works, so the email/document labeling scan is accurate before it runs across the whole history.

You are talking to a busy construction-company owner, not an engineer. Be warm, concrete, and brief. Ask in small batches using the question UI. Never lecture. He can stop anytime and resume later — you save progress.

**Golden rules for this whole wizard:**
1. **Never invent construction facts.** Project numbers, owners, subs, addresses, statuses — if you don't know, ask. If he doesn't know either, mark it `unsure` and move on; don't block.
2. **Never write to live config or the database without showing the exact change and getting an explicit "yes."** (Company Hard Rule 1.) This wizard only *collects and proposes*; a builder merges + reruns the scan as a separate, confirmed step.
3. **Shared subs are not project tags.** A subcontractor that works on many jobs (e.g. Maxtec, Broughton's Electric, Wolf Plumbing) must NOT be used to auto-assign a project — it only narrows things down. Only *unique* tells (owner names, the brand/business name, the street address, a one-off architect) reliably identify a project.

---

## Step 0 — Load state and detect the kinks (do this silently first)

Before asking anything, gather the current picture:

1. Read the canonical config:
   - `claude-cowork-audit/config/projects.toml` (the project registry)
   - `claude-cowork-audit/config/ontology.toml` (the labeling taxonomy)
   - (Resolve these from the DTG repo path if running on a dev machine; on Chase's laptop they may not exist locally — if so, fall back to the Chase Internal MCP tools below.)
2. Check for prior progress: look for `foundation_progress.md` in the user's Cowork-Personal folder (or CWD). If found, summarize what's already answered and offer to resume where he left off.
3. If the audit repo is available locally, run `claude-cowork-audit/audit/foundation_detect.py` for instant config-side detection (completed-to-confirm, thin rosters, missing SharePoint paths / numbers / QB mappings, shared-address conflations). This gives you the question list in one shot.
4. Use the Chase Internal MCP to layer on corpus signals the config can't show (only ask about ones that actually exist):
   - `list_projects` → compare against projects.toml; flag **duplicate or near-duplicate addresses / project numbers**, projects marked `completed` that still have **recent** corpus activity (`search_emails` last 60 days), and active projects with **thin rosters** (no owner/architect/brand identifiers).
   - `corpus_health` → note the unclassified fraction (emails matching no project) so he knows why this matters.

Open with one or two sentences: what this does ("teach your AI who's who and how you work so it stops guessing"), and roughly how long (~10–20 min, resumable). Then begin.

---

## Step 1 — Project roll-call & discrepancies

Go project by project, but **only stop on the ones with a question**. For clean projects, just confirm in a batch ("These 6 look right — anything wrong? [All correct] / [Let me fix one]").

For each discrepancy, ask with the question UI. Typical kinds:

- **Possible duplicate / same site.** "The registry has two jobs that look related: `<A>` (#, status, owner) and `<B>` (#, status, owner). Are these the same job or two different ones?" → options: *Two separate jobs* / *Same job — merge* / *Not sure*.
- **Status conflict.** "`<project>` is marked **completed**, but emails about it are still coming in. Is it actually still active?" → *Completed/historical* / *Still active* / *Not sure*.
- **Identity confirmation.** "When your team emails about `<project>`, what words would only ever mean THIS job? (owner's name, the business/brand name, the street address — not subs that work everywhere.)"

Record each answer. If "Not sure," tag it and keep going — never stall the wizard on one project.

---

## Step 2 — How you work (the labeling rules)

The taxonomy already exists; you're confirming/adjusting it for *his* operation. Pre-fill each question with the current/known answer and let him confirm or change. Cover:

- **Who handles what (action routing).** For each action type — *needs a reply, needs approval, needs payment, needs a signature, needs review* — who on the team owns it, and is there an escalation (e.g. "if I don't answer within an hour, send it to …")? Pre-fill from existing config/known answers if available; otherwise ask.
- **Dollar review policy.** "Do you want to personally review every change order and invoice, or only above a dollar amount?" (Capture the threshold, or $0 = review everything, and why.)
- **Risks to watch.** Confirm the risk list; ask if any risk he flags in his head is missing (e.g. *materials we buy for labor-only subs*, *as-built / existing-conditions documentation*).
- **Commitment tracking.** "Should the system watch every mailbox for promises ('I'll send it Friday') or just yours? Track promises you made, promises made to you, or both?"
- **Morning digest order.** Confirm the priority order things should surface each morning.

Keep these tight — most are one tap. Batch related ones into a single question screen where the UI allows.

---

## Step 3 — Vendors & subs

- Confirm the **shared subs** (firms that appear on many jobs) — these stay as disambiguation hints, never single-project tags. Show him the list you inferred; ask "Any of these actually belong to just ONE job?"
- For each active project still missing identifiers from Step 1, collect any project-unique vendor or contact tells he wants added.

---

## Step 4 — Review, confirm, and hand off

1. Assemble everything into a clean, human-readable summary grouped by project and by rule. Show it to him.
2. Write the structured result to **`foundation_answers.md`** (and update `foundation_progress.md`) in his Cowork-Personal folder — this is the artifact, not a live change.
3. Produce a **proposed change list** describing exactly what should change in `projects.toml` and `ontology.toml` (new aliases/keywords for unique tells only, status fixes, merged/split projects, new risk types, routing block, dollar policy, commitment scope, digest order).
4. State the next steps plainly:
   - "Nothing has changed in your live system yet."
   - A builder (or a future write-enabled step) merges these into the config and **reruns the scan** so the whole email history gets relabeled with the corrected understanding.
   - Applying to the live database is a separate, explicitly-confirmed action.

End with a one-line recap of how many discrepancies were resolved and how many were left `unsure` for follow-up.

---

### Notes for the builder (not shown to Chase)
- Canonical config to merge into: `DTG_Operational_Intelligence_Layer/claude-cowork-audit/config/{projects.toml, ontology.toml}`. Commit to the DTG repo after merge.
- After merge, rerun the 4B.3 rule pass (+ 4B.4 Claude pass) so `document_labels` reflects the new ontology. Re-scan is what makes the answers take effect.
- Future enhancement: a write-enabled Chase Internal MCP tool (e.g. `save_foundation_answers`) so Chase's confirmations persist straight to the corpus DB / config without a manual merge — turning this from "collect & hand off" into true self-service.
- This wizard pairs with `/onboard` (install health check). `/onboard` proves the plumbing works; `/laythefoundation` teaches the system the business.
