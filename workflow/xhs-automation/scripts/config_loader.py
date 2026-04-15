"""Shared runtime env loader for the shareable XHS automation bundle."""

import os
from pathlib import Path


def _parse_line(line):
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        return None, None

    key, value = stripped.split("=", 1)
    key = key.strip()
    value = value.strip()
    if not key:
        return None, None

    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]

    value = os.path.expandvars(os.path.expanduser(value))
    return key, value


def load_runtime_env():
    """Load config/runtime.env into os.environ if present."""
    base_dir = Path(__file__).resolve().parent.parent
    env_path = os.environ.get("XHS_RUNTIME_ENV")
    candidates = []

    if env_path:
        candidates.append(Path(os.path.expandvars(os.path.expanduser(env_path))))

    candidates.append(base_dir / "config" / "runtime.env")

    for path in candidates:
        if not path.exists():
            continue

        for raw in path.read_text(encoding="utf-8").splitlines():
            key, value = _parse_line(raw)
            if key:
                os.environ.setdefault(key, value)
        return str(path)

    return None
