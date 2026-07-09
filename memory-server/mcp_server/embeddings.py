"""mcp_server/embeddings.py — embedding model + Dolt VECTOR literal
helpers.

Uses all-MiniLM-L6-v2 via sentence-transformers (384-dim), matching
schema.sql's `embedding VECTOR(384)` column and the SAME model used
throughout this project's benchmarking lineage (SPIKE-1/loom-zu91,
loom-40ec.3, loom-40ec.7) — see the loom-40ec.4.1 bead description's
"Embedding model convention" note.

The model is loaded lazily and cached at module scope: loading it
costs real time (model weights + tokenizer init), and a stdio MCP
server process is long-lived, so that cost should be paid once per
process, not once per tool call.
"""
from __future__ import annotations

from typing import Iterable

MODEL_NAME = "all-MiniLM-L6-v2"

_model = None


def _get_model():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer

        _model = SentenceTransformer(MODEL_NAME)
    return _model


def embed(text: str) -> list[float]:
    """Return a 384-dim embedding for `text` as a plain list of floats."""
    model = _get_model()
    vec = model.encode(text)
    return vec.tolist()


def vector_literal(vec: Iterable[float]) -> str:
    """Format a vector as the `[0.1,0.2,...]` string literal Dolt's
    `string_to_vector()` expects.

    A bare string/JSON-array literal does NOT implicitly convert to
    the `vector` column type (verified — raises "value of type string
    cannot be converted to 'vector' type"; see schema.sql's NOTE and
    tests/test_memory_server.py's `_vec_literal()` helper for the same
    pattern this mirrors).
    """
    return "[" + ",".join(f"{x:.6f}" for x in vec) + "]"
