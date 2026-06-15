---
name: circleci-tests
description: Fetch failing tests from a CircleCI job URL. Use when user asks you to retrieve data from CircleCI.
---

# CircleCI Failing Tests

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

- `CIRCLE_TOKEN` must be in the environment (typically exported from `~/.bashrc`).
- If the URL doesn't include the org/repo, check the current repo's `CLAUDE.md`
  for its GitHub repo slug and other CircleCI specifics.
