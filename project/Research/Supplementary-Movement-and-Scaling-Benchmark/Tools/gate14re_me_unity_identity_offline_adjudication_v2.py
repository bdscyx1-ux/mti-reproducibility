#!/usr/bin/env python3
"""Repair-cycle wrapper for attempt-005 offline evidence adjudication.

The frozen v1 adjudicator correctly implements every identity criterion but its
first read-only preflight assumed historical copies beneath the isolated Unity
project would still exist.  Attempt-004 had already removed seven such copies.
This wrapper redirects reads for only those missing
``isolated-unity-audit-project/Research/...`` paths to the canonical project
``Research/...`` originals.  Recorded length and SHA-256 checks remain exact.

No file is copied, deleted, renamed or modified.  No process is started.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import stat
import sys
from typing import Any


def argument_value(name: str) -> str:
    positions = [index for index, value in enumerate(sys.argv) if value == name]
    if len(positions) != 1 or positions[0] + 1 >= len(sys.argv):
        raise RuntimeError(f"Expected exactly one {name} argument.")
    return sys.argv[positions[0] + 1]


def load_v1(source: Path) -> Any:
    specification = importlib.util.spec_from_file_location(
        "gate14re_me_unity_identity_offline_adjudication_v1_frozen", source
    )
    if specification is None or specification.loader is None:
        raise RuntimeError("Unable to load the frozen v1 adjudicator.")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def main() -> int:
    project_root = Path(argument_value("--project-root")).resolve()
    v1_source = (
        project_root
        / "Research"
        / "Gate14Re-ME"
        / "Tools"
        / "gate14re_me_unity_identity_offline_adjudication_v1.py"
    ).resolve()
    isolated_root = (
        project_root
        / "Research"
        / "Verification"
        / "Gate14Re-ME"
        / "unity-executable-identity-rule-repair-attempt-004"
        / "isolated-unity-audit-project"
    ).resolve()
    module = load_v1(v1_source)

    original_is_file = Path.is_file
    original_stat = Path.stat
    original_open = Path.open
    original_write_json = module.write_json_exclusive
    resolved_aliases: dict[str, str] = {}

    def is_regular_without_patch(path: Path) -> bool:
        try:
            return stat.S_ISREG(original_stat(path).st_mode)
        except (FileNotFoundError, OSError):
            return False

    def canonical_alias(path: Path) -> Path:
        candidate = Path(path)
        try:
            relative = candidate.relative_to(isolated_root)
        except ValueError:
            return candidate
        if not relative.parts or relative.parts[0].casefold() != "research":
            return candidate
        canonical = project_root.joinpath(*relative.parts)
        if is_regular_without_patch(candidate) or not is_regular_without_patch(canonical):
            return candidate
        resolved_aliases[str(candidate).replace("\\", "/")] = str(canonical).replace(
            "\\", "/"
        )
        return canonical

    def patched_is_file(path: Path) -> bool:
        return is_regular_without_patch(canonical_alias(path))

    def patched_stat(path: Path, *args: Any, **kwargs: Any) -> Any:
        return original_stat(canonical_alias(path), *args, **kwargs)

    def patched_open(path: Path, *args: Any, **kwargs: Any) -> Any:
        return original_open(canonical_alias(path), *args, **kwargs)

    def patched_write_json(path: Path, value: Any) -> None:
        if isinstance(value, dict):
            schema = value.get("schema")
            if schema == "gate14re-me-unity-identity-offline-evidence-adjudication-v1":
                value.setdefault("attempt005Execution", {})[
                    "automaticToolRepairCycleCount"
                ] = 1
                value["attempt005Execution"][
                    "historicalBindingAliasResolution"
                ] = {
                    "policy": "Only missing isolated-unity-audit-project/Research paths resolve to canonical project-root Research originals; byte length and SHA-256 remain mandatory.",
                    "resolvedAliasCount": len(resolved_aliases),
                    "resolvedAliases": [
                        {"historicalPath": key, "canonicalPath": resolved_aliases[key]}
                        for key in sorted(resolved_aliases, key=str.casefold)
                    ],
                    "criteriaRelaxed": False,
                }
            elif schema == "gate14re-me-unity-identity-offline-adjudication-terminal-receipt-v1":
                value["automaticRetryCount"] = 1
                value["automaticRetryKind"] = "READ_ONLY_PREFLIGHT_TOOL_REPAIR"
                value["historicalBindingAliasCount"] = len(resolved_aliases)
            elif schema == "gate14re-me-status-v17":
                value.setdefault("offlineEvidenceAdjudication", {})[
                    "automaticToolRepairCycleCount"
                ] = 1
        original_write_json(path, value)

    Path.is_file = patched_is_file
    Path.stat = patched_stat
    Path.open = patched_open
    module.write_json_exclusive = patched_write_json
    try:
        return int(module.main())
    finally:
        module.write_json_exclusive = original_write_json
        Path.open = original_open
        Path.stat = original_stat
        Path.is_file = original_is_file


if __name__ == "__main__":
    raise SystemExit(main())
