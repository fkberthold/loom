# askuserquestion-option-cap hook

> PreToolUse hook that refuses an `AskUserQuestion` call carrying three
> or more authored options in one question, and names the diagnosis a
> third option carries.

## Why this exists

Closes loom-42cw.9, the gate half of D7 in the decision-routing design
cycle (`drawer_loom_decisions_97b8a01aa8d18d7a32e86c2d`).

D3 of that cycle caps an ask at two authored options. An alternative
earns its place only if you can describe someone who would actually take
it, and a third option usually cannot clear that bar. So when central
finds a third, it does not present three. It reads the count as a
signal.

There are two things the signal can mean. Either the problem needs more
research, or there is more than one problem. The first branch is where a
dispatched researcher fires. The second is loom's bead-splitting
heuristic applied to an option set.

That is why the refusal names the diagnosis rather than reporting a
count. A count tells the caller it broke a rule. The diagnosis tells it
which repair to make.

The evidence sits in the drawer. The short version is that padding an
options table is not inert. Across the 38 studies surveyed, the
attraction effect held in 4 of 5 pure numeric attribute matrices, which
is the shape an engineering options table takes. Frederick, Lee and
Baskin 2014 measured a repulsion effect on top of that, so a padded
option can move the choice away from the right answer instead of only
wasting attention.

## Why it gates rather than nudges

[Gate, don't advise](../explanation/gate-dont-advise.md) turns on one
question. Is a human supposed to weigh in? Nobody is supposed to weigh
in on whether three exceeds two, so this half of D7 gates.

The other half is judgment, and it does not gate. D1 and D2 decide what
reaches Frank at all. D4, D5 and D6 decide what a surviving ask carries.
Those ship as prose in `templates/rules/loom-conventions.md`, loom's one
owned template, under loom-42cw.10.

## What counts as an authored option

An authored option is an entry in a question's `options` array, which is
what the caller wrote:

```json
{"tool_name": "AskUserQuestion",
 "tool_input": {"questions": [
   {"question": "...", "header": "...", "multiSelect": false,
    "options": [{"label": "...", "description": "..."}]}]}}
```

The free-form escape hatch the harness offers the user is not counted.
It never reaches `tool_input`, and nobody authored it, so counting it
would charge the caller for a choice it did not make.

## The cap is per question, not per call

The hook takes the largest `options` array in the call and compares that
against the cap. A call asking two questions of two options each passes.

That reading is mine rather than the spec's. D7's L3 spec says "a call
carrying three or more authored options", which is ambiguous once a call
holds more than one question. I read it per question because D3 rests on
choice-set evidence, and a choice set is one question's option list. Two
questions of two are two decisions of two, and refusing them would gate
something D3 never spoke to. For the single-question shape, which is
almost every call, the two readings agree.

## What the hook checks

For each `AskUserQuestion` tool call:

1. `LOOM_ASKUSERQUESTION_OPTION_CAP_SKIP=1` (literal "1") → exit 0.
2. Empty stdin → exit 0.
3. `tool_name != "AskUserQuestion"` → exit 0.
4. Count the largest `options` array across `tool_input.questions`.
5. A payload the counter cannot read → exit 0.
6. Largest count of 2 or fewer → exit 0.
7. Otherwise → exit 2, naming the count and both diagnosis branches.

Steps 2, 3 and 5 all fail open. A gate that blocks on a payload it does
not understand stops work it was never meant to judge, and the option
cap is worth nothing if it makes the harness unusable on an unfamiliar
call shape.

## The refusal

```text
askuserquestion-option-cap: this call carries 3 authored options in a
single question. The cap is 2.

A third option is a diagnosis, not a style problem. It means one of two
things.

  1. The problem needs more research. Dispatch a researcher. Ask again
     with what comes back.
  2. There is more than one problem. Split it. Ask one question at a
     time.

Cut the set to 2 options. Then call again.

Rule: D3 and D7, drawer_loom_decisions_97b8a01aa8d18d7a32e86c2d.
Bypass: LOOM_ASKUSERQUESTION_OPTION_CAP_SKIP=1, set before launching claude.
```

## Counting the options

The shared `json_get` helper reads string scalars, and this hook needs an
array length, so it repeats the jq to python3 ladder locally rather than
bending `json_get` out of shape.

When neither binary resolves, the hook cannot prove a violation and
exits 0.

| Env var | Effect | Default |
|---|---|---|
| `LOOM_ASKUSERQUESTION_OPTION_CAP_SKIP` | Set to `1` to disable the hook | unset |
| `LOOM_JQ_BIN` | The jq binary the counter looks for | `jq` |
| `LOOM_PY_BIN` | The python3 binary it falls back to | `python3` |

The two binary overrides are test-only. They let
`lib/tests/askuserquestion-option-cap.test.sh` exercise the python3 rung
and the neither-available rung on a host that has both. Neither is a
global switch, because `json_get` resolves jq on its own.

The skip var matches the literal string `1` and nothing else, per
loom-b1l. `=yes`, `=true`, `=0` and empty are all rejected. Like every
hook-installed PreToolUse guard, it is read when `claude` forks, so set
it before launching rather than exporting mid-session.

## Registration

`settings.snippet.json` carries the hook under a `PreToolUse` matcher of
`AskUserQuestion`, and `install.sh` merges that into
`~/.claude/settings.json`. A hook that ships and symlinks but never gets
registered never runs, which is what `lib/tests/settings-parity.test.sh`
exists to catch (loom-kwkc). Run `./install.sh` after picking this up, or
the parity gate will report the drift.

## Lineage

- **Design source**: `drawer_loom_decisions_97b8a01aa8d18d7a32e86c2d`, D3
  and D7. Promoted from exploration
  `drawer_loom_decisions_0f717aebc52d7a069289b39b`.
- **Sibling**: loom-42cw.10 writes the nudge half into
  `templates/rules/loom-conventions.md`.
- **Pattern followed**: `hooks/skill-redirect.sh` matches a non-file tool
  by name and blocks with exit 2.
- **Same split one rung down**: claim-provenance's D4, gate the
  structure and nudge the claims. See
  [Claim provenance](../explanation/claim-provenance.md).
