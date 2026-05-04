# Glossary

## AAAK

Compressed memory dialect MemPalace uses for diary entries
(approximately 30× compression). Format:
`KEY:value|KEY:value|⭐⭐⭐`. Three-letter capitalised entity codes,
`*action*` emotion markers, pipe-separated fields. Read naturally;
expand entity codes mentally. Spec retrievable via
`mempalace_get_aaak_spec`.

## Bead

A beads issue (`bd` CLI tracker).

## Closet

MemPalace secondary index (`topic|entities|→drawer_ids`). Greedily
packed to approximately 1500 characters. Not directly exposed;
referenced by `kg_add(source_closet=…)`.

## Drawer

Unit of MemPalace content. Carries `wing` / `room` / `source_file`
metadata.

## Family

A class of related bugs sharing a fix pattern (e.g.,
classifier-validator-demotion: `huu.7.1`, `huu.15.2`, `huu.19.3`,
`0qw`).

## HAW

Hundred Acre Woods. Frank's primary project; historical source of
the workflow-infrastructure design captured in MemPalace drawer
"WORKFLOW INFRASTRUCTURE PLAN".

## KG

MemPalace knowledge graph. SQLite-backed S→P→O triples with
`valid_from` / `ended` timestamps.

## Loom

This repository. Workflow-infrastructure package: skills, slash
commands, subagents, hooks, helpers, and settings snippets installed
into `~/.claude/`.

## MCP

Model Context Protocol. MemPalace exposes 29 MCP tools.

## Recipe

An activity-shaped workflow (`bugfix-a-bead`, `feature-a-bead`,
`refactor-a-bead`, `research-a-bead`, `cleanup-a-bead`,
`docs-a-bead`) that supplies its own variable middle and defers to
`bead-lifecycle-shell` for the surrounding phases.

## Room

Topic or aspect within a MemPalace wing (e.g., `decisions`, `diary`).

## Subagent

Isolated worker with its own context that returns a reviewable
summary. Loom ships four: `bug-family-researcher`, `drawer-author`,
`kg-relationship-extractor`, `project-onboarder`.

## Tunnel

Explicit cross-wing link in MemPalace.

## Wing

Project namespace in MemPalace.

## Wisp

Ephemeral beads molecule (no audit trail; deleted after work).
