#!/usr/bin/env python3
"""Apply triage verdicts to Jira ITSM tickets — the deterministic write step.

Reads a verdicts JSON file (a list of verdict objects produced by the triage
workflow's analyze stage) and, for each:
  - PUTs the AI: custom fields via the Jira REST API (label -> option id from field_map.json),
  - computes AI: Priority Score deterministically from value/effort,
  - stamps AI: Last Reviewed = now,
  - posts the triage comment via `acli` (plain text / --body-file).

This is the single, tested writer. The analyze agents only produce verdicts; nothing
else should hand-roll the field write. Reused for ad-hoc applies and by phase-2.

Verdict object shape (extra keys ignored):
  {
    "key": "ITSM-1234",
    "agentSuitability": "Agent-ready",            # required, must match field_map options
    "value": "High", "effort": "Medium",          # required
    "confidence": "High", "area": "API",          # required
    "comment": "> *This was generated...*\n...",  # optional; posted via acli if present
    "priorityScore": 150                            # optional; recomputed unless --keep-score
  }

Usage:
  python3 apply_verdicts.py verdicts.json [--dry-run] [--field-map FILE] [--jira-env FILE] [--keep-score]

Env (sourced from --jira-env, default ~/.config/hoopit/jira.env): JIRA_API_TOKEN, JIRA_EMAIL.
Exit code is non-zero if any ticket failed.
"""
import argparse, base64, datetime, json, os, re, subprocess, sys, tempfile, urllib.error, urllib.request

RANK = {"High": 3, "Medium": 2, "Low": 1}

# Durable-brief enforcement: agents occasionally leak volatile refs despite the prompt.
# Strip line numbers and file:line suffixes deterministically (keep symbol/method names).
_VOLATILE = [
    (re.compile(r"\s*\((?:see\s+)?lines?\s+\d+(?:\s*(?:[-–]|and)\s*\d+)?\)", re.I), ""),   # "(line 241)", "(lines 1-2)"
    (re.compile(r"\s+(?:on\s+|at\s+)?lines?\s+\d+(?:\s*(?:[-–]|and)\s*\d+)?", re.I), ""),  # " line 241", " at lines 1 and 2"
    (re.compile(r"(\.(?:py|ts|dart|js|html))[:#]L?\d+(?:-\d+)?", re.I), r"\1"),                  # "foo.py:163-167" -> "foo.py"
]


def strip_volatile_refs(text):
    if not text:
        return text
    for rx, repl in _VOLATILE:
        text = rx.sub(repl, text)
    return text
SCORED_TIERS = {"Agent-ready", "Agent-assisted"}
SELECT_KEYS = ["agentSuitability", "value", "effort", "confidence", "area"]
REQUIRED = SELECT_KEYS  # all selects required


def load_env(path):
    path = os.path.expanduser(path)
    if not os.path.isfile(path):
        sys.exit(f"FATAL: env file not found: {path}")
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())
    for k in ("JIRA_API_TOKEN", "JIRA_EMAIL"):
        if not os.environ.get(k):
            sys.exit(f"FATAL: {k} missing from {path}")


def priority_score(v):
    if v.get("agentSuitability") in SCORED_TIERS and RANK.get(v.get("value")) and RANK.get(v.get("effort")):
        return round(100 * RANK[v["value"]] / RANK[v["effort"]])
    return None


def resolve_target(v, status_map):
    """needs-info is authoritative: a ticket awaiting reporter info must never route to dev."""
    if v.get("needsInfo") or v.get("agentSuitability") == "Needs-info":
        return status_map["Needs-info"]
    return status_map.get(v.get("agentSuitability"))


def resolve_components(v, fmap):
    """Valid component names from the verdict (any unknown names are dropped)."""
    valid = set(fmap.get("components", []))
    return [c for c in (v.get("components") or []) if c in valid]


def build_fields(v, fmap, keep_score, target_status):
    f, opt = fmap["fields"], fmap["options"]
    body = {}
    for key in SELECT_KEYS:
        label = v[key]
        if label not in opt[key]:
            raise ValueError(f"unknown {key} value {label!r} (valid: {list(opt[key])})")
        body[f[key]] = {"id": opt[key][label]}
    score = v.get("priorityScore") if keep_score else priority_score(v)
    if score is not None:
        body[f["priorityScore"]] = score
    body[f["lastReviewed"]] = datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S.000%z")
    # Components reflect the implementation surface; only set them when moving to dev.
    if target_status == "Pending development":
        comps = resolve_components(v, fmap)
        if comps:
            body["components"] = [{"name": c} for c in comps]
    return body


def get_status(base, auth, key):
    req = urllib.request.Request(f"{base}/rest/api/3/issue/{key}?fields=status")
    req.add_header("Authorization", auth); req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)["fields"]["status"]["name"]
    except Exception:
        return None


def transition(key, status):
    cp = subprocess.run(["acli", "jira", "workitem", "transition", "--key", key, "--status", status, "--yes"],
                        capture_output=True, text=True)
    return cp.returncode, (cp.stderr or cp.stdout).strip()[:200]


def put_fields(base, auth, key, fields):
    req = urllib.request.Request(f"{base}/rest/api/3/issue/{key}", data=json.dumps({"fields": fields}).encode(), method="PUT")
    req.add_header("Authorization", auth); req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, ""
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


def post_comment(key, comment):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
        fh.write(comment); path = fh.name
    try:
        cp = subprocess.run(["acli", "jira", "workitem", "comment", "create", "--key", key, "--body-file", path],
                            capture_output=True, text=True)
        return cp.returncode, (cp.stderr or cp.stdout).strip()[:200]
    finally:
        os.unlink(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("verdicts")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--keep-score", action="store_true", help="trust verdict.priorityScore instead of recomputing")
    ap.add_argument("--field-map", default=os.path.join(os.path.dirname(__file__), "field_map.json"))
    ap.add_argument("--jira-env", default="~/.config/hoopit/jira.env")
    ap.add_argument("--no-transition", action="store_true", help="set fields/comment but do not change workflow status")
    args = ap.parse_args()

    fmap = json.load(open(args.field_map))
    base = fmap["jira_base_url"]
    status_map = fmap["status_map"]
    verdicts = json.load(open(args.verdicts))
    if isinstance(verdicts, dict):
        verdicts = verdicts.get("result", verdicts.get("verdicts", [verdicts]))

    if not args.dry_run:
        load_env(args.jira_env)
        auth = "Basic " + base64.b64encode(f'{os.environ["JIRA_EMAIL"]}:{os.environ["JIRA_API_TOKEN"]}'.encode()).decode()

    failures = 0
    for v in verdicts:
        key = v.get("key", "<no-key>")
        target = resolve_target(v, status_map)
        if not target:
            print(f"{key}: SKIP — no status mapping for agentSuitability={v.get('agentSuitability')!r}"); failures += 1; continue
        try:
            fields = build_fields(v, fmap, args.keep_score, target)
        except (KeyError, ValueError) as e:
            print(f"{key}: SKIP — {e}"); failures += 1; continue
        score = fields.get(fmap["fields"]["priorityScore"])
        comps = resolve_components(v, fmap) if target == "Pending development" else []
        if args.dry_run:
            has_c = "comment" if v.get("comment") else "no-comment"
            cstr = f" components={comps}" if target == "Pending development" else ""
            print(f"{key}: DRY -> {target} | {v['agentSuitability']}/{v['value']}/{v['effort']}/{v['confidence']}/{v['area']} score={score}{cstr} ({has_c})")
            continue
        st, err = put_fields(base, auth, key, fields)
        if st != 204:
            print(f"{key}: PUT FAILED {st} {err}"); failures += 1; continue
        parts = []
        if v.get("comment"):
            rc, cout = post_comment(key, strip_volatile_refs(v["comment"]))
            parts.append("comment ok" if rc == 0 else f"COMMENT FAILED rc={rc} {cout}")
            if rc != 0:
                failures += 1
        if not args.no_transition:
            cur = get_status(base, auth, key)
            protected = set(fmap.get("protected_statuses", []))
            if cur == target:
                parts.append(f"already {target}")
            elif cur in protected:
                parts.append(f"PROTECTED ({cur}) — not reopening to {target}")  # never reopen resolved tickets
            else:
                rc, tout = transition(key, target)
                parts.append(f"{cur} -> {target}" if rc == 0 else f"TRANSITION FAILED rc={rc} {tout}")
                if rc != 0:
                    failures += 1
        cstr = f" components={comps}" if comps else ""
        print(f"{key}: applied (score={score}){cstr} {' | '.join(parts)}")

    print(f"\n{'DRY RUN — ' if args.dry_run else ''}{len(verdicts) - failures}/{len(verdicts)} ok, {failures} failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
