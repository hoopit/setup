#!/usr/bin/env python3
"""Shared helpers for the triage-sentry writers (apply_review.py, promote_pending.py).

Two backends:
  - Jira: reads/comments/transitions/create via `acli`; field/label/priority writes via the Jira REST
    API (acli cannot set custom-field values). Auth from JIRA_EMAIL + JIRA_API_TOKEN.
  - Sentry: everything via the Sentry REST API (a standalone script cannot call MCP tools). Auth from
    SENTRY_AUTH_TOKEN (needs scopes event:write + org:integrations for status/assign/priority/notes and
    the native Jira link).

No MCP, no network library beyond urllib + the `acli` CLI, so this is fully testable and dry-runnable.
"""
from __future__ import annotations

import base64
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

RANK = {"High": 3, "Medium": 2, "Low": 1}
SCORED_TIERS = {"Agent-ready", "Agent-assisted"}
SELECT_KEYS = ["agentSuitability", "value", "effort", "confidence", "area"]

# Agents occasionally leak volatile refs despite the prompt. Strip line numbers / file:line suffixes
# deterministically (keep symbol/method names). Mirrors triage-itsm/scripts/apply_verdicts.py.
_VOLATILE = [
    (re.compile(r"\s*\((?:see\s+)?lines?\s+\d+(?:\s*(?:[-–]|and)\s*\d+)?\)", re.I), ""),
    (re.compile(r"\s+(?:on\s+|at\s+)?lines?\s+\d+(?:\s*(?:[-–]|and)\s*\d+)?", re.I), ""),
    (re.compile(r"(\.(?:py|ts|dart|js|html))[:#]L?\d+(?:-\d+)?", re.I), r"\1"),
]


def warn(msg):
    print(msg, file=sys.stderr)


def strip_volatile_refs(text):
    if not text:
        return text
    for rx, repl in _VOLATILE:
        text = rx.sub(repl, text)
    return text


def priority_score(v):
    """Deterministic value/effort score; only meaningful for Agent-ready/Agent-assisted (Develop/Silence)."""
    if v.get("agentSuitability") in SCORED_TIERS and RANK.get(v.get("value")) and RANK.get(v.get("effort")):
        return round(100 * RANK[v["value"]] / RANK[v["effort"]])
    return None


def now_jira():
    return datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S.000%z")


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------- env / config

def load_env_file(path):
    """Source KEY=VALUE lines from an env file into os.environ (without overriding existing)."""
    path = os.path.expanduser(path)
    if not os.path.isfile(path):
        return
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, val = line.split("=", 1)
            os.environ.setdefault(k.strip(), val.strip().strip('"').strip("'"))


def require_jira_env(jira_env):
    load_env_file(jira_env)
    for k in ("JIRA_API_TOKEN", "JIRA_EMAIL"):
        if not os.environ.get(k):
            sys.exit(f"FATAL: {k} missing (set it or add it to {jira_env})")
    return "Basic " + base64.b64encode(
        f'{os.environ["JIRA_EMAIL"]}:{os.environ["JIRA_API_TOKEN"]}'.encode()
    ).decode()


def load_field_map(path):
    return json.load(open(path))


# ---------------------------------------------------------------------------- Jira REST + acli

def _jira_request(base, auth, path, method="GET", body=None):
    url = f"{base}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", auth)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:500]


def jira_get_status(base, auth, key):
    st, payload = _jira_request(base, auth, f"/rest/api/3/issue/{key}?fields=status")
    if st == 200 and isinstance(payload, dict):
        return payload["fields"]["status"]["name"]
    return None


def jira_put(base, auth, key, body):
    """PUT an issue edit body (fields and/or update ops). Returns (status_code, err_text)."""
    st, payload = _jira_request(base, auth, f"/rest/api/3/issue/{key}", "PUT", body)
    return st, ("" if st == 204 else (payload if isinstance(payload, str) else json.dumps(payload)))


def acli(*args):
    cp = subprocess.run(["acli", "jira", *args], capture_output=True, text=True)
    return cp.returncode, (cp.stdout or "") + (("\n" + cp.stderr) if cp.stderr else "")


def jira_search_count(jql):
    """Count issues matching a JQL via acli CSV (header line excluded). Returns int or None on error."""
    rc, out = acli("workitem", "search", "--jql", jql, "--fields", "key", "--csv", "--paginate")
    if rc != 0:
        return None
    lines = [ln for ln in out.splitlines() if ln.strip()]
    # first line is the CSV header
    return max(0, len(lines) - 1)


def jira_search_keys(jql, limit=10):
    rc, out = acli("workitem", "search", "--jql", jql, "--fields", "key", "--csv", "--limit", str(limit))
    if rc != 0:
        return []
    keys = []
    for ln in out.splitlines()[1:]:
        m = re.match(r"([A-Z]+-\d+)", ln.strip())
        if m:
            keys.append(m.group(1))
    return keys


def jira_create_bug(project, summary, description):
    """Create a Bug via acli; return the new key or None."""
    rc, out = acli(
        "workitem", "create", "--project", project, "--type", "Bug",
        "--summary", summary, "--description", description,
    )
    if rc != 0:
        warn(f"jira create failed: {out.strip()[:300]}")
        return None
    m = re.search(r"([A-Z]+-\d+)", out)
    return m.group(1) if m else None


def jira_comment(key, body):
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
        fh.write(body)
        path = fh.name
    try:
        rc, out = acli("workitem", "comment", "create", "--key", key, "--body-file", path)
        return rc, out.strip()[:200]
    finally:
        os.unlink(path)


def jira_transition(key, status):
    rc, out = acli("workitem", "transition", "--key", key, "--status", status, "--yes")
    return rc, out.strip()[:200]


def build_ai_fields(v, fmap, *, suitability=None, score=None, with_components=True, priority_name=None):
    """Assemble the Jira edit body for the AI: fields + area + components + priority + sentry labels.

    suitability overrides the verdict's agentSuitability (used to force escalations to Human-only).
    """
    f, opt = fmap["fields"], fmap["options"]
    suit = suitability or v["agentSuitability"]
    area = v.get("area") or fmap.get("default_area", "API")
    fields = {
        f["agentSuitability"]: {"id": opt["agentSuitability"][suit]},
        f["value"]: {"id": opt["value"][v["value"]]},
        f["effort"]: {"id": opt["effort"][v["effort"]]},
        f["confidence"]: {"id": opt["confidence"][v["confidence"]]},
        f["area"]: {"id": opt["area"][area]},
        f["lastReviewed"]: now_jira(),
    }
    if score is not None:
        fields[f["priorityScore"]] = score
    if with_components and fmap.get("components"):
        fields["components"] = [{"name": c} for c in fmap["components"]]
    if priority_name:
        fields["priority"] = {"name": priority_name}
    return {"fields": fields}


def add_labels_op(body, labels):
    body.setdefault("update", {})["labels"] = [{"add": lab} for lab in labels]
    return body


# ---------------------------------------------------------------------------- Sentry (via the `sentry` CLI)
# Auth is handled by the authenticated `sentry` CLI — no token env var. `sentry api` is a generic REST
# proxy (endpoint relative to /api/0/); `sentry issue archive|resolve` are first-class status commands.

def sentry_cli(*args):
    cp = subprocess.run(["sentry", *args], capture_output=True, text=True)
    return cp.returncode, ((cp.stdout or "") + (("\n" + cp.stderr) if cp.stderr else "")).strip()


def sentry_auth_ok():
    rc, _ = sentry_cli("auth", "status")
    return rc == 0


def sentry_api(endpoint, method="GET", body=None, dry=False):
    """Raw Sentry REST via the CLI proxy. Returns (rc, text). rc != 0 on HTTP error."""
    args = ["api", endpoint, "-X", method]
    if body is not None:
        args += ["-d", json.dumps(body)]
    if dry:
        args += ["--dry-run"]
    return sentry_cli(*args)


def sentry_get_issue(numeric_id):
    rc, out = sentry_api(f"issues/{numeric_id}/")
    if rc == 0:
        try:
            return json.loads(out)
        except Exception:
            return None
    return None


def sentry_update_issue(numeric_id, body, dry=False):
    """Update assignedTo / priority / status etc. on a Sentry issue. Returns (rc, text)."""
    return sentry_api(f"issues/{numeric_id}/", "PUT", body, dry=dry)


def sentry_add_note(numeric_id, text, dry=False):
    return sentry_api(f"issues/{numeric_id}/comments/", "POST", {"text": text}, dry=dry)


def sentry_archive(short_id, until=None):
    """`sentry issue archive`: until='auto' = archive-until-escalating; until=None = archive forever."""
    args = ["issue", "archive", short_id]
    if until:
        args += ["--until", until]
    return sentry_cli(*args)


def sentry_resolve(short_id):
    return sentry_cli("issue", "resolve", short_id)


def sentry_link_jira(numeric_id, jira_key, integration_id, dry=False):
    """Native two-way link of an existing Jira issue to a Sentry group. Returns (ok, detail)."""
    if not integration_id:
        return False, "no jira integration id"
    rc, out = sentry_api(f"groups/{numeric_id}/integrations/{integration_id}/", "PUT",
                         {"externalIssue": jira_key}, dry=dry)
    return rc == 0, out[:200]


def sentry_has_jira_link(issue_payload):
    """Best-effort detection of an existing native Jira link from a GET issue payload (annotations)."""
    if not isinstance(issue_payload, dict):
        return False
    blob = json.dumps(issue_payload.get("annotations") or []).lower()
    return "jira" in blob or "browse/" in blob


def team_slug_of(triage_assignee):
    """'team:ai-triage' -> 'ai-triage'."""
    return (triage_assignee or "").split(":", 1)[-1]


def sentry_assigned_to_team(issue_payload, team_slug):
    """True iff the issue's current assignee is the given team (works for any status, incl. ignored)."""
    if not isinstance(issue_payload, dict):
        return False
    a = issue_payload.get("assignedTo")
    if not isinstance(a, dict) or a.get("type") != "team":
        return False
    return team_slug in (a.get("slug"), a.get("name"))


def sentry_team_issues(fmap, team_slug):
    """Issues assigned to the team and not resolved (covers unresolved + ignored/archived — so Develop AND
    Silence-in-code both appear). Returns [{'numericId','shortId'}]. This is promote's work-list."""
    params = urllib.parse.urlencode(
        {"project": fmap["sentry_project_id"], "query": f"assigned:#{team_slug} !is:resolved", "limit": 100},
        quote_via=urllib.parse.quote,
    )
    rc, out = sentry_api(f"organizations/{fmap['sentry_org']}/issues/?{params}")
    if rc != 0:
        return []
    try:
        data = json.loads(out)
    except Exception:
        return []
    return [{"numericId": str(it.get("id")), "shortId": it.get("shortId")} for it in data if isinstance(it, dict)]


def sentry_list_comments(numeric_id):
    rc, out = sentry_api(f"issues/{numeric_id}/comments/")
    if rc != 0:
        return []
    try:
        return json.loads(out)
    except Exception:
        return []


# --- verdict carried on the Sentry issue itself (no local queue) -------------------------------------
# review appends a marker-delimited one-line JSON block to its human note; promote parses the latest back.

VERDICT_MARKER = "===AI-TRIAGE-VERDICT-V1==="


def encode_verdict(verdict):
    """Marker + compact one-line JSON, to append after a human-readable note."""
    return f"{VERDICT_MARKER}\n{json.dumps(verdict, separators=(',', ':'))}"


def comment_text(c):
    if not isinstance(c, dict):
        return ""
    d = c.get("data")
    if isinstance(d, dict) and d.get("text"):
        return d["text"]
    return c.get("text") or ""


def parse_verdict_from_comments(comments):
    """The most-recent embedded verdict dict across an issue's comments, or None (latest wins on re-review)."""
    best = None  # (dateCreated, verdict)
    for c in comments or []:
        text = comment_text(c)
        if not text or VERDICT_MARKER not in text:
            continue
        tail = text.split(VERDICT_MARKER, 1)[1].strip()
        line = tail.splitlines()[0].strip() if tail else ""
        try:
            v = json.loads(line)
        except Exception:
            continue
        ts = c.get("dateCreated") or ""
        if best is None or ts >= best[0]:
            best = (ts, v)
    return best[1] if best else None


# ---------------------------------------------------------------------------- ledger (audit-only)
# Append-only local log of what each run did, for unattended-run debugging. NOTHING reads it for control
# flow — dedup is purely Sentry-side (review: `!assigned:#ai-triage`; promote: the team work-list + link
# check). Safe to delete/rotate; the system is otherwise stateless (Sentry holds the verdict + state).

def ledger_path(skill_local):
    return os.path.join(skill_local, "triaged.log")


def ledger_append(path, short_id, disposition, jira_key="-"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as fh:
        fh.write(f"{short_id}\t{now_utc()}\t{disposition}\t{jira_key}\n")
