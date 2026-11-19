# Findings format

Every reviewer returns **exactly one JSON object** and nothing else: no prose
before or after it, no Markdown fence. `review/bin/validate-findings` checks it.

```json
{
  "reviewer": "product | code | architect | security | devils-advocate",
  "model": "the model or agent you are, e.g. claude",
  "summary": "2-5 sentences: your overall read of the change from your angle",
  "findings": [
    {
      "id": "<reviewer>-<n>",
      "severity": "blocker | major | minor | nit",
      "confidence": "high | medium | low",
      "file": "path/from/repo/root or null for a whole-PR finding",
      "line": 12,
      "title": "one line",
      "evidence": "what in the code shows it: quote the line(s) or describe the path through the code",
      "suggestion": "what to do instead"
    }
  ],
  "extras": {}
}
```

- `line` is a line number in the **new** version of the file, or `null`.
- `id`s are unique within your output: `code-1`, `code-2`, ...
- An empty `findings` array is a valid, good answer when there is nothing real.

## Severity

| Severity  | Meaning |
|-----------|---------|
| `blocker` | Must not merge: wrong behaviour, data loss, security hole, breaks the build. |
| `major`   | Should be fixed before merge: likely bug, missing requirement, real design problem. |
| `minor`   | Worth fixing, fine to follow up: small risk, unclear code, missing test for an edge. |
| `nit`     | Taste or style. Usually dropped from the report. |

## Confidence

`high`: you traced it in the code. `medium`: likely, but depends on something
you couldn't fully see. `low`: a hunch worth a second look.

## `extras` by reviewer

**code, architect:** `{}`

**product:**

```json
{
  "card": "ABC-123",
  "ac_source": "card | inferred | none",
  "requirements": [
    {"requirement": "Export includes archived items",
     "status": "met | not_met | drift_documented | drift_undocumented",
     "where": "src/export.ts:40, or the PR description paragraph that explains the drift"}
  ]
}
```

`card` is `null` when there is no linked card. `ac_source` is `card` when
the card has an AC / Acceptance Criteria section, `inferred` when you derived
the criteria from the description, `none` when there was no card and you
used the PR description.

**security:**

```json
{
  "aikido": {
    "pr_check": "passed | failed | pending | missing | n/a",
    "scan": "clean | issues | not_scanned",
    "notes": "what the scan and PR check said, in a sentence or two"
  }
}
```

`pr_check` is `n/a` for a local branch.

**devils-advocate:** at most 3 alternatives.

```json
{
  "alternatives": [
    {"approach": "Fix it in the API layer instead",
     "strongest_argument": "One place instead of three callers",
     "why_pr_may_still_win": "The API is shared with a team that can't take the change this sprint"}
  ]
}
```

## Verifier output

The verifier returns a JSON array, one entry per finding it checked:

```json
[{"id": "code-1", "verdict": "confirmed | plausible | refuted", "reason": "one or two sentences"}]
```

`review/bin/apply-verdicts` drops `refuted` findings and tags the rest.
