# Triage Rubric — Sentry

What each per-issue analysis agent decides, and how. The agent is **read-only** — it never mutates
Sentry or Jira; it returns a verdict that the Apply step (`scripts/apply_review.py`) writes. Be
calibrated and honest: a wrong `Develop/Agent-ready` wastes a phase-2 run; an over-cautious `Escalate`
buries fixable work; a wrong `Resolve` hides a live bug.

## Per-issue procedure (each analysis agent)

1. **Read the issue** with the authenticated `sentry` CLI:
   - `sentry issue view <shortId> --json` — error type/message, culprit, status, **numeric id** (`id`),
     occurrence count, users affected, first/last seen, environment, level.
   - `sentry issue events <shortId> --limit 1 --json` — a recent event (stacktrace + request context).
   - Optionally `sentry issue explain <shortId>` for an AI root-cause seed.
   Record **impact**: usersAffected, eventCount (+ window), prod environment, escalating/new.
2. **Check for an existing Jira issue** so you don't propose a duplicate:
   `acli jira workitem search --jql 'project = BAC AND text ~ "<shortId>"' --fields 'key,status' --csv`.
   If a relevant **unresolved** issue exists, set `existingJiraKey` (the writer reuses it).
3. **Locate the root cause** READ-ONLY in the api base worktree (latest default branch). Trace the stack
   frame to the model/view/serializer/task; judge findability + fix size. For suppression, the surface is
   `before_send_event` / `traces_sampler` in `club_united_api/utilities/sentry.py`.
4. **Classify** into exactly one disposition + score the dimensions.
5. **Draft outputs**: a plain-text `sentryNote` (starts with the disclaimer), and for
   Develop/Escalate/Silence-in-code a `jiraSummary` + `jiraDescription`, plus a `jiraBrief` for
   Develop/Silence-in-code.

## Disposition — the primary axis

| Disposition | Use when | Downstream effect |
|---|---|---|
| **Develop** | Real, fixable bug; root cause is locatable in code and the fix is bounded. | Verdict posted on the Sentry issue (assigned `ai-triage`); `promote` creates a BAC Bug within budget. Only `Agent-ready` is auto-fixed. |
| **Escalate** | Real, **Critical/High**, needs a human **now** — ops/infra, a third party (Stripe/Firebase), data integrity, or a product/judgement call — and is *not* agent-fixable. | BAC issue created immediately (cap-exempt), `Human-only`, `sentry-escalated`, High priority. |
| **Silence-in-code** | **Not a true/actionable error.** High frequency/quota OR something we never want to hear about even if it escalates (expected client cancellations, framework noise, known third-party flakiness). | Verdict posted on the Sentry issue (assigned `ai-triage`) as an `Agent-ready` suppression task (edit `before_send_event`/sampling/ignore); `promote` creates the BAC Bug. Archived **forever** in Sentry. |
| **Archive** | Low-value / low-frequency noise worth monitoring, not worth code or a ticket now. | Archived **until escalating** in Sentry — re-opens automatically if it spikes. No Jira. |
| **Resolve** | Already fixed, stale (not seen in a long time), or not reproducible / invalid. | Marked resolved in Sentry. No Jira. |

**Silence-in-code vs Archive** — the test is *frequency/quota + permanence*. If it's loud (burning quota)
or we never want it back even on a spike → suppress in code (Silence). If it's quiet and we only care if
it grows → Archive (it resurfaces on escalation). **Escalate vs Develop** — both are real bugs; Escalate
is for what a human must act on now and an agent can't safely fix.

## `agentSuitability` — sub-axis for Develop / Silence-in-code

How autonomously the existing `auto-fix-next-bug` → `handle-jira-issue` flow (branch → fix → test → PR)
can resolve it. (`Silence-in-code` is always `Agent-ready` — a bounded, well-specified config edit.)

| Value | Use when |
|---|---|
| **Agent-ready** | Root cause locatable in code, fix bounded, regression test feasible. No human decision needed. |
| **Agent-assisted** | An agent does most of it but a human checkpoint is required (product/design call, data migration judgement, external access). |
| **Human-only** | Needs human judgement / manual repro / ops / third-party action. (If it's *urgent*, it's usually `Escalate`, not `Develop/Human-only`.) |

Prefer `Agent-assisted` over `Agent-ready` whenever any human decision is genuinely required — do not be
optimistic. Only `Agent-ready` BAC bugs are picked up autonomously.

## `value` — impact of resolving (High / Medium / Low)

`severity × reach`, **informed by Sentry impact data**. **High**: payments/money, data loss/corruption,
security, login/onboarding blocked, OR many users / events (e.g. hundreds of users or escalating in prod).
**Medium**: a real workflow degraded with a workaround, or a moderate user/event count. **Low**: cosmetic,
rare edge case, single-user, or near-zero volume.

## `effort` — size of the fix (High / Medium / Low)

**Low**: localized, one/few files, clear change, easy test. **Medium**: spans a couple of modules or needs
care around data/migrations. **High**: cross-cutting, uncertain blast radius, or hard to test.

## `confidence` — trust in this assessment (High / Medium / Low)

**High**: root cause confirmed in code / repro clear from the event. **Medium**: strong hypothesis.
**Low**: educated guess — phase-2 must re-verify before committing effort.

## `priorityScore` (computed, not by the model)

Map H/M/L → 3/2/1 and compute `round(100 * value / effort)` (High-value/Low-effort ≈ 300). Only meaningful
for `Agent-ready`/`Agent-assisted` (Develop/Silence-in-code) — null otherwise. It ranks the promotion
promotion order. The agent leaves it null; the workflow + writer recompute it deterministically.

## `area`

This run triages the **bac** Sentry project only, so `area` is always **API** (component **Backend**).

## Output templates (plain text — Sentry notes & Jira comments do NOT render markdown)

Every Sentry note starts with the disclaimer line. **No file paths or line numbers anywhere** — name
classes, methods, types, and behavioral contracts instead (paths go stale; symbols don't).

### `sentryNote` (every disposition)

```text
> *This was generated by AI during triage.*

AI TRIAGE — <disposition>
Value: <H/M/L> | Effort: <H/M/L> | Confidence: <H/M/L> | Users: <N> | Events: <N/window>

Assessment: <2–4 sentences: what this is, suspected root cause, why this disposition.>
```

The writer appends a tail line for queued/escalated items (e.g. "Queued for development…", "Escalated to
BAC-1234…"), so you don't need to add it.

### `jiraDescription` (Develop / Escalate / Silence-in-code)

```text
## Summary
<1–2 sentences>

## Root cause
<technical explanation / hypothesis>

## References
- Sentry: <shortId>
- First seen: <date>, Occurrences: <N>, Users impacted: <N>
```

### `jiraBrief` (Develop / Silence-in-code) — appended as an agent brief

```text
AGENT BRIEF
Summary: <one line>
Current behavior: <what happens now>
Desired behavior: <what should happen, incl. edge cases>
Key interfaces: <types / functions / config to look for or change>
Acceptance criteria:
- [ ] <testable criterion>
Out of scope: <what not to touch>
```

For **Silence-in-code**, the brief names the exact exception class / transaction / URL pattern to add to
`before_send_event` (or the sampling rule), and notes that a regression test should assert the event is
dropped.
