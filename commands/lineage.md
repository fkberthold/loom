---
description: "Surface prior art for a topic across MemPalace + beads in a single ad-hoc lookup. Runs mempalace_search + mempalace_kg_query + bd memories + bd search in parallel and summarises. Use when you suspect a bug or design question has prior art but don't know where it lives."
disable-model-invocation: true
---

The user supplied a topic as the argument (a bead title fragment, a
function name, an error message, or a freeform symptom phrase). Surface
prior art across all four memory layers.

Dispatch the `bug-family-researcher` subagent with the topic as the
"bead title or symptom description" input. The subagent will run:

1. `mempalace_search` for the topic + project decisions.
2. `mempalace_kg_query` for any named entities in the topic.
3. `mempalace_diary_read("claude-opus", 5)` for introspective context.
4. `bd memories <topic-keyword>` for project tribal facts.
5. `bd search <topic-keyword>` for related closed beads.

Return the subagent's structured prior-art report verbatim.

If the topic doesn't map to a clear bead and the search returns
"no close prior art found", say so explicitly — that's a real signal
that the topic is novel territory.
