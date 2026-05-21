"""Chase Internal MCP — Phase 5.

Read-only access to the Azure SQL audit corpus from each employee's
Claude Code. Enforces per-user access scopes via users.toml.

Identity: the current user is determined by env var `CHASE_INTERNAL_USER`
(an SMTP address). setup.ps1 sets this on each laptop. If unset, the
server falls back to whatever `chase@chasegroupcc.com` would see — but
NEVER exec scope unless the env var matches a known user.

Auth:
  - Azure SQL: DefaultAzureCredential → Key Vault → sql-admin-password.
  - No outbound network beyond Azure.

Stdio MCP transport (Claude Desktop / Claude Code spawns as child).

Tools exposed (Phase 5 v1):
  corpus_health            — one-shot platform dashboard
  list_open_action_items   — open actions, optionally filtered by owner/project
  list_open_risks          — risks flagged by Claude, by project / risk_type
  list_unanswered_rfis     — open RFIs by project
  list_pending_submittals  — submittals awaiting approval
  list_unpaid_invoices     — vendor invoices + pay apps
  list_unfiled_documents   — Unclassified/Archive files
  recent_high_value        — high-value docs in the last N days
  project_summary          — per-project rollup
  search_emails            — full-text search w/ filters
  get_pricing_for          — pricing history lookup
  find_similar_question    — find Q&A in the corpus
  get_blob_detail          — full label + entity dump for one blob_id
  whoami                   — debug: what scopes does this user have

Each tool returns plain-text rows that Claude can read; minimal JSON.
"""
from __future__ import annotations

import asyncio
import base64
import json
import os
import sys
import time
import tomllib
from pathlib import Path
from typing import Any, Optional

import httpx
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import pymssql
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

# CHASE_USERS_TOML env var (set by quickstart.ps1) wins; fall back to the
# standard minimal-install location so the server works without a full repo.
_fallback_users_toml = (
    Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    / "claude-cowork-audit" / "config" / "users.toml"
)
USERS_TOML = Path(os.environ.get("CHASE_USERS_TOML") or _fallback_users_toml)

KEY_VAULT  = "https://kv-chase-cowork-5f74.vault.azure.net/"
SQL_SERVER = "sql-chase-cowork-5f74.database.windows.net"
SQL_DB     = "chasecowork-audit"

# QuickBooks Online — credentials come from Key Vault secrets:
#   qb-client-id, qb-client-secret, qb-realm-id, qb-refresh-token
# Run scripts/qb_initial_auth.py once to populate the KV secrets.
QB_TOKEN_URL = "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
QB_API_BASE  = "https://quickbooks.api.intuit.com/v3/company"

DEFAULT_LIMIT = 20
MAX_LIMIT     = 200


# ============================================================================
# Identity + access scopes
# ============================================================================
def load_users() -> dict[str, dict]:
    if not USERS_TOML.exists():
        return {}
    with USERS_TOML.open("rb") as f:
        data = tomllib.load(f)
    return {u["email"].lower(): u for u in data.get("user", [])}


def current_user_email() -> str:
    return (os.environ.get("CHASE_INTERNAL_USER") or "").strip().lower()


def current_user(users: dict) -> dict:
    email = current_user_email()
    if email and email in users:
        return users[email]
    # Default: most restrictive — anonymous read-only with no scopes.
    return {"email": "anonymous", "display_name": "anonymous",
            "role": "anonymous", "access_scopes": [], "assigned_projects": []}


def user_can_see(user: dict, access_tier: Optional[str],
                 project_slug: Optional[str], mailbox_address: Optional[str]) -> bool:
    """Apply per-row access filter. Defaults to deny when uncertain."""
    scopes = set(user.get("access_scopes") or [])
    if "all" in scopes:
        return True
    if access_tier == "executive_only":
        return False                       # exec content is "all" only
    if access_tier == "hr_only":
        return "human_resources" in scopes
    if access_tier == "operations_team":
        return user.get("role") in ("pm_office", "super") or "ops_room" in scopes
    # org_wide and email content: superintendent has project-scope filter
    if user.get("role") == "super":
        assigned = set(user.get("assigned_projects") or [])
        if project_slug and project_slug in assigned:
            return True
        own = (user.get("email") or "").lower()
        if mailbox_address and mailbox_address.lower() == own:
            return True
        return False
    # pm_office / shared_inbox: chase_group_files covers most things
    if "chase_group_files" in scopes:
        return True
    if "own_mailbox" in scopes and mailbox_address and \
       mailbox_address.lower() == user.get("email", "").lower():
        return True
    return False


def sql_access_clause(user: dict, project_col: str = "project_slug",
                      tier_col: str = "access_tier") -> tuple[str, list]:
    """Return a parameterized SQL WHERE-clause fragment + params list that
    enforces the user's access at row level. Caller AND-merges into their query.
    """
    scopes = set(user.get("access_scopes") or [])
    if "all" in scopes:
        return "1=1", []

    parts: list[str] = []
    params: list = []

    # Default: hide executive_only unless user has 'all'
    parts.append(f"({tier_col} IS NULL OR {tier_col} <> 'executive_only')")

    # HR rows
    if "human_resources" not in scopes:
        parts.append(f"({tier_col} IS NULL OR {tier_col} <> 'hr_only')")

    # Supers: project-scoped
    if user.get("role") == "super":
        assigned = list(user.get("assigned_projects") or [])
        if assigned:
            ph = ",".join(["%s"] * len(assigned))
            parts.append(f"({project_col} IN ({ph}))")
            params.extend(assigned)
        else:
            # No projects assigned => sees only own mailbox content (handled
            # by the calling tool if it joins email_audit on mailbox_address).
            parts.append("1=0")
    return " AND ".join(parts), params


# ============================================================================
# SQL connection (lazy, single connection per process)
# ============================================================================
_conn: Optional[pymssql.Connection] = None


def get_conn() -> pymssql.Connection:
    global _conn
    if _conn is not None:
        return _conn
    cred = DefaultAzureCredential()
    kv = SecretClient(vault_url=KEY_VAULT, credential=cred)
    pw = kv.get_secret("sql-admin-password").value
    _conn = pymssql.connect(server=SQL_SERVER, user="coworkadmin",
                            password=pw, database=SQL_DB,
                            timeout=60, login_timeout=30)
    return _conn


def query_dicts(sql: str, params: tuple = ()) -> list[dict]:
    cur = get_conn().cursor(as_dict=True)
    cur.execute(sql, params)
    rows = cur.fetchall()
    return rows


def fmt_rows(rows: list[dict], columns: list[str], max_col_len: int = 80) -> str:
    """Plain-text table for the LLM."""
    if not rows:
        return "(no rows)"
    out = []
    out.append(" | ".join(columns))
    out.append("-" * len(out[0]))
    for r in rows:
        cells = []
        for c in columns:
            v = r.get(c)
            s = "" if v is None else str(v)
            if len(s) > max_col_len:
                s = s[: max_col_len - 1] + "…"
            cells.append(s)
        out.append(" | ".join(cells))
    return "\n".join(out)


# ============================================================================
# Tools
# ============================================================================
def tool_whoami(users: dict, args: dict) -> str:
    u = current_user(users)
    return json.dumps({
        "email": u.get("email"),
        "display_name": u.get("display_name"),
        "role": u.get("role"),
        "access_scopes": u.get("access_scopes"),
        "assigned_projects": u.get("assigned_projects", []),
    }, indent=2)


def tool_corpus_health(users: dict, args: dict) -> str:
    rows = query_dicts("SELECT * FROM v_corpus_health")
    return fmt_rows(rows, list(rows[0].keys()))


def tool_list_open_action_items(users: dict, args: dict) -> str:
    user = current_user(users)
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    where, params = sql_access_clause(user)
    extra: list[str] = []
    if args.get("owner"):
        extra.append("action_owner = %s")
        params.append(args["owner"])
    if args.get("project"):
        extra.append("project_slug = %s")
        params.append(args["project"])
    extra_sql = (" AND " + " AND ".join(extra)) if extra else ""
    rows = query_dicts(
        f"SELECT TOP {limit} action_required, action_owner, project_slug, document_type, "
        f"       LEFT(summary, 120) AS summary, blob_uri "
        f"FROM v_open_action_items "
        f"WHERE {where} {extra_sql} "
        f"ORDER BY ingested_at DESC",
        tuple(params),
    )
    return fmt_rows(rows, ["action_required", "action_owner", "project_slug",
                           "document_type", "summary", "blob_uri"], 60)


def tool_list_open_risks(users: dict, args: dict) -> str:
    user = current_user(users)
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    where, params = sql_access_clause(user)
    extra: list[str] = []
    if args.get("project"):
        extra.append("project_slug = %s")
        params.append(args["project"])
    if args.get("risk_type"):
        extra.append("risk = %s")
        params.append(args["risk_type"])
    extra_sql = (" AND " + " AND ".join(extra)) if extra else ""
    rows = query_dicts(
        f"SELECT TOP {limit} risk, action_owner, project_slug, document_type, "
        f"       LEFT(summary, 120) AS summary, blob_uri "
        f"FROM v_open_risks "
        f"WHERE {where} {extra_sql} "
        f"ORDER BY risk_confidence DESC, ingested_at DESC",
        tuple(params),
    )
    return fmt_rows(rows, ["risk", "action_owner", "project_slug",
                           "document_type", "summary", "blob_uri"], 60)


def tool_list_unanswered_rfis(users: dict, args: dict) -> str:
    user = current_user(users)
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    where, params = sql_access_clause(user)
    extra: list[str] = []
    if args.get("project"):
        extra.append("project_slug = %s")
        params.append(args["project"])
    extra_sql = (" AND " + " AND ".join(extra)) if extra else ""
    rows = query_dicts(
        f"SELECT TOP {limit} rfi_number, project_slug, action_owner, "
        f"       LEFT(summary, 120) AS summary, blob_uri "
        f"FROM v_unanswered_rfis "
        f"WHERE {where} {extra_sql} "
        f"ORDER BY ingested_at DESC",
        tuple(params),
    )
    return fmt_rows(rows, ["rfi_number", "project_slug", "action_owner",
                           "summary", "blob_uri"], 60)


def tool_list_pending_submittals(users: dict, args: dict) -> str:
    user = current_user(users)
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    where, params = sql_access_clause(user)
    extra: list[str] = []
    if args.get("project"):
        extra.append("project_slug = %s")
        params.append(args["project"])
    extra_sql = (" AND " + " AND ".join(extra)) if extra else ""
    rows = query_dicts(
        f"SELECT TOP {limit} project_slug, action_owner, "
        f"       LEFT(summary, 120) AS summary, blob_uri "
        f"FROM v_pending_submittals "
        f"WHERE {where} {extra_sql} "
        f"ORDER BY ingested_at DESC",
        tuple(params),
    )
    return fmt_rows(rows, ["project_slug", "action_owner", "summary", "blob_uri"], 60)


def tool_list_unpaid_invoices(users: dict, args: dict) -> str:
    user = current_user(users)
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    where, params = sql_access_clause(user)
    extra: list[str] = []
    if args.get("vendor"):
        extra.append("vendor LIKE %s")
        params.append(f"%{args['vendor']}%")
    if args.get("project"):
        extra.append("project_slug = %s")
        params.append(args["project"])
    extra_sql = (" AND " + " AND ".join(extra)) if extra else ""
    rows = query_dicts(
        f"SELECT TOP {limit} vendor, top_amount, invoice_number, project_slug, "
        f"       LEFT(summary, 100) AS summary, blob_uri "
        f"FROM v_unpaid_invoices "
        f"WHERE {where} {extra_sql} "
        f"ORDER BY ingested_at DESC",
        tuple(params),
    )
    return fmt_rows(rows, ["vendor", "top_amount", "invoice_number",
                           "project_slug", "summary", "blob_uri"], 50)


def tool_list_unfiled_documents(users: dict, args: dict) -> str:
    user = current_user(users)
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    where, params = sql_access_clause(user)
    extra: list[str] = []
    if args.get("site"):
        extra.append("site_key = %s")
        params.append(args["site"])
    extra_sql = (" AND " + " AND ".join(extra)) if extra else ""
    rows = query_dicts(
        f"SELECT TOP {limit} site_key, name, LEFT(parent_path, 80) AS path, "
        f"       size_bytes, modified_at, modified_by "
        f"FROM v_unfiled_documents "
        f"WHERE {where} {extra_sql} "
        f"ORDER BY modified_at DESC",
        tuple(params),
    )
    return fmt_rows(rows, ["site_key", "name", "path", "size_bytes",
                           "modified_at", "modified_by"], 60)


def tool_recent_high_value(users: dict, args: dict) -> str:
    user = current_user(users)
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    days = int(args.get("days") or 90)
    where, params = sql_access_clause(user)
    rows = query_dicts(
        f"SELECT TOP {limit} document_type, project_slug, action_owner, "
        f"       LEFT(summary, 120) AS summary, blob_uri "
        f"FROM v_recent_high_value "
        f"WHERE ingested_at >= DATEADD(day, -%s, SYSUTCDATETIME()) AND {where} "
        f"ORDER BY ingested_at DESC",
        tuple([days] + params),
    )
    return fmt_rows(rows, ["document_type", "project_slug", "action_owner",
                           "summary", "blob_uri"], 60)


def tool_project_summary(users: dict, args: dict) -> str:
    user = current_user(users)
    slug = (args.get("project") or "").strip()
    if not slug:
        return "Error: project (slug) is required."
    # Access check
    if user.get("role") == "super":
        assigned = set(user.get("assigned_projects") or [])
        if slug not in assigned:
            return "Access denied: this project is not assigned to you."
    rows = query_dicts(
        "SELECT document_type, doc_count, last_seen FROM v_project_activity "
        "WHERE project_slug = %s ORDER BY doc_count DESC",
        (slug,),
    )
    body = fmt_rows(rows, ["document_type", "doc_count", "last_seen"])

    risks = query_dicts(
        "SELECT TOP 10 risk, LEFT(summary, 100) AS summary FROM v_open_risks "
        "WHERE project_slug = %s ORDER BY risk_confidence DESC",
        (slug,),
    )
    risks_body = fmt_rows(risks, ["risk", "summary"], 60)

    actions = query_dicts(
        "SELECT TOP 10 action_required, action_owner, LEFT(summary, 100) AS summary "
        "FROM v_open_action_items WHERE project_slug = %s ORDER BY ingested_at DESC",
        (slug,),
    )
    actions_body = fmt_rows(actions, ["action_required", "action_owner", "summary"], 60)

    return (f"# {slug} — activity by document_type\n{body}\n\n"
            f"# {slug} — open risks (top 10)\n{risks_body}\n\n"
            f"# {slug} — open action items (top 10)\n{actions_body}")


def tool_search_emails(users: dict, args: dict) -> str:
    user = current_user(users)
    query = (args.get("query") or "").strip()
    if not query:
        return "Error: query is required."
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    parts = ["(subject LIKE %s OR body_preview LIKE %s)"]
    params: list = [f"%{query}%", f"%{query}%"]
    if args.get("project"):
        parts.append("project_slug = %s")
        params.append(args["project"])
    if args.get("sender"):
        parts.append("sender_address LIKE %s")
        params.append(f"%{args['sender']}%")
    if args.get("date_from"):
        parts.append("received_at >= %s")
        params.append(args["date_from"])
    if args.get("date_to"):
        parts.append("received_at <= %s")
        params.append(args["date_to"])
    # Mailbox access — supers see only their own mailbox + assigned project mail
    if user.get("role") == "super":
        assigned = list(user.get("assigned_projects") or [])
        own = (user.get("email") or "").lower()
        if assigned:
            ph = ",".join(["%s"] * len(assigned))
            parts.append(f"(project_slug IN ({ph}) OR mailbox_address = %s)")
            params.extend(assigned)
            params.append(own)
        else:
            parts.append("mailbox_address = %s")
            params.append(own)
    where = " AND ".join(parts)
    rows = query_dicts(
        f"SELECT TOP {limit} received_at, sender_address, mailbox_address, "
        f"       project_slug, LEFT(subject, 80) AS subject, "
        f"       LEFT(body_preview, 120) AS preview, internet_message_id "
        f"FROM email_audit WHERE {where} ORDER BY received_at DESC",
        tuple(params),
    )
    return fmt_rows(rows, ["received_at", "sender_address", "project_slug",
                           "subject", "preview"], 60)


def tool_get_pricing_for(users: dict, args: dict) -> str:
    user = current_user(users)
    limit = min(int(args.get("limit") or DEFAULT_LIMIT), MAX_LIMIT)
    parts: list[str] = []
    params: list = []
    if args.get("vendor"):
        parts.append("(vendor LIKE %s OR snippet LIKE %s)")
        params.extend([f"%{args['vendor']}%", f"%{args['vendor']}%"])
    if args.get("item"):
        parts.append("snippet LIKE %s")
        params.append(f"%{args['item']}%")
    if args.get("project"):
        parts.append("project_slug = %s")
        params.append(args["project"])
    if user.get("role") == "super":
        assigned = list(user.get("assigned_projects") or [])
        if assigned:
            ph = ",".join(["%s"] * len(assigned))
            parts.append(f"project_slug IN ({ph})")
            params.extend(assigned)
        else:
            parts.append("1=0")
    where = " AND ".join(parts) if parts else "1=1"
    rows = query_dicts(
        f"SELECT TOP {limit} extracted_at, vendor, amount, project_slug, "
        f"       LEFT(snippet, 160) AS snippet "
        f"FROM v_pricing_received WHERE {where} ORDER BY extracted_at DESC",
        tuple(params),
    )
    return fmt_rows(rows, ["extracted_at", "vendor", "amount",
                           "project_slug", "snippet"], 80)


def tool_find_similar_question(users: dict, args: dict) -> str:
    """Search the answered-questions index in signals for similar Q&A."""
    text = (args.get("text") or "").strip()
    if not text:
        return "Error: text is required."
    limit = min(int(args.get("limit") or 5), 20)
    rows = query_dicts(
        f"SELECT TOP {limit} type, project_slug, "
        f"       LEFT(question_text, 120) AS question, LEFT(raw_snippet, 160) AS context, "
        f"       internet_message_id "
        f"FROM signals WHERE type IN ('question_asked','question_answered','rfi_raised','rfi_answered') "
        f"  AND (question_text LIKE %s OR raw_snippet LIKE %s) "
        f"ORDER BY extracted_at DESC",
        (f"%{text}%", f"%{text}%"),
    )
    return fmt_rows(rows, ["type", "project_slug", "question", "context"], 80)


def tool_get_blob_detail(users: dict, args: dict) -> str:
    user = current_user(users)
    blob_id = (args.get("blob_id") or "").strip()
    if not blob_id:
        return "Error: blob_id is required."
    labels = query_dicts(
        "SELECT label_key, label_value, confidence, source FROM v_blob_label WHERE blob_id = %s",
        (blob_id,),
    )
    # Access check (after lookup; cheap)
    tier = next((r["label_value"] for r in labels if r["label_key"] == "access_tier"), None)
    project = next((r["label_value"] for r in labels if r["label_key"] == "project"), None)
    if not user_can_see(user, tier, project, None):
        return "Access denied for this blob."
    summary = next((r for r in query_dicts(
        "SELECT * FROM v_blob_summary WHERE blob_id = %s", (blob_id,))), {})
    entities = query_dicts(
        "SELECT entity_type, entity_value FROM document_entities WHERE blob_id = %s ORDER BY entity_type",
        (blob_id,),
    )
    out = [f"# blob {blob_id}"]
    out.append(f"source_kind: {summary.get('source_kind')}")
    out.append(f"blob_uri:    {summary.get('blob_uri')}")
    out.append(f"document_type: {summary.get('document_type')} ({summary.get('doc_type_confidence')})")
    out.append(f"project:     {summary.get('project_slug')}")
    out.append(f"access_tier: {summary.get('access_tier')}")
    out.append(f"summary:     {summary.get('summary')}")
    out.append("\n## labels")
    out.append(fmt_rows(labels, ["label_key", "label_value", "confidence", "source"]))
    out.append("\n## entities")
    out.append(fmt_rows(entities, ["entity_type", "entity_value"], 80))
    return "\n".join(out)


# ============================================================================
# QuickBooks Online connector
# ============================================================================
class QBClient:
    """Thin QB Online REST client. Credentials sourced from Key Vault.

    Required KV secrets (one-time setup via scripts/qb_initial_auth.py):
      qb-client-id      — Intuit developer app client ID
      qb-client-secret  — Intuit developer app client secret
      qb-realm-id       — QuickBooks company ID (from QB URL: /app/homepage?...companyId=XXX)
      qb-refresh-token  — long-lived refresh token (90-day sliding window)
    """
    _instance: Optional["QBClient"] = None

    def __init__(self, kv: SecretClient):
        self._kv = kv
        self._client_id: Optional[str] = None
        self._client_secret: Optional[str] = None
        self._realm_id: Optional[str] = None
        self._refresh_token: Optional[str] = None
        self._access_token: Optional[str] = None
        self._token_expiry: float = 0.0

    @classmethod
    def get(cls) -> Optional["QBClient"]:
        return cls._instance

    @classmethod
    def init(cls, kv: SecretClient) -> "QBClient":
        cls._instance = cls(kv)
        return cls._instance

    def _load_secrets(self):
        if self._client_id:
            return
        try:
            self._client_id     = self._kv.get_secret("qb-client-id").value
            self._client_secret = self._kv.get_secret("qb-client-secret").value
            self._realm_id      = self._kv.get_secret("qb-realm-id").value
            self._refresh_token = self._kv.get_secret("qb-refresh-token").value
        except Exception as e:
            raise RuntimeError(
                f"QuickBooks credentials not found in Key Vault: {e}\n"
                "Run scripts/qb_initial_auth.py to set up QB access."
            ) from e

    def _ensure_token(self):
        if self._access_token and time.time() < self._token_expiry - 60:
            return
        self._load_secrets()
        creds = base64.b64encode(
            f"{self._client_id}:{self._client_secret}".encode()
        ).decode()
        r = httpx.post(
            QB_TOKEN_URL,
            headers={"Authorization": f"Basic {creds}",
                     "Accept": "application/json",
                     "Content-Type": "application/x-www-form-urlencoded"},
            content=f"grant_type=refresh_token&refresh_token={self._refresh_token}",
            timeout=15,
        )
        r.raise_for_status()
        data = r.json()
        self._access_token = data["access_token"]
        self._token_expiry = time.time() + int(data.get("expires_in", 3600))
        # Rotate refresh token if QB issued a new one
        new_rt = data.get("refresh_token")
        if new_rt and new_rt != self._refresh_token:
            self._refresh_token = new_rt
            try:
                self._kv.set_secret("qb-refresh-token", new_rt)
            except Exception:
                pass  # best-effort; old token still valid for 100 days

    def query(self, sql: str) -> list[dict]:
        self._ensure_token()
        url = f"{QB_API_BASE}/{self._realm_id}/query"
        r = httpx.get(
            url,
            headers={"Authorization": f"Bearer {self._access_token}",
                     "Accept": "application/json"},
            params={"query": sql, "minorversion": "73"},
            timeout=20,
        )
        r.raise_for_status()
        data = r.json()
        qr = data.get("QueryResponse", {})
        # QB returns the entity type as the first key with a list value
        for v in qr.values():
            if isinstance(v, list):
                return v
        return []


def _qb_client() -> QBClient:
    c = QBClient.get()
    if c is None:
        raise RuntimeError("QBClient not initialized — call QBClient.init() first.")
    return c


def tool_qb_list_open_bills(users: dict, args: dict) -> str:
    """List QB bills with an outstanding balance (unpaid or partially paid)."""
    user = current_user(users)
    scopes = set(user.get("access_scopes") or [])
    if "all" not in scopes and "chase_group_files" not in scopes:
        return "Access denied: financial data requires pm_office or exec access."
    vendor_filter = (args.get("vendor") or "").strip()
    limit = min(int(args.get("limit") or 25), 100)
    try:
        qb = _qb_client()
        sql = f"SELECT * FROM Bill WHERE Balance > '0.0' MAXRESULTS {limit}"
        if vendor_filter:
            # QB doesn't support LIKE in IDS query; filter client-side
            bills = qb.query(f"SELECT * FROM Bill WHERE Balance > '0.0' MAXRESULTS {limit * 3}")
            bills = [b for b in bills
                     if vendor_filter.lower() in (b.get("VendorRef", {}).get("name") or "").lower()]
            bills = bills[:limit]
        else:
            bills = qb.query(sql)
        if not bills:
            return "(no open bills)"
        rows = []
        for b in bills:
            rows.append({
                "due_date":    b.get("DueDate", ""),
                "vendor":      b.get("VendorRef", {}).get("name", ""),
                "balance":     b.get("Balance", ""),
                "total":       b.get("TotalAmt", ""),
                "doc_number":  b.get("DocNumber", ""),
                "txn_date":    b.get("TxnDate", ""),
                "id":          b.get("Id", ""),
            })
        return fmt_rows(rows, ["due_date", "vendor", "balance", "total", "doc_number", "txn_date", "id"])
    except RuntimeError as e:
        return str(e)
    except Exception as e:
        return f"QB error: {type(e).__name__}: {e}"


def tool_qb_vendor_balance(users: dict, args: dict) -> str:
    """Total AP balance owed to a specific vendor across all open bills."""
    user = current_user(users)
    scopes = set(user.get("access_scopes") or [])
    if "all" not in scopes and "chase_group_files" not in scopes:
        return "Access denied: financial data requires pm_office or exec access."
    vendor_name = (args.get("vendor") or "").strip()
    if not vendor_name:
        return "Error: vendor name is required."
    try:
        qb = _qb_client()
        bills = qb.query("SELECT * FROM Bill WHERE Balance > '0.0' MAXRESULTS 500")
        matched = [b for b in bills
                   if vendor_name.lower() in (b.get("VendorRef", {}).get("name") or "").lower()]
        if not matched:
            return f"No open bills found for vendor matching '{vendor_name}'."
        total_balance = sum(float(b.get("Balance") or 0) for b in matched)
        rows = []
        for b in matched:
            rows.append({
                "due_date":   b.get("DueDate", ""),
                "vendor":     b.get("VendorRef", {}).get("name", ""),
                "balance":    b.get("Balance", ""),
                "total":      b.get("TotalAmt", ""),
                "doc_number": b.get("DocNumber", ""),
            })
        body = fmt_rows(rows, ["due_date", "vendor", "balance", "total", "doc_number"])
        return f"Total open balance for '{vendor_name}': ${total_balance:,.2f}\n\n{body}"
    except RuntimeError as e:
        return str(e)
    except Exception as e:
        return f"QB error: {type(e).__name__}: {e}"


def tool_qb_recent_payments(users: dict, args: dict) -> str:
    """Recent vendor payments (BillPayments) from QuickBooks."""
    user = current_user(users)
    scopes = set(user.get("access_scopes") or [])
    if "all" not in scopes and "chase_group_files" not in scopes:
        return "Access denied: financial data requires pm_office or exec access."
    days = int(args.get("days") or 30)
    limit = min(int(args.get("limit") or 20), 100)
    vendor_filter = (args.get("vendor") or "").strip()
    try:
        qb = _qb_client()
        from datetime import datetime, timedelta
        since = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")
        sql = f"SELECT * FROM BillPayment WHERE TxnDate >= '{since}' MAXRESULTS {limit}"
        payments = qb.query(sql)
        if vendor_filter:
            payments = [p for p in payments
                        if vendor_filter.lower() in (p.get("VendorRef", {}).get("name") or "").lower()]
        if not payments:
            return "(no payments in the requested window)"
        rows = []
        for p in payments:
            rows.append({
                "date":       p.get("TxnDate", ""),
                "vendor":     p.get("VendorRef", {}).get("name", ""),
                "amount":     p.get("TotalAmt", ""),
                "check_num":  p.get("CheckPayment", {}).get("PrintStatus", "") if p.get("CheckPayment") else p.get("CreditCardPayment", {}).get("CCAccountRef", {}).get("name", ""),
                "doc_number": p.get("DocNumber", ""),
                "id":         p.get("Id", ""),
            })
        return fmt_rows(rows, ["date", "vendor", "amount", "check_num", "doc_number", "id"])
    except RuntimeError as e:
        return str(e)
    except Exception as e:
        return f"QB error: {type(e).__name__}: {e}"


def tool_qb_job_cost_summary(users: dict, args: dict) -> str:
    """Job cost summary by QB Customer/Project. Requires QB Projects feature.
    Returns total billed and paid amounts grouped by QB Customer (project).
    """
    user = current_user(users)
    scopes = set(user.get("access_scopes") or [])
    if "all" not in scopes and "chase_group_files" not in scopes:
        return "Access denied: financial data requires pm_office or exec access."
    project_filter = (args.get("project") or "").strip()
    limit = min(int(args.get("limit") or 30), 100)
    try:
        qb = _qb_client()
        # Pull open bills grouped by customer ref (project)
        bills = qb.query("SELECT * FROM Bill WHERE Balance > '0.0' MAXRESULTS 500")
        # Group by customer/project name
        from collections import defaultdict
        by_project: dict[str, dict] = defaultdict(lambda: {"open_balance": 0.0, "bill_count": 0})
        for b in bills:
            lines = b.get("Line", [])
            for line in lines:
                detail = line.get("AccountBasedExpenseLineDetail") or line.get("ItemBasedExpenseLineDetail") or {}
                cref = detail.get("CustomerRef", {})
                proj = cref.get("name") or "(no project)"
                if project_filter and project_filter.lower() not in proj.lower():
                    continue
                by_project[proj]["open_balance"] += float(line.get("Amount") or 0)
                by_project[proj]["bill_count"] += 1
        if not by_project:
            msg = f"for project '{project_filter}'" if project_filter else "(no open bills with project assignment)"
            return f"No job cost data found {msg}."
        rows = sorted(
            [{"project": k, "open_ap": f"${v['open_balance']:,.2f}", "bill_lines": v["bill_count"]}
             for k, v in by_project.items()],
            key=lambda r: -float(r["open_ap"].replace("$", "").replace(",", ""))
        )[:limit]
        return fmt_rows(rows, ["project", "open_ap", "bill_lines"])
    except RuntimeError as e:
        return str(e)
    except Exception as e:
        return f"QB error: {type(e).__name__}: {e}"


# ============================================================================
# MCP server wiring
# ============================================================================
TOOLS: dict[str, dict] = {
    "whoami": {
        "description": "Show the current user's identity and access scopes (debug helper).",
        "schema": {"type": "object", "properties": {}},
        "fn": tool_whoami,
    },
    "corpus_health": {
        "description": "One-shot platform dashboard: counts of emails, attachments, SP files, labels, entities, last sync.",
        "schema": {"type": "object", "properties": {}},
        "fn": tool_corpus_health,
    },
    "list_open_action_items": {
        "description": "List items demanding action. Filter by owner (chase, alex, shawnee, kaylin, mike-daly, john-white, unassigned) and/or project (slug).",
        "schema": {"type": "object", "properties": {
            "owner": {"type": "string"},
            "project": {"type": "string"},
            "limit": {"type": "integer", "default": 20},
        }},
        "fn": tool_list_open_action_items,
    },
    "list_open_risks": {
        "description": "List active risks (legal_exposure, payment_overdue, scope_gap, co_unsigned, etc.). Filter by project and/or risk_type.",
        "schema": {"type": "object", "properties": {
            "project": {"type": "string"},
            "risk_type": {"type": "string"},
            "limit": {"type": "integer", "default": 20},
        }},
        "fn": tool_list_open_risks,
    },
    "list_unanswered_rfis": {
        "description": "RFIs raised that don't have a recorded answer yet. Optional project filter.",
        "schema": {"type": "object", "properties": {
            "project": {"type": "string"},
            "limit": {"type": "integer", "default": 20},
        }},
        "fn": tool_list_unanswered_rfis,
    },
    "list_pending_submittals": {
        "description": "Submittals awaiting approval. Optional project filter.",
        "schema": {"type": "object", "properties": {
            "project": {"type": "string"},
            "limit": {"type": "integer", "default": 20},
        }},
        "fn": tool_list_pending_submittals,
    },
    "list_unpaid_invoices": {
        "description": "Vendor invoices + pay applications. Filter by vendor and/or project.",
        "schema": {"type": "object", "properties": {
            "vendor": {"type": "string"},
            "project": {"type": "string"},
            "limit": {"type": "integer", "default": 20},
        }},
        "fn": tool_list_unpaid_invoices,
    },
    "list_unfiled_documents": {
        "description": "SharePoint files in Unclassified/Archive/Old-Versions folders (the filing-debt list). Filter by site (main|exec|ops).",
        "schema": {"type": "object", "properties": {
            "site": {"type": "string"},
            "limit": {"type": "integer", "default": 20},
        }},
        "fn": tool_list_unfiled_documents,
    },
    "recent_high_value": {
        "description": "Strategic documents (operating agreements, contracts, signed COs, disputes, WIP reports, etc.) in the last N days.",
        "schema": {"type": "object", "properties": {
            "days": {"type": "integer", "default": 30},
            "limit": {"type": "integer", "default": 20},
        }},
        "fn": tool_recent_high_value,
    },
    "project_summary": {
        "description": "Per-project rollup: document counts by type, top open risks, top open action items.",
        "schema": {"type": "object", "properties": {
            "project": {"type": "string", "description": "Project slug (fpk, smash, caddy-shack, 800-e-farrel, etc.)"},
        }, "required": ["project"]},
        "fn": tool_project_summary,
    },
    "search_emails": {
        "description": "Full-text search over email subject + body_preview. Filter by project, sender, date range.",
        "schema": {"type": "object", "properties": {
            "query":     {"type": "string"},
            "project":   {"type": "string"},
            "sender":    {"type": "string"},
            "date_from": {"type": "string", "description": "YYYY-MM-DD"},
            "date_to":   {"type": "string", "description": "YYYY-MM-DD"},
            "limit":     {"type": "integer", "default": 20},
        }, "required": ["query"]},
        "fn": tool_search_emails,
    },
    "get_pricing_for": {
        "description": "Pricing history from vendors. Filter by vendor (string match), item (keyword), and/or project.",
        "schema": {"type": "object", "properties": {
            "vendor":  {"type": "string"},
            "item":    {"type": "string"},
            "project": {"type": "string"},
            "limit":   {"type": "integer", "default": 20},
        }},
        "fn": tool_get_pricing_for,
    },
    "find_similar_question": {
        "description": "Find emails where a similar question was asked or answered (lifts repeat-question burden).",
        "schema": {"type": "object", "properties": {
            "text":  {"type": "string"},
            "limit": {"type": "integer", "default": 5},
        }, "required": ["text"]},
        "fn": tool_find_similar_question,
    },
    "get_blob_detail": {
        "description": "Full label + entity dump for a specific blob_id (the UUID returned by other tools).",
        "schema": {"type": "object", "properties": {
            "blob_id": {"type": "string"},
        }, "required": ["blob_id"]},
        "fn": tool_get_blob_detail,
    },
    "qb_list_open_bills": {
        "description": "QuickBooks: list vendor bills with an outstanding balance. Filter by vendor name.",
        "schema": {"type": "object", "properties": {
            "vendor": {"type": "string", "description": "Partial vendor name match"},
            "limit":  {"type": "integer", "default": 25},
        }},
        "fn": tool_qb_list_open_bills,
    },
    "qb_vendor_balance": {
        "description": "QuickBooks: total AP balance owed to a vendor across all open bills.",
        "schema": {"type": "object", "properties": {
            "vendor": {"type": "string"},
        }, "required": ["vendor"]},
        "fn": tool_qb_vendor_balance,
    },
    "qb_recent_payments": {
        "description": "QuickBooks: recent vendor payments (checks + ACH) in the last N days.",
        "schema": {"type": "object", "properties": {
            "days":   {"type": "integer", "default": 30},
            "vendor": {"type": "string", "description": "Optional vendor filter"},
            "limit":  {"type": "integer", "default": 20},
        }},
        "fn": tool_qb_recent_payments,
    },
    "qb_job_cost_summary": {
        "description": "QuickBooks: open AP balance grouped by project/customer. Shows which projects have outstanding sub/vendor bills.",
        "schema": {"type": "object", "properties": {
            "project": {"type": "string", "description": "Optional project name filter"},
            "limit":   {"type": "integer", "default": 30},
        }},
        "fn": tool_qb_job_cost_summary,
    },
}


async def main():
    users = load_users()
    # QB: init client (credentials are lazy-loaded on first use)
    try:
        cred = DefaultAzureCredential()
        kv = SecretClient(vault_url=KEY_VAULT, credential=cred)
        QBClient.init(kv)
    except Exception:
        pass  # QB tools will return a clear error if KV is unreachable
    server: Server = Server("chase-internal")

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [Tool(name=n, description=t["description"], inputSchema=t["schema"])
                for n, t in TOOLS.items()]

    @server.call_tool()
    async def call_tool(name: str, args: dict[str, Any]) -> list[TextContent]:
        tool = TOOLS.get(name)
        if not tool:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]
        try:
            out = tool["fn"](users, args or {})
        except Exception as e:
            out = f"Error in {name}: {type(e).__name__}: {e}"
        return [TextContent(type="text", text=out)]

    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
