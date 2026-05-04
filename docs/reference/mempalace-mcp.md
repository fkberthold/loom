# MemPalace MCP tools

MemPalace is an upstream MCP server. The list below catalogues the 29
tools loom relies on via skills, subagents, and the recipe family.
For the full MemPalace reference, consult the upstream MemPalace
documentation and `mempalace_get_aaak_spec` for the diary dialect.

## High-frequency tools

```
mempalace_status              # palace overview at session start
mempalace_kg_stats            # KG entity/triple counts
mempalace_search              # semantic similarity over drawers
mempalace_kg_query            # structured S→P→O lookup
mempalace_kg_add              # add new fact
mempalace_add_drawer          # file decision drawer
mempalace_diary_write         # AAAK session summary
mempalace_diary_read          # recover own continuity
```

## Mid-frequency tools

```
mempalace_check_duplicate     # before add_drawer (prevents fragmentation)
mempalace_kg_timeline         # chronological story for entity
mempalace_kg_invalidate       # mark fact as no-longer-true
mempalace_get_drawer          # fetch single drawer by ID
mempalace_list_drawers        # paginated, optional wing/room filter
mempalace_update_drawer       # modify content or relocate
```

## Low-frequency / advanced tools

```
mempalace_traverse                    # BFS walk from room, auto-detects tunnels
mempalace_list_wings / list_rooms     # palace structure inspection
mempalace_get_taxonomy                # full hierarchy
mempalace_create_tunnel               # explicit cross-wing link
mempalace_follow_tunnels              # navigate explicit tunnels
mempalace_find_tunnels                # discover bridging rooms
mempalace_list_tunnels                # all explicit tunnels
mempalace_graph_stats                 # graph connectivity metrics
mempalace_memories_filed_away         # acknowledge silent checkpoint
mempalace_get_aaak_spec               # AAAK dialect reference
mempalace_hook_settings               # silent_save / desktop_toast flags
mempalace_reconnect                   # force HNSW index resync
mempalace_delete_drawer               # irreversible
mempalace_delete_tunnel               # remove explicit tunnel
```

## Architecture vocabulary

| Term | Definition |
|---|---|
| Wing | Project namespace (e.g., `hundred_acre_woods`, `loom`, `wing_claude-opus`) |
| Room | Topic/aspect within a wing (e.g., `decisions`, `diary`, `architecture`) |
| Drawer | Unit of verbatim content with markdown body, source-file metadata, and `added_by` metadata |
| Closet | Secondary index (`topic|entities|→drawer_ids`); not directly exposed but referenced by `kg_add(source_closet=...)` |
| Tunnel | Explicit cross-wing link, manually created via `create_tunnel` / `follow_tunnels` |
| KG | SQLite `knowledge_graph.sqlite3` with S→P→O triples (`valid_from`, `ended`, `source_closet`) |
| Diary | Per-agent personal wing (`wing_<agent_name>`, `room=diary`); AAAK-compressed entries |

For diary dialect specifics see [Glossary §AAAK](glossary.md#aaak).

## Loom-specific usage

| MemPalace surface | Loom integration |
|---|---|
| `mempalace_search`, `kg_query`, `diary_read` | `bug-family-researcher` subagent recipe; recipe phase A1 |
| `mempalace_add_drawer`, `kg_add`, `diary_write` | `/wrap-up`; recipe phase D3 |
| `mempalace_status`, `kg_stats` | `session-startup` skill |
