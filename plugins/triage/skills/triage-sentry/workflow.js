export const meta = {
  name: 'triage-sentry-review',
  description: 'Analyze Hoopit Sentry issues in parallel: one read-only agent per issue produces a schema-validated disposition verdict. Sentry/Jira writes happen separately via scripts/apply_review.py.',
  phases: [
    { title: 'Analyze', detail: 'one read-only Explore agent per Sentry issue -> schema-validated verdict' },
    { title: 'Reconcile', detail: 'converge same-signature issue clusters that disagreed on disposition (one agent per conflict; skipped when none)' },
  ],
}

// args: { issues: [{shortId, numericId, title?}], skillDir?, repoPaths? }
// Be robust to args arriving as a JSON string instead of an object.
let A = typeof args === 'string' ? (() => { try { return JSON.parse(args) } catch { return {} } })() : (args || {})
const ISSUES = A.issues || []
const SKILL = A.skillDir
if (!SKILL) throw new Error('args.skillDir is required — the orchestrator must pass this skill\'s directory.')
// Base worktree (pinned to api's default branch) prepared by the orchestrator and passed in args.repoPaths.
const API_PATH = (A.repoPaths && A.repoPaths.api) || ''

if (!ISSUES.length) {
  log('No Sentry issues passed in args.issues — nothing to analyze.')
  return []
}
log(`Analyzing ${ISSUES.length} Sentry issue(s). Writes happen separately via scripts/apply_review.py.`)

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['sentryShortId', 'sentryNumericId', 'title', 'disposition', 'value', 'effort', 'confidence', 'area', 'impact', 'reproResult', 'rootCauseHypothesis', 'sentryNote', 'existingJiraKey'],
  properties: {
    sentryShortId: { type: 'string' },
    sentryNumericId: { type: 'string', description: 'Numeric Sentry issue/group id (from `sentry issue view --json` field "id"). Required for REST/native-link calls.' },
    title: { type: 'string' },
    disposition: { enum: ['Develop', 'Escalate', 'Silence-in-code', 'Archive', 'Resolve'] },
    agentSuitability: { enum: ['Agent-ready', 'Agent-assisted', 'Human-only', null] },
    value: { enum: ['High', 'Medium', 'Low'] },
    effort: { enum: ['High', 'Medium', 'Low'] },
    confidence: { enum: ['High', 'Medium', 'Low'] },
    area: { enum: ['API', 'Web Admin', 'Flutter App', 'Multiple', 'Unknown'] },
    impact: {
      type: 'object',
      additionalProperties: true,
      properties: {
        usersAffected: { type: ['number', 'null'] },
        eventCount: { type: ['number', 'null'] },
        window: { type: 'string' },
      },
    },
    reproResult: { enum: ['confirmed', 'failed', 'insufficient-info', 'not-applicable'] },
    rootCauseHypothesis: { type: 'string' },
    jiraSummary: { type: 'string', description: 'Concise BAC bug title. Required for Develop/Escalate/Silence-in-code.' },
    jiraDescription: { type: 'string', description: 'BAC bug description incl. a "## References - Sentry: <shortId>" line. Required for Develop/Escalate/Silence-in-code.' },
    jiraBrief: { type: 'string', description: 'Plain-text agent brief (Develop/Silence-in-code). Symbol names only — NO file paths or line numbers.' },
    sentryNote: { type: 'string', description: 'Plain-text note for the Sentry activity feed. MUST begin with the AI disclaimer line.' },
    existingJiraKey: { type: ['string', 'null'], description: 'An existing OPEN BAC issue already tracking this error (text-match), else null. The writer reuses it instead of creating a duplicate.' },
    priorityScore: { type: ['number', 'null'] },
  },
}

const analyzePrompt = (issue) => `You are triaging a single Hoopit Sentry issue: **${issue.shortId}** (numeric id ${issue.numericId || 'unknown — fetch it'}).

You are READ-ONLY. Do NOT resolve/archive/assign/comment on the Sentry issue, do NOT write to Jira, do NOT edit any files. Produce a calibrated triage verdict only.

1. Read the rubric and follow it exactly (disposition definitions, scoring, note + brief templates): ${SKILL}/RUBRIC.md
2. Fetch the issue with the authenticated \`sentry\` CLI (load the \`sentry-cli\` skill if you need command help):
   - \`sentry issue view ${issue.shortId} --json\` — error type/message, culprit, status, **numeric id** (field "id"), counts, users, first/last seen, environment, level.
   - \`sentry issue events ${issue.shortId} --limit 1 --json\` — a recent event with stacktrace + request context.
   - Optionally \`sentry issue explain ${issue.shortId}\` for an AI root-cause seed.
   Capture impact: usersAffected, eventCount (state the window, e.g. 14d/30d), production environment, substatus (e.g. regressed/new/ongoing), and whether it is escalating. Record the issue's exact title and culprit VERBATIM (used downstream to cluster sibling issues — do not paraphrase). Restrict your reading to PRODUCTION events.
3. Check whether an OPEN BAC issue already tracks this error so you don't propose a duplicate:
   \`acli jira workitem search --jql 'project = BAC AND text ~ "${issue.shortId}"' --fields 'key,status' --csv\`
   If a relevant unresolved issue exists, set existingJiraKey to its key.
4. Locate the root cause READ-ONLY in the api base worktree (pinned to the latest default branch — analyze against this production-equivalent state): API=${API_PATH}. Trace the stack frame to the model/view/serializer/task; judge how findable the cause is and how big the fix looks. For "silence in code", the suppression surface is club_united_api/utilities/sentry.py (before_send_event / traces_sampler) — name the exception class / transaction to suppress.
5. Classify into exactly one disposition and set value/effort/confidence + (for Develop/Silence-in-code) agentSuitability, plus jiraSummary/jiraDescription/jiraBrief where the rubric requires them, and a plain-text sentryNote that MUST start with \`> *This was generated by AI during triage.*\`. **Never put file paths or line numbers in jiraBrief or sentryNote — name classes/methods/types and behavior instead.**

Disposition guide (full definitions in RUBRIC.md):
- **Develop** — real, fixable bug; set agentSuitability (Agent-ready / Agent-assisted / Human-only). Only Agent-ready is auto-fixed downstream; be honest.
- **Escalate** — real, Critical/High, needs a human now (ops/3rd-party/judgement), not agent-fixable. agentSuitability = Human-only.
- **Silence-in-code** — NOT a true/actionable error; high frequency/quota OR never-want-to-hear even if it escalates. agentSuitability = Agent-ready; brief targets before_send_event / sampling / ignore.
- **Archive** — low-value/low-frequency noise to monitor; re-opens in Sentry if it spikes. No Jira.
- **Resolve** — already fixed / stale / not reproducible. No Jira.

Calibration for infrastructure / transient / recurring errors (connection refused, broker/AMQP, statement timeout, 5xx from a dependency) and ANY issue whose substatus is "regressed": before choosing Escalate or Resolve, establish whether the incident is still live. (a) Compare lastSeen against the most recent relevant fix/deploy in the api worktree (\`git log\` around lastSeen for infra/config/code changes) — if there are NO events after a confirmed fix, it is Resolve, not Escalate. (b) Check whether SIBLING issues with the same error signature were already resolved or assigned to the ai-triage team (\`sentry issue list\`/search, or the Jira text search above) — if the same incident is already handled, match that disposition. Do NOT over-weight the "regressed" substatus: it reflects the issue's history, not proof of a current recurrence. Escalate only when the error is genuinely still occurring and a human is needed now.

Set area = "API" (this run triages the bac project only). Leave priorityScore null (recomputed deterministically downstream). Set existingJiraKey to null if none. Return the verdict object.`

// Deterministic value/effort priority score (don't trust the model to do arithmetic).
const RANK = { High: 3, Medium: 2, Low: 1 }
const SCORED = new Set(['Agent-ready', 'Agent-assisted'])
const withScore = (v) => {
  if (!v) return v
  v.priorityScore = SCORED.has(v.agentSuitability) && RANK[v.value] && RANK[v.effort]
    ? Math.round((100 * RANK[v.value]) / RANK[v.effort]) : null
  return v
}

const verdicts = (await parallel(
  ISSUES.map((issue) => () =>
    agent(analyzePrompt(issue), { label: `analyze:${issue.shortId}`, phase: 'Analyze', schema: VERDICT_SCHEMA, agentType: 'Explore', model: 'sonnet' }),
  ),
)).filter(Boolean).map(withScore)

// ---- Reconcile: harmonize verdicts across same-signature issue clusters ----
// Independent per-issue agents can land inconsistently when several Sentry issues share one root cause
// (same exception/message on different endpoints/culprits). Group by normalized title; for EVERY
// multi-member cluster a single read-only agent re-investigates the SHARED evidence (event timelines,
// deploy/git history, and sibling issues already handled in earlier runs) and converges on ONE
// disposition — or declares the members genuinely different ("keep-split"). If it cannot converge, the
// whole cluster is escalated to a human (the safe, loud fallback). We reconcile every multi-member cluster
// (not only ones that disagree) because a unanimous-but-wrong cluster has no internal conflict to detect.
// Costs nothing when there are no multi-member clusters (pure-JS grouping, no agent).

const realStr = (s) => (s && s !== 'null' ? s : null)
// Normalize a title into a cluster key: digits -> '#', drop punctuation, collapse whitespace. Groups
// issues whose titles differ only by ids/counts (e.g. the same exception raised from different endpoints).
const normKey = (t) => String(t || '').toLowerCase().replace(/\d+/g, '#').replace(/[^a-z#]+/g, ' ').replace(/\s+/g, ' ').trim()

const buildNote = (disp, val, eff, conf, impact, assessment) => {
  const imp = impact || {}
  const ev = imp.eventCount != null ? `${imp.eventCount}${imp.window ? ' / ' + imp.window : ''}` : '?'
  return `> *This was generated by AI during triage.*\n\n` +
    `AI TRIAGE — ${disp}\n` +
    `Value: ${val} | Effort: ${eff} | Confidence: ${conf} | Users: ${imp.usersAffected ?? '?'} | Events: ${ev}\n\n` +
    `Assessment: ${assessment}`
}

const refsBlock = (member, siblings) => {
  const imp = member.impact || {}
  const others = siblings.filter((s) => s !== member.sentryShortId)
  return `\n\n## References\n- Sentry: ${member.sentryShortId}` +
    (others.length ? ` (cluster: ${others.join(', ')})` : '') +
    `\n- Occurrences: ${imp.eventCount ?? '?'}, Users impacted: ${imp.usersAffected ?? '?'}${imp.window ? ', Window: ' + imp.window : ''}`
}

const NO_JIRA = new Set(['Resolve', 'Archive'])

// Apply a converged group decision to one cluster member (keeps the member's own ids + impact).
const applyConverged = (member, d, siblings) => {
  const disp = d.disposition
  const out = {
    ...member,
    disposition: disp,
    value: d.value, effort: d.effort, confidence: d.confidence, area: member.area || 'API',
    agentSuitability: NO_JIRA.has(disp) ? null : (d.agentSuitability || (disp === 'Escalate' ? 'Human-only' : 'Agent-ready')),
    sentryNote: buildNote(disp, d.value, d.effort, d.confidence, member.impact, d.assessment || ''),
  }
  if (NO_JIRA.has(disp)) {
    out.jiraSummary = null; out.jiraDescription = null; out.jiraBrief = null
  } else {
    out.jiraSummary = realStr(d.jiraSummary) || member.title
    out.jiraDescription = (realStr(d.jiraDescriptionBody) || `## Summary\n${member.title}`) + refsBlock(member, siblings)
    out.jiraBrief = disp === 'Escalate' ? null : (realStr(d.jiraBrief) || realStr(member.jiraBrief) || '')
  }
  return withScore(out)
}

// Deterministic fallback: escalate one cluster member to a human (cannot-converge).
const escalate = (member, reason, siblings) => {
  const eff = member.effort || 'High'
  const conf = member.confidence || 'Medium'
  const hadDesc = realStr(member.jiraDescription)
  return withScore({
    ...member,
    disposition: 'Escalate', agentSuitability: 'Human-only',
    value: 'High', effort: eff, confidence: conf, area: member.area || 'API',
    jiraSummary: realStr(member.jiraSummary) || member.title,
    jiraDescription: hadDesc || (`## Summary\n${member.title}\n\n## Root cause\n${member.rootCauseHypothesis || 'See Sentry.'}` + refsBlock(member, siblings)),
    jiraBrief: null,
    sentryNote: buildNote('Escalate', 'High', eff, conf, member.impact,
      `${reason} Triage could not converge on a single disposition for this error cluster (${siblings.join(', ')}); escalating for human review.`),
  })
}

const RECONCILE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['decision', 'rationale'],
  properties: {
    decision: { enum: ['converged', 'keep-split', 'cannot-converge'] },
    disposition: { enum: ['Develop', 'Escalate', 'Silence-in-code', 'Archive', 'Resolve', null] },
    agentSuitability: { enum: ['Agent-ready', 'Agent-assisted', 'Human-only', null] },
    value: { enum: ['High', 'Medium', 'Low', null] },
    effort: { enum: ['High', 'Medium', 'Low', null] },
    confidence: { enum: ['High', 'Medium', 'Low', null] },
    assessment: { type: ['string', 'null'], description: '2-4 sentence shared assessment for the converged disposition; embedded verbatim in each member note. Required when decision=converged.' },
    jiraSummary: { type: ['string', 'null'], description: 'Required when converged to Develop/Escalate/Silence-in-code.' },
    jiraDescriptionBody: { type: ['string', 'null'], description: 'BAC bug description WITHOUT a References section (the workflow appends per-member references). Required when converged to Develop/Escalate/Silence-in-code.' },
    jiraBrief: { type: ['string', 'null'], description: 'Agent brief (converged Develop/Silence-in-code). Symbol names only — no file paths.' },
    rationale: { type: 'string', description: 'Why this decision — cite the deciding evidence (event timeline, fix/deploy commit + date vs lastSeen).' },
  },
}

const reconcilePrompt = (key, members) => `You are reconciling a CLUSTER of Hoopit Sentry issues that share one error signature but were triaged INDEPENDENTLY (they may or may not have agreed). Confirm they should share a single disposition — and correct it even if the independent verdicts AGREE but are wrong (e.g. several issues of one already-fixed incident all marked Escalate).

Cluster signature (normalized): ${key}
Members (each already carries an independent verdict):
${members.map((m) => `- ${m.sentryShortId} (numeric ${m.sentryNumericId}): disposition=${m.disposition}, value=${m.value}, effort=${m.effort}, confidence=${m.confidence}, users=${(m.impact || {}).usersAffected}, events=${(m.impact || {}).eventCount}/${(m.impact || {}).window}
    title: ${m.title}
    rootCause: ${m.rootCauseHypothesis}`).join('\n')}

You are READ-ONLY. Do NOT mutate Sentry/Jira or edit files. Investigate the SHARED evidence to converge:
- Per member, re-check the live signal with the \`sentry\` CLI: \`sentry issue view <shortId> --json\` (status, substatus, count, firstSeen, lastSeen) and \`sentry issue events <shortId> --limit 1 --json\`. For an "already fixed?" cluster the decisive question is: are there ANY events AFTER the suspected fix/deploy date, across ALL members?
- Check the api base worktree (read-only) for a deploy/fix that explains the timeline: API=${API_PATH}. Use \`git log\` around the last-seen date to confirm whether a fix landed (infra/config/code) and whether it post-dates the last event.
- CROSS-BATCH check: this cluster may be only PART of a larger incident already handled in earlier runs. Search Sentry for the SAME signature outside this batch — \`sentry issue list\`/search for already-\`is:resolved\` or \`assigned:#ai-triage\` issues with this error. If sibling issues were already resolved (or the incident was fixed and is now dormant), converge this cluster to match them (usually Resolve). Never re-escalate an incident that has already been resolved elsewhere.
- Follow the rubric for disposition definitions/scoring: ${SKILL}/RUBRIC.md

Return one of:
- decision="converged" + disposition + value/effort/confidence (+ agentSuitability for Develop/Silence-in-code) + a shared \`assessment\` (2-4 sentences) — when ALL members should share ONE disposition (e.g. all Resolve because no events occurred after the confirmed fix). For Develop/Escalate/Silence-in-code also return jiraSummary + jiraDescriptionBody (NO References section — the workflow adds per-member refs) and, for Develop/Silence-in-code, jiraBrief.
- decision="keep-split" — ONLY when the members are genuinely different (real evidence they diverge, e.g. one endpoint still erroring after the fix while another is dormant). Their independent verdicts are kept unchanged. Justify in rationale.
- decision="cannot-converge" — when the evidence is insufficient to decide. The whole cluster is then escalated to a human.

Always set rationale to the deciding evidence (the event timeline; the fix commit and its date vs lastSeen). Be calibrated: a dormant cluster with zero events since a confirmed fix is a clean "converged -> Resolve", not an escalation.`

// Group by normalized signature; reconcile EVERY multi-member cluster (>=2), not only ones that disagree —
// a unanimous-but-wrong cluster (e.g. several issues of one already-fixed incident all marked Escalate) has
// no internal conflict to detect, so triggering only on disagreement would let it through.
const groups = {}
for (const v of verdicts) (groups[normKey(v.title)] ||= []).push(v)
const clusters = Object.entries(groups).filter(([, ms]) => ms.length > 1)

let finalVerdicts = verdicts
if (clusters.length) {
  phase('Reconcile')
  log(`Reconciling ${clusters.length} multi-member cluster(s): ${clusters.map(([, ms]) => `${ms.map((m) => m.sentryShortId).join('/')} [${[...new Set(ms.map((m) => m.disposition))].join(' vs ')}]`).join('; ')}`)
  const decisions = (await parallel(
    clusters.map(([key, members]) => () =>
      agent(reconcilePrompt(key, members), { label: `reconcile:${members.map((m) => m.sentryShortId).join('+')}`, phase: 'Reconcile', schema: RECONCILE_SCHEMA, agentType: 'Explore', model: 'sonnet' })
        .then((d) => ({ key, members, d })),
    ),
  )).filter(Boolean)

  const replaced = {}
  for (const { members, d } of decisions) {
    const sibs = members.map((m) => m.sentryShortId)
    const why = (d && d.rationale ? d.rationale : '').slice(0, 160)
    if (d && d.decision === 'converged' && d.disposition) {
      for (const m of members) replaced[m.sentryShortId] = applyConverged(m, d, sibs)
      log(`  ${sibs.join('/')} -> converged: ${d.disposition} — ${why}`)
    } else if (d && d.decision === 'keep-split') {
      log(`  ${sibs.join('/')} -> kept split — ${why}`)
    } else {
      // cannot-converge (or a dead/invalid decision): escalate the whole cluster to a human.
      for (const m of members) replaced[m.sentryShortId] = escalate(m, why || 'Unresolved triage conflict.', sibs)
      log(`  ${sibs.join('/')} -> cannot converge: escalated cluster to human`)
    }
  }
  finalVerdicts = verdicts.map((v) => replaced[v.sentryShortId] || v)
}

log(`Done: ${finalVerdicts.length}/${ISSUES.length} verdict(s)${clusters.length ? `, ${clusters.length} cluster(s) reconciled` : ''}. Next: save to a file and run scripts/apply_review.py (omit --dry-run to write).`)
return finalVerdicts
