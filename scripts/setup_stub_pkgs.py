#!/usr/bin/env python3
# TODO: Remove per #125 once sweagent >= 1.0.2
"""
Idempotently create minimal stub directories so that sweagent v1.0.1
does not blow up when CONFIG_DIR / TOOLS_DIR / TRAJ_DIR are missing.

If a future wheel already ships them (non-empty), we leave them untouched.

NOTE: This script can likely be removed once sweagent version > 1.0.1
is used, assuming upstream fixes the packaging to include these directories.
"""

from __future__ import annotations

import importlib.util as ilu
import pathlib as pl
import site
import sys
import textwrap


STUB_DIRS = ("config", "tools", "trajectories")


def _touch(path: pl.Path, content: str = "") -> None:
    """Create file only if absent **or** empty."""
    if not path.exists() or path.stat().st_size == 0:
        path.write_text(content)


def _ensure_runtime_dirs(base: pl.Path) -> None:
    for sub in STUB_DIRS:
        d = base / sub
        d.mkdir(parents=True, exist_ok=True)
        _touch(d / "__init__.py")
        if sub == "config":
            _touch(
                d / "default.yaml",
                textwrap.dedent(
                    """\
                    #############################
                    # Minimal placeholder config
                    #############################
                    agent:
                      name: placeholder
                    """
                ),
            )


def _ensure_enterprise_stub(base: pl.Path) -> None:
    ent = base / "enterprise"
    ent.mkdir(parents=True, exist_ok=True)
    _touch(ent / "__init__.py", "# stub enterprise package\n")

    hooks = ent / "enterprise_hooks"
    hooks.mkdir(exist_ok=True)
    _touch(hooks / "__init__.py", "# stub enterprise_hooks package\n")
    _touch(
        hooks / "session_handler.py",
        "class SessionHandler: ...\nclass ChatCompletionSession: ...\n",
    )


def main() -> None:
    spec = ilu.find_spec("sweagent")
    if spec is None or spec.origin is None:
        sys.exit("❌  sweagent not found on sys.path")

    pkg_dir = pl.Path(spec.origin).parent
    site_pkgs = pl.Path(site.getsitepackages()[0])

    # Let exceptions from helpers propagate directly
    for target in {pkg_dir.parent, site_pkgs}:
        _ensure_runtime_dirs(target)
        _ensure_enterprise_stub(target)

    print("✅  stub packages ensured; ready to import sweagent")


if __name__ == "__main__":
    main()
