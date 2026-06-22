# Field Map

> **STATUS: LIVE** — fields created 2026-06-20 in Jira (global contexts). The REST field-write needs
> the numeric **field id** and, for select fields, the numeric **option id** (labels are not accepted).

## Fields

| Field name | `customfield_` id | Type | Context id |
|---|---|---|---|
| AI: Agent Suitability | `customfield_10975` | select | `11223` |
| AI: Value | `customfield_10976` | select | `11224` |
| AI: Effort | `customfield_10977` | select | `11225` |
| AI: Confidence | `customfield_10978` | select | `11226` |
| AI: Area | `customfield_10979` | select | `11227` |
| AI: Priority Score | `customfield_10980` | number (float) | `11228` |
| AI: Last Reviewed | `customfield_10981` | datetime | `11229` |

## Select options (label → option id)

**AI: Agent Suitability** (`customfield_10975`)
| label | option id |
|---|---|
| Agent-ready | `10846` |
| Agent-assisted | `10847` |
| Human-only | `10848` |
| Needs-info | `10849` |
| Not actionable | `10850` |

**AI: Value / AI: Effort / AI: Confidence** (each its own field — ids differ per field)
| label | Value (`10976`) | Effort (`10977`) | Confidence (`10978`) |
|---|---|---|---|
| High | `10851` | `10854` | `10857` |
| Medium | `10852` | `10855` | `10858` |
| Low | `10853` | `10856` | `10859` |

**AI: Area** (`customfield_10979`)
| label | option id |
|---|---|
| API | `10860` |
| Web Admin | `10861` |
| Flutter App | `10862` |
| Multiple | `10863` |
| Unknown | `10864` |

## Write payload reference

```jsonc
{"fields": {
  "customfield_10975": {"id": "10846"},   // AI: Agent Suitability = Agent-ready
  "customfield_10976": {"id": "10851"},   // AI: Value = High
  "customfield_10977": {"id": "10856"},   // AI: Effort = Low
  "customfield_10978": {"id": "10857"},   // AI: Confidence = High
  "customfield_10979": {"id": "10860"},   // AI: Area = API
  "customfield_10980": 300,                // AI: Priority Score (number; omit if unset)
  "customfield_10981": "2026-06-20T14:03:00.000+0200"  // AI: Last Reviewed (datetime)
}}
```
