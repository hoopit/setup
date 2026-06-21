---
name: circleci-tests
description: Fetch failing tests from a CircleCI job URL. Use when user asks you to retrieve data from CircleCI.
---

# CircleCI Failing Tests

## Prerequisite — `CIRCLE_TOKEN`

The API calls below authenticate with a `CIRCLE_TOKEN` personal API token. Before
running them, check it's set:

```bash
[ -n "$CIRCLE_TOKEN" ] && echo "CIRCLE_TOKEN is set" || echo "CIRCLE_TOKEN is missing"
```

If it's missing, help the user set one up — don't just fail:

1. Have the user create a token at <https://app.circleci.com/settings/user/tokens>
   (CircleCI → User Settings → Personal API Tokens → *Create New Token*). This step
   needs the user — pause and let them generate and copy it; don't try to automate it.
2. Persist it to their shell rc so it survives new shells (pick the file that
   matches their shell — `~/.bashrc` for bash, `~/.zshrc` for zsh):

   ```bash
   echo 'export CIRCLE_TOKEN="<token>"' >> ~/.bashrc
   ```

3. Make it available in the current session before continuing:

   ```bash
   export CIRCLE_TOKEN="<token>"
   ```

Re-run the check above and confirm it prints *set* before making any API calls.

## Fetching failing tests

A CircleCI job URL carries everything you need — the `{org}`, `{repo}`, and
`{jobNumber}` are all in the path:
```text
https://app.circleci.com/pipelines/github/{org}/{repo}/{pipeline}/workflows/{wfId}/jobs/{jobNumber}/tests
```

Parse those segments from the URL and call the API — don't hard-code them:

```bash
curl -s -H "Circle-Token: $CIRCLE_TOKEN" \
  "https://circleci.com/api/v2/project/github/{org}/{repo}/{jobNumber}/tests" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
failures = [t for t in data['items'] if t['result'] == 'failure']
print(f'Total: {len(data[\"items\"])} tests, {len(failures)} failures\n')
for i, t in enumerate(failures, 1):
    print(f'{i}. {t[\"classname\"]}.{t[\"name\"]}')
    if t['message']:
        print(t['message'][:500])
    print('---')
"
```

- If the URL doesn't include the org/repo, check the current repo's `CLAUDE.md`
  for its GitHub repo slug and other CircleCI specifics.
