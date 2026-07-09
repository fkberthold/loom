"""memory-server/conftest.py — ensures the `mcp_server` package (a
sibling of tests/) is importable regardless of how pytest is invoked.

The project constitution's canonical test command
(`.venv/bin/pytest tests/ -v`) runs pytest via its console-script
entry point, which does NOT add the current working directory to
sys.path (unlike `python -m pytest`, which does). Without this file,
pytest's default rootless import mode would only add tests/'s own
parent directory for test-module imports, leaving `import mcp_server`
unresolved. Pytest auto-discovers and imports conftest.py files before
collecting sibling/child test modules, and — per that same rootless
import-mode rule — inserts THIS file's directory (memory-server/,
which has no __init__.py) onto sys.path to import it. The explicit
sys.path insert below is a belt-and-suspenders guarantee that isn't
solely dependent on that heuristic.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
