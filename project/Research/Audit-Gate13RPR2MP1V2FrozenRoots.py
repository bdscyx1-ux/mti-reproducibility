#!/usr/bin/env python3
"""Read-only canonical identity audit for the frozen MP1 v1 and formal attempt-2 roots."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


EXPECTED = {
    "pilotV1": {
        "path": r"H:\DDM_Final_Project\Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1",
        "fileCount": 5,
        "rawBytes": 5247,
        "canonicalTreeSha256": "a1f427a74a3a211778fa36d95f1a83b2d182c8f035e7d4970248274aeb91a265",
        "canonicalTreeContractId": "mp1-pilot-v1-pipe-delimited-no-final-lf-v1",
    },
    "formalAttempt2": {
        "path": r"H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v2",
        "fileCount": 28020,
        "rawBytes": 8536611302,
        "canonicalTreeSha256": "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e",
        "canonicalTreeContractId": "gate13r-pr2-attempt2-ordinal-tab-final-lf-v2",
    },
}


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_identity(root: Path, contract_id: str) -> dict[str, Any]:
    files = sorted((item for item in root.rglob("*") if item.is_file()), key=lambda item: item.relative_to(root).as_posix())
    rows: list[tuple[str, int, str]] = []
    total = 0
    readonly = 0
    for path in files:
        relative = path.relative_to(root).as_posix()
        size = path.stat().st_size
        digest = file_hash(path)
        rows.append((relative, size, digest.lower()))
        total += size
        if path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY:
            readonly += 1
    if contract_id == "mp1-pilot-v1-pipe-delimited-no-final-lf-v1":
        # Frozen MP1 pilot-v1 preservation identity: LF between pipe-delimited
        # records and no LF after the final record.
        payload = "\n".join(f"{relative}|{size}|{digest}" for relative, size, digest in rows).encode("utf-8")
    elif contract_id == "gate13r-pr2-attempt2-ordinal-tab-final-lf-v2":
        # Frozen formal-attempt-2 corrected canonical-order contract:
        # Python/Unicode ordinal path ordering and a TAB-delimited line ending
        # in LF for every file, including the final file.
        payload = "".join(f"{relative}\t{size}\t{digest}\n" for relative, size, digest in rows).encode("utf-8")
    else:
        raise ValueError(f"Unsupported canonical tree contract: {contract_id}")
    canonical = hashlib.sha256(payload).hexdigest()
    return {
        "absolutePath": str(root),
        "fileCount": len(files),
        "rawBytes": total,
        "canonicalTreeSha256": canonical,
        "canonicalTreeContractId": contract_id,
        "readOnlyFileCount": readonly,
        "allFilesReadOnly": readonly == len(files),
    }


def atomic_create(path: Path, value: Any) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".g13rpr2-mp1-v2-frozen-audit-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write((json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8"))
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    actual = {
        name: tree_identity(Path(spec["path"]).resolve(), spec["canonicalTreeContractId"])
        for name, spec in EXPECTED.items()
    }
    checks = []
    for name, expected in EXPECTED.items():
        value = actual[name]
        for field in ("fileCount", "rawBytes", "canonicalTreeSha256"):
            checks.append({"id": f"{name}-{field}", "passed": value[field] == expected[field], "expected": expected[field], "actual": value[field]})
        checks.append({
            "id": f"{name}-canonicalTreeContractId",
            "passed": value["canonicalTreeContractId"] == expected["canonicalTreeContractId"],
            "expected": expected["canonicalTreeContractId"],
            "actual": value["canonicalTreeContractId"],
        })
        checks.append({"id": f"{name}-all-read-only", "passed": value["allFilesReadOnly"] is True, "expected": True, "actual": value["allFilesReadOnly"]})
    result = {
        "schemaVersion": 1,
        "auditKind": "gate13r-pr2-mp1-v2-frozen-roots-postvalidation-audit-v1",
        "capturedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "roots": actual,
        "checks": checks,
        "pilotV2RootExists": Path(r"H:\DDM_Final_Project\Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2").exists(),
        "formalAttempt3RootExists": Path(r"H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v3").exists(),
        "formalAttempt3ReceiptExists": Path(r"H:\DDM_Final_Project\Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json").exists(),
    }
    result["passed"] = all(item["passed"] for item in checks) and not result["pilotV2RootExists"] and not result["formalAttempt3RootExists"] and not result["formalAttempt3ReceiptExists"]
    atomic_create(Path(args.output).resolve(), result)
    print(json.dumps({"passed": result["passed"], "output": str(Path(args.output).resolve()), "roots": actual}, sort_keys=True))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
