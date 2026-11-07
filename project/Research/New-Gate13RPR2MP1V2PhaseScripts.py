#!/usr/bin/env python3
"""Mechanically derive MP1 v2 Phase-A freeze and Phase-B analysis scripts."""

from __future__ import annotations

import hashlib
import os
import tempfile
from pathlib import Path


SOURCES = {
    "Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV1.py": "87861378c94c93a8a6c91915bb6b5e919746c4dedb287b53f710a56e7733964d",
    "Research/Analyze-Gate13RPR2MemoryPolicyPilotV1.py": "65b65ede6f4dfd32f5c93494aea9809950c0c797b86d8a87058f621dd2b75b4b",
}


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def create(path: Path, text: str) -> None:
    if path.exists():
        raise FileExistsError(path)
    fd, temp = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-phase-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(text.encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    for relative, expected in SOURCES.items():
        if digest(project / relative) != expected:
            raise RuntimeError(f"Frozen source hash mismatch: {relative}")

    freeze_source = project / "Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV1.py"
    freeze = freeze_source.read_text(encoding="utf-8-sig")
    old = '    if read_json(receipt_path).get("measuredPilotAuthorized") is not True:\n        raise RuntimeError("Pilot execution receipt is not authorized")'
    new = (
        '    receipt = read_json(receipt_path)\n'
        '    config = read_json(config_path)\n'
        '    if receipt.get("receiptKind") != "gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v2" or receipt.get("measuredPilotAuthorized") is not True:\n'
        '        raise RuntimeError("Pilot v2 execution receipt is not authorized")\n'
        '    if config.get("configId") != "gate13r-pr2-mp1-targeted-memory-pilot-config-v2":\n'
        '        raise RuntimeError("Pilot v2 config identity mismatch")'
    )
    if old not in freeze:
        raise RuntimeError("Freeze authorization anchor is absent")
    freeze = freeze.replace(old, new)
    for old_id, new_id in {
        "gate13r-pr2-mp1-immutable-raw-tree-manifest-v1": "gate13r-pr2-mp1-immutable-raw-tree-manifest-v2",
        "gate13r-pr2-mp1-raw-execution-manifest-v1": "gate13r-pr2-mp1-raw-execution-manifest-v2",
        "gate13r-pr2-mp1-pilot-raw-freeze-receipt-v1": "gate13r-pr2-mp1-pilot-raw-freeze-receipt-v2",
        ".g13rpr2-mp1-freeze-": ".g13rpr2-mp1-v2-freeze-",
    }.items():
        if old_id not in freeze:
            raise RuntimeError(f"Freeze replacement anchor absent: {old_id}")
        freeze = freeze.replace(old_id, new_id)
    freeze_header = f'# Mechanically derived from Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV1.py; SHA-256 {SOURCES["Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV1.py"]}.\n'
    freeze_target = project / "Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV2.py"
    create(freeze_target, freeze_header + freeze)

    analysis_source = project / "Research/Analyze-Gate13RPR2MemoryPolicyPilotV1.py"
    analysis = analysis_source.read_text(encoding="utf-8-sig")
    old_guard = '    if set(freeze_receipt.get("statusTokens", [])) != required_status or freeze_receipt.get("allRawFilesReadOnly") is not True:\n        raise RuntimeError("Valid immutable Phase-A receipt is required")'
    new_guard = (
        '    if set(freeze_receipt.get("statusTokens", [])) != required_status or freeze_receipt.get("allRawFilesReadOnly") is not True:\n'
        '        raise RuntimeError("Valid immutable Phase-A receipt is required")\n'
        '    if freeze_receipt.get("receiptKind") != "gate13r-pr2-mp1-pilot-raw-freeze-receipt-v2":\n'
        '        raise RuntimeError("MP1 v2 raw-freeze receipt identity mismatch")'
    )
    if old_guard not in analysis:
        raise RuntimeError("Analysis Phase-A guard anchor is absent")
    analysis = analysis.replace(old_guard, new_guard)
    for old_id, new_id in {
        "gate13r-pr2-mp1-stage-separated-memory-diagnostic-analysis-v1": "gate13r-pr2-mp1-stage-separated-memory-diagnostic-analysis-v2",
        "gate13r-pr2-mp1-forward-memory-policy-decision-matrix-v1": "gate13r-pr2-mp1-forward-memory-policy-decision-matrix-v2",
        "gate13r-pr2-mp1-analysis-evidence-manifest-v1": "gate13r-pr2-mp1-analysis-evidence-manifest-v2",
        ".g13rpr2-mp1-analysis-": ".g13rpr2-mp1-v2-analysis-",
    }.items():
        if old_id not in analysis:
            raise RuntimeError(f"Analysis replacement anchor absent: {old_id}")
        analysis = analysis.replace(old_id, new_id)
    analysis_header = f'# Mechanically derived from Research/Analyze-Gate13RPR2MemoryPolicyPilotV1.py; SHA-256 {SOURCES["Research/Analyze-Gate13RPR2MemoryPolicyPilotV1.py"]}.\n'
    analysis_target = project / "Research/Analyze-Gate13RPR2MemoryPolicyPilotV2.py"
    create(analysis_target, analysis_header + analysis)

    print(f"Research/Freeze-Gate13RPR2MemoryPolicyPilotRawV2.py|{digest(freeze_target)}")
    print(f"Research/Analyze-Gate13RPR2MemoryPolicyPilotV2.py|{digest(analysis_target)}")


if __name__ == "__main__":
    main()
