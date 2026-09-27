"""BLAKE3 file digests for the WS2 manufacture court (hand-authored).

ggen's sync receipt binds every output as `path -> BLAKE3 hex` (ggen-engine
sync.rs: payload `{ graph_hash, outputs: { path -> BLAKE3 } }`), not SHA-256.
Resolution order, all producing the same 32-byte default-mode digest:

1. the `blake3` Python package, when importable;
2. the `b3sum` CLI, when on PATH;
3. the pure-Python implementation below (BLAKE3 spec, default hash mode,
   32-byte output), which needs nothing beyond the standard library.

`backend()` names the one in use so receipts can record it; the environment
variable WS2_BLAKE3_BACKEND pins one explicitly.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

_IV = (
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
)
_PERM = (2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8)
_CHUNK_START, _CHUNK_END, _PARENT, _ROOT = 1, 2, 4, 8
_BLOCK, _CHUNK = 64, 1024
_M32 = 0xFFFFFFFF
BACKENDS = ("python-blake3", "b3sum", "pure-python")


def _schedules() -> list[tuple[int, ...]]:
    order = tuple(range(16))
    out = []
    for _ in range(7):
        out.append(order)
        order = tuple(order[p] for p in _PERM)
    return out


_SCHED = _schedules()


_G_LANES = (
    (0, 4, 8, 12),
    (1, 5, 9, 13),
    (2, 6, 10, 14),
    (3, 7, 11, 15),
    (0, 5, 10, 15),
    (1, 6, 11, 12),
    (2, 7, 8, 13),
    (3, 4, 9, 14),
)


def _compress(cv, m, counter, block_len, flags):
    v = [
        cv[0],
        cv[1],
        cv[2],
        cv[3],
        cv[4],
        cv[5],
        cv[6],
        cv[7],
        _IV[0],
        _IV[1],
        _IV[2],
        _IV[3],
        counter & _M32,
        (counter >> 32) & _M32,
        block_len,
        flags,
    ]
    for sc in _SCHED:
        # Column step then diagonal step: G over the 8 lanes.
        for lane, (a, b, c, d) in enumerate(_G_LANES):
            va = (v[a] + v[b] + m[sc[2 * lane]]) & _M32
            vd = v[d] ^ va
            vd = ((vd >> 16) | (vd << 16)) & _M32
            vc = (v[c] + vd) & _M32
            vb = v[b] ^ vc
            vb = ((vb >> 12) | (vb << 20)) & _M32
            va = (va + vb + m[sc[2 * lane + 1]]) & _M32
            vd ^= va
            vd = ((vd >> 8) | (vd << 24)) & _M32
            vc = (vc + vd) & _M32
            vb ^= vc
            v[a], v[b], v[c], v[d] = va, ((vb >> 7) | (vb << 25)) & _M32, vc, vd
    return (
        v[0] ^ v[8],
        v[1] ^ v[9],
        v[2] ^ v[10],
        v[3] ^ v[11],
        v[4] ^ v[12],
        v[5] ^ v[13],
        v[6] ^ v[14],
        v[7] ^ v[15],
    )


def _words(block: bytes) -> tuple[int, ...]:
    block = block.ljust(_BLOCK, b"\0")
    return tuple(int.from_bytes(block[i : i + 4], "little") for i in range(0, _BLOCK, 4))


def _chunk_output(chunk: bytes, counter: int):
    """Return (cv, words, block_len, flags) of the chunk's final block, un-compressed."""
    cv = _IV
    blocks = [chunk[i : i + _BLOCK] for i in range(0, len(chunk), _BLOCK)] or [b""]
    for idx, block in enumerate(blocks):
        flags = _CHUNK_START if idx == 0 else 0
        if idx == len(blocks) - 1:
            return cv, _words(block), len(block), flags | _CHUNK_END, counter
        cv = _compress(cv, _words(block), counter, _BLOCK, flags)
    raise AssertionError("unreachable")


def _parent(left, right):
    return _IV, tuple(left) + tuple(right), _BLOCK, _PARENT, 0


def _chaining(output) -> tuple[int, ...]:
    cv, words, block_len, flags, counter = output
    return _compress(cv, words, counter, block_len, flags)


def pure_python(data: bytes) -> str:
    chunks = [data[i : i + _CHUNK] for i in range(0, len(data), _CHUNK)] or [b""]
    stack: list[tuple[int, ...]] = []
    output = None
    for counter, chunk in enumerate(chunks):
        output = _chunk_output(chunk, counter)
        if counter == len(chunks) - 1:
            break
        cv = _chaining(output)
        total = counter + 1
        while total & 1 == 0:
            cv = _chaining(_parent(stack.pop(), cv))
            total >>= 1
        stack.append(cv)
    assert output is not None
    while stack:
        output = _parent(stack.pop(), _chaining(output))
    cv, words, block_len, flags, counter = output
    root = _compress(cv, words, counter, block_len, flags | _ROOT)
    return b"".join(w.to_bytes(4, "little") for w in root).hex()


def backend() -> str:
    forced = os.environ.get("WS2_BLAKE3_BACKEND", "")
    if forced:
        if forced not in BACKENDS:
            raise ValueError(f"WS2_BLAKE3_BACKEND={forced!r} not in {BACKENDS}")
        return forced
    try:
        import blake3  # noqa: F401

        return "python-blake3"
    except ImportError:
        pass
    if shutil.which("b3sum"):
        return "b3sum"
    return "pure-python"


def file_digest(path: Path, force: str | None = None) -> str:
    mode = force or backend()
    if mode == "python-blake3":
        import blake3

        return blake3.blake3(path.read_bytes()).hexdigest()
    if mode == "b3sum":
        out = subprocess.run(
            ["b3sum", "--no-names", str(path)], check=True, capture_output=True, text=True
        ).stdout
        return out.strip()
    return pure_python(path.read_bytes())
