#!/usr/bin/env python3
"""Algorithm-free known-answer tests for the Gate14Re-ME formal ST v5 package.

This program never creates formal study inputs, never invokes Unity, and never
executes a navigation algorithm.  It exercises only package plumbing:
streaming typed-Parquet round-trip, tamper/type fail-closed behavior, strict
process-ledger ordering, and static presence of the no-resume/no-top-up policy.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List


SCHEMA = "gate14re-me-formal-st-package-known-answer-terminal-v5"
STATUS = "PASS_FORMAL_ST_V5_PACKAGE_KNOWN_ANSWER_NO_FORMAL_EXECUTION"


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_jsonl(path: Path, rows: Iterable[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(canonical_json(row) + "\n")


def load_module(path: Path) -> Any:
    spec = importlib.util.spec_from_file_location("gate14re_me_formal_st_acceptance_v5", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load acceptance module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def validate_process_rows(rows: List[Dict[str, Any]], expected: int) -> None:
    require(len(rows) == expected, "process-ledger cardinality mismatch")
    for index, row in enumerate(rows):
        require(row.get("schema") == "gate14re-me-formal-st-process-ledger-row-v5", "ledger schema mismatch")
        require(row.get("state") == "EXITED_ZERO_TRUSTED_IDENTITY", "untrusted process state")
        require(row.get("exitCode") == 0, "nonzero process exit")
        require(row.get("ordinal") == index, "process ordinals are not strict and contiguous")


def expect_failure(label: str, action: Any, results: List[Dict[str, Any]]) -> None:
    try:
        action()
    except Exception as exc:  # Fail-closed behavior is the subject of this KAT.
        results.append({"test": label, "status": "PASS", "observedFailureType": type(exc).__name__})
        return
    raise RuntimeError(f"negative known-answer test did not fail closed: {label}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--pyarrow-root", required=True)
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    output_root = Path(args.output_root).resolve()
    pyarrow_root = Path(args.pyarrow_root).resolve()
    acceptance_path = project_root / "Research/Gate14Re-ME/Tools/gate14re_me_formal_st_acceptance_v5.py"
    supervisor_path = project_root / "Research/Gate14Re-ME/Execution/v5/Run-Gate14ReMEFormalST.v5_0.ps1"
    require(acceptance_path.is_file(), "formal acceptance tool is missing")
    require(supervisor_path.is_file(), "formal supervisor is missing")
    require(not output_root.exists(), "known-answer output root must be new")
    output_root.mkdir(parents=True, exist_ok=False)

    module = load_module(acceptance_path)
    pa, pq, pyarrow_version = module.import_pyarrow(pyarrow_root)
    results: List[Dict[str, Any]] = []

    raw_root = output_root / "fixture-raw"
    source = raw_root / "tables" / "operations.raw.v5.jsonl"
    rows = [
        {"recordId": "fixture-a:operation:0", "inputId": "fixture-a", "sequence": 0, "value": 1.25, "ok": True},
        {"recordId": "fixture-a:operation:1", "inputId": "fixture-a", "sequence": 1, "value": 2.5, "ok": False},
        {"recordId": "fixture-a:operation:2", "inputId": "fixture-a", "sequence": 2, "value": None, "ok": True},
    ]
    write_jsonl(source, rows)
    relative = source.relative_to(raw_root).as_posix()
    sealed = {relative: {"bytes": source.stat().st_size, "sha256": sha256_file(source)}}
    profile = module.first_pass_profile(
        raw_root,
        "operations",
        {"requiredFields": ["recordId", "inputId", "sequence", "value", "ok"]},
        [source],
        sealed,
        {},
        {"d3": set(), "event": set(), "empty": set()},
    )
    parquet_path = output_root / "round-trip" / "operations.parquet"
    built = module.write_parquet_streaming(raw_root, profile, parquet_path, 2, pa, pq)
    verified = module.verify_parquet_streaming(profile, parquet_path, built, 2, pa, pq)
    require(verified.get("roundTripPass") is True and verified.get("rows") == len(rows), "typed Parquet round-trip failed")
    results.append({"test": "typed-parquet-complete-value-type-order-round-trip", "status": "PASS", "rows": len(rows)})

    tampered = output_root / "tampered" / "operations.parquet"
    tampered.parent.mkdir(parents=True, exist_ok=False)
    shutil.copy2(parquet_path, tampered)
    with tampered.open("r+b") as handle:
        handle.seek(-1, 2)
        final = handle.read(1)
        handle.seek(-1, 2)
        handle.write(bytes([final[0] ^ 0xFF]))
    expect_failure(
        "tampered-parquet-fails-closed",
        lambda: module.verify_parquet_streaming(profile, tampered, built, 2, pa, pq),
        results,
    )

    changed_root = output_root / "type-change-raw"
    changed_source = changed_root / "operations.raw.v5.jsonl"
    write_jsonl(changed_source, rows[:2])
    changed_relative = changed_source.relative_to(changed_root).as_posix()
    changed_seal = {changed_relative: {"bytes": changed_source.stat().st_size, "sha256": sha256_file(changed_source)}}
    changed_profile = module.first_pass_profile(
        changed_root,
        "operations",
        {"requiredFields": ["recordId", "inputId", "sequence", "value", "ok"]},
        [changed_source],
        changed_seal,
        {},
        {"d3": set(), "event": set(), "empty": set()},
    )
    bad_rows = list(rows[:2])
    bad_rows[1] = dict(bad_rows[1])
    bad_rows[1]["sequence"] = "one"
    write_jsonl(changed_source, bad_rows)
    expect_failure(
        "between-pass-scalar-type-change-fails-closed",
        lambda: module.write_parquet_streaming(
            changed_root, changed_profile, output_root / "type-change-parquet" / "operations.parquet", 2, pa, pq
        ),
        results,
    )

    valid_ledger = [
        {
            "schema": "gate14re-me-formal-st-process-ledger-row-v5",
            "state": "EXITED_ZERO_TRUSTED_IDENTITY",
            "exitCode": 0,
            "ordinal": index,
        }
        for index in range(5)
    ]
    validate_process_rows(valid_ledger, 5)
    results.append({"test": "strict-contiguous-trusted-zero-exit-ledger", "status": "PASS", "rows": 5})
    broken_ledger = [dict(row) for row in valid_ledger]
    broken_ledger[3]["ordinal"] = 4
    expect_failure("duplicate-or-skipped-ordinal-fails-closed", lambda: validate_process_rows(broken_ledger, 5), results)
    broken_state = [dict(row) for row in valid_ledger]
    broken_state[2]["state"] = "EXITED_ZERO_UNTRUSTED_IDENTITY"
    expect_failure("untrusted-process-identity-fails-closed", lambda: validate_process_rows(broken_state, 5), results)

    supervisor_text = supervisor_path.read_text(encoding="utf-8-sig")
    required_policy_markers = [
        "formalCollectionAuthorized",
        "formalAnalysisAuthorized",
        "mqAuthorized",
        "mtAuthorized",
        "process-ledger.raw.v5.jsonl",
        "replacement-ledger.raw.v5.jsonl",
        "retry/resume/overwrite are prohibited.",
        "Measured root already exists",
    ]
    missing_markers = [marker for marker in required_policy_markers if marker not in supervisor_text]
    require(not missing_markers, f"formal supervisor is missing policy markers: {missing_markers}")
    results.append({"test": "static-no-resume-no-top-up-and-scope-gates", "status": "PASS"})

    receipt = {
        "schema": SCHEMA,
        "status": STATUS,
        "projectRoot": project_root.as_posix(),
        "acceptanceTool": {
            "relativePath": acceptance_path.relative_to(project_root).as_posix(),
            "sha256": sha256_file(acceptance_path),
        },
        "supervisor": {
            "relativePath": supervisor_path.relative_to(project_root).as_posix(),
            "sha256": sha256_file(supervisor_path),
        },
        "pyarrow": {"version": pyarrow_version, "root": pyarrow_root.as_posix()},
        "tests": results,
        "boundaries": {
            "formalInputsCreated": 0,
            "formalScheduleRowsCreated": 0,
            "formalCollectionStarted": False,
            "formalAnalysisStarted": False,
            "mqStarted": False,
            "mtStarted": False,
            "algorithmsInstantiated": 0,
        },
    }
    receipt_path = output_root / "terminal-receipt.v5.json"
    write_json(receipt_path, receipt)
    print(canonical_json({"status": STATUS, "receipt": str(receipt_path), "sha256": sha256_file(receipt_path)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
