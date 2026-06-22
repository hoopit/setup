# Attachments & HAR files

Most ITSM tickets carry attachments — usually **HAR files** (full browser network capture at the time
of the bug) and screenshots. They are the single most useful evidence for confirming a repro and
pinning the failing endpoint. **Always download and analyze them yourself — never ask the reporter to
"review the HAR".**

## acli cannot download attachments — use the REST API

`acli jira workitem attachment` only supports `list` / `delete`, **not download**. Download goes through
the Jira REST API with the same token the writer uses.

```bash
set -a; . ~/.config/hoopit/jira.env; set +a        # JIRA_API_TOKEN, JIRA_EMAIL
JIRA=https://hoopit.atlassian.net
A=(-u "$JIRA_EMAIL:$JIRA_API_TOKEN")

# 1. List attachments (id | filename | mimeType | size | content URL)
curl -s "${A[@]}" -H 'Accept: application/json' "$JIRA/rest/api/3/issue/<KEY>?fields=attachment" \
  | python3 -c "import json,sys;[print(x['id'],x['filename'],x['mimeType'],x['size']) for x in json.load(sys.stdin)['fields'].get('attachment',[])]"

# 2. Download one by id (-L follows the redirect to media storage)
curl -sL "${A[@]}" "$JIRA/rest/api/3/attachment/content/<ID>" -o /tmp/<KEY>-<filename>
```

## HAR files — parse, don't read

HARs are often **5–15 MB**. Never read one into context whole. Extract the failing requests with a
script and look only at those:

```bash
python3 - /tmp/<KEY>-file.har <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for e in d["log"]["entries"]:
    req, resp = e["request"], e["response"]
    st = resp["status"]
    if st == 0 or st >= 400:                       # failures (0 = no response / network error)
        body = (resp.get("content", {}).get("text", "") or "")[:800]
        print(f"{req['method']} {st} {req['url']}")
        if req.get("postData", {}).get("text"):
            print("  req body:", req["postData"]["text"][:500])
        if body:
            print("  resp body:", body)
PY
```

From the failing entries, read off the **endpoint, method, request payload shape, and the error
response body** — that usually identifies the exact view/serializer/component to investigate. Also note
the request that fired immediately before the failure (timing/sequence). If nothing is ≥400, scan for
2xx responses whose body contains an error message matching the reported symptom.

## Screenshots / images

Download as above, then use the **Read tool** on the file path — it renders images visually. Use them to
confirm which screen/state the reporter is describing.

## Other attachments

Plain-text logs: download and `grep` for error/exception lines. PDFs: Read tool (supports PDFs).

## Only escalate to Needs-info for *missing* evidence

If the attachments DO let you confirm the failing request/screen, classify on that — do **not** mark
`Needs-info` merely because reading the HAR takes effort. Reserve `Needs-info` for genuinely absent or
insufficient evidence (no repro steps AND no useful attachment).
