#!/usr/bin/env python3
"""Create the attempt-2 versioned adapter stack from exact frozen parents.

This script is deliberately create-new and hash-gated.  It performs only the
mechanical version/path changes needed before the target files receive their
version-specific, reviewable additions.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Callable


ROOT = Path(r"H:\DDM_Final_Project")
OUT = ROOT / "Research/Verification/Gate13R_PR2_Formal_Attempt2/v1/base-derivation-summary.json"

SOURCES = {
    "command": (
        ROOT / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV2.cs",
        "af9156588bc259dfa8cafeec4adb82c93a2b07f5e2ae772b4b0fd4115dce28a8",
    ),
    "module": (
        ROOT / "Research/Gate13RPR2FormalExecutionV3.psm1",
        "5eaf15a3f1891d17849cf5c417aabaa03bcac7d25771e83ab905060b2db74b74",
    ),
    "wrapper": (
        ROOT / "Research/Run-Gate13RPR2FormalBlockV4.ps1",
        "30bf36239aaf321a4d454bf71f777a668476b1b962021d30ec3bb4d6abe25f54",
    ),
    "campaign": (
        ROOT / "Research/Run-Gate13RPR2FormalCampaignV4.ps1",
        "66821f7642a260a80a5ea30f3e45a4e93e4dbc0c78095a3bcf2800d86bf65b53",
    ),
}

TARGETS = {
    "command": ROOT / "Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV3.cs",
    "module": ROOT / "Research/Gate13RPR2FormalExecutionV4.psm1",
    "wrapper": ROOT / "Research/Run-Gate13RPR2FormalBlockV5.ps1",
    "campaign": ROOT / "Research/Run-Gate13RPR2FormalCampaignV5.ps1",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def replace_exact(text: str, old: str, new: str, count: int = 1) -> str:
    actual = text.count(old)
    if actual != count:
        raise RuntimeError(f"expected {count} occurrences, found {actual}: {old!r}")
    return text.replace(old, new)


def command_transform(text: str) -> str:
    text = replace_exact(
        text,
        "public static class Gate13RPR2FormalBatchCommandV2",
        "public static class Gate13RPR2FormalBatchCommandV3",
    )
    text = replace_exact(
        text,
        "            public double dynamicHandlingMillisecondsPerScheduledEvent;\n"
        "            public bool completed;",
        "            public double dynamicHandlingMillisecondsPerScheduledEvent;\n"
        "            public bool formalCampaign;\n"
        "            public bool completed;",
    )
    text = replace_exact(
        text,
        "                dynamicHandlingMillisecondsPerScheduledEvent = core.dynamicHandlingMillisecondsPerScheduledEvent,\n"
        "                completed = core.workloadCompleted",
        "                dynamicHandlingMillisecondsPerScheduledEvent = core.dynamicHandlingMillisecondsPerScheduledEvent,\n"
        "                formalCampaign = plan.formalCampaign,\n"
        "                completed = core.workloadCompleted",
    )
    return text


def identity(text: str) -> str:
    return text


def wrapper_transform(text: str) -> str:
    replacements = (
        ("Run-Gate13RPR2FormalBlockV4", "Run-Gate13RPR2FormalBlockV5"),
        ("Gate13RPR2FormalExecutionV3.psm1", "Gate13RPR2FormalExecutionV4.psm1"),
        ("Gate13R_RQAligned_S48H48\\v1", "Gate13R_RQAligned_S48H48\\v2"),
        ("Gate13RPR2FormalBatchCommandV2.Run", "Gate13RPR2FormalBatchCommandV3.Run"),
        (
            "gate13r-pr2-rq-aligned-s48-h48-formal-block-wrapper-summary-v4",
            "gate13r-pr2-rq-aligned-s48-h48-formal-block-wrapper-summary-v5",
        ),
    )
    for old, new in replacements:
        text = replace_exact(text, old, new)
    return text


def campaign_transform(text: str) -> str:
    replacements = (
        ("Run-Gate13RPR2FormalCampaignV4", "Run-Gate13RPR2FormalCampaignV5"),
        ("Gate13RPR2FormalExecutionV3.psm1", "Gate13RPR2FormalExecutionV4.psm1"),
        ("Gate13R_RQAligned_S48H48\\v1", "Gate13R_RQAligned_S48H48\\v2"),
        ("Gate13R_PR2_Formal_Execution_Status.v1.json", "Gate13R_PR2_Formal_Execution_Status.v2.json"),
        ("Run-Gate13RPR2FormalBlockV4.ps1", "Run-Gate13RPR2FormalBlockV5.ps1"),
        ("Gate13RPR2FormalBatchCommandV2.cs", "Gate13RPR2FormalBatchCommandV3.cs"),
    )
    for old, new in replacements:
        text = replace_exact(text, old, new)
    return text


TRANSFORMS: dict[str, Callable[[str], str]] = {
    "command": command_transform,
    "module": identity,
    "wrapper": wrapper_transform,
    "campaign": campaign_transform,
}


def atomic_create(path: Path, text: str) -> None:
    if path.exists():
        raise FileExistsError(f"create-new target exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    with temporary.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(text)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def main() -> None:
    if OUT.exists():
        raise FileExistsError(f"create-new evidence exists: {OUT}")
    records = []
    for role, (source, expected_hash) in SOURCES.items():
        actual = sha256(source)
        if actual != expected_hash:
            raise RuntimeError(f"frozen {role} hash mismatch: {actual}")
        target = TARGETS[role]
        text = source.read_text(encoding="utf-8")
        transformed = TRANSFORMS[role](text)
        atomic_create(target, transformed)
        records.append(
            {
                "role": role,
                "sourceRelativePath": source.relative_to(ROOT).as_posix(),
                "sourceSha256": actual,
                "targetRelativePath": target.relative_to(ROOT).as_posix(),
                "baseDerivedSha256": sha256(target),
                "sourceBytes": source.stat().st_size,
                "targetBytes": target.stat().st_size,
            }
        )
    summary = {
        "schemaVersion": 1,
        "summaryKind": "gate13r-pr2-attempt2-create-new-base-derivation-summary-v1",
        "status": "BASE-DERIVATION-COMPLETE-TARGET-ADDITIONS-PENDING",
        "records": records,
        "formalRootCreated": False,
        "unityStarted": False,
    }
    atomic_create(OUT, json.dumps(summary, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

