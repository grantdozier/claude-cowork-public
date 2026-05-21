# Chase Internal MCP — Phase 5

Read-only Microsoft Claude Code MCP server that lets every employee's Claude Code query the Chase Group audit corpus (Azure SQL `chasecowork-audit`).

## What it does

Exposes 14 tools that wrap the Phase 4B.6 operational views — open action items, risks, RFIs, submittals, invoices, pricing history, project summaries, full-text email search, and one-blob deep dives. Every query honors the access-tier filter so a super never sees `executive_only` rows, a non-HR user never sees `hr_only` rows, and superintendents are scoped to their `assigned_projects`.

## Identity

The current user is determined by env var **`CHASE_INTERNAL_USER`** (an SMTP address that matches an entry in `users.toml`). `setup.ps1` is responsible for setting this on each laptop. If unset, the server falls back to an anonymous user with no scopes — every query returns "Access denied" until the env var is populated.

## Auth

The server itself authenticates to Azure SQL via `DefaultAzureCredential` → Key Vault → `sql-admin-password`. On a developer laptop that's the user's `az login` token; in production it would be a managed identity. **No outbound traffic beyond Azure.**

## Install (manual, until setup.ps1 wires it up)

```powershell
cd "C:\Users\<you>\Chase Construction Group\Chase Group Construction - Documents\Chase Group Files\4. MISCELLANEOUS\Claude\claude-cowork\mcp-servers\chase-internal"

# Make sure Python 3.11 + pip are on PATH
pip install -r requirements.txt

# Add to your Claude Code config (~/.claude/mcp-servers.json or equivalent)
# {
#   "mcpServers": {
#     "chase-internal": {
#       "command": "python",
#       "args": ["C:\\...\\claude-cowork\\mcp-servers\\chase-internal\\server.py"],
#       "env": {
#         "CHASE_INTERNAL_USER": "chase@chasegroupcc.com"
#       }
#     }
#   }
# }
```

## Tools

| Tool | What it does |
|---|---|
| `whoami` | Show your identity + access scopes (debug) |
| `corpus_health` | One-shot dashboard: counts of emails, attachments, SP files, labels, last sync |
| `list_open_action_items` | Open actions; optional `owner` / `project` |
| `list_open_risks` | Active risks; optional `project` / `risk_type` |
| `list_unanswered_rfis` | RFIs without a recorded answer; optional `project` |
| `list_pending_submittals` | Submittals awaiting approval; optional `project` |
| `list_unpaid_invoices` | Vendor invoices + pay apps; optional `vendor` / `project` |
| `list_unfiled_documents` | Files in Unclassified/Archive folders; optional `site` |
| `recent_high_value` | Strategic docs in last N days; default 30 |
| `project_summary` | Per-project rollup (doc-type counts + risks + actions) |
| `search_emails` | Full-text on subject + preview; filter by project/sender/date |
| `get_pricing_for` | Pricing history; filter by `vendor` / `item` / `project` |
| `find_similar_question` | Find Q&A in the corpus (anti-repeat-question) |
| `get_blob_detail` | Full label + entity dump for a specific blob_id |

## Adding a new tool

1. Write the `tool_<name>(users, args) -> str` function. Return plain text.
2. Add an entry in the `TOOLS` dict with `description`, JSON schema, and the fn ref.
3. Reload Claude Code — the MCP picks up the new tool on next launch.

## Access enforcement

Done in `sql_access_clause(user, project_col, tier_col)`. Every list-style tool calls this and appends the result as a WHERE-clause fragment. The fragment:
- Always hides `access_tier = 'executive_only'` unless the user has `'all'` in scopes.
- Hides `access_tier = 'hr_only'` unless the user has `'human_resources'`.
- For supers, restricts to `assigned_projects`; emits `1=0` if empty (deny-all until projects are assigned).

For blob-level `get_blob_detail`, access is checked after the labels are fetched (cheaper than enforcing in SQL given the lookup).

## Phase 5 status

✅ Server.py committed
⏳ Smoke test (after Claude enrichment batch B finishes — needs real labeled data to query)
⏳ Wire into `claude-cowork/claude-config/mcp-servers.json`
⏳ Verify on Chase's laptop end-to-end
