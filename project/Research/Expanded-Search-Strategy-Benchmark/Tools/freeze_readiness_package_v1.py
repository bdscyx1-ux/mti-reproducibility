#!/usr/bin/env python3
"""Create and freeze the final Gate13R-AX2 readiness package manifest."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import stat
import sys
from typing import Any, Dict, List, Sequence


DESIGN_ID = "gate13r-ax2-shared32-b48-four-treatment-v1"


class FreezeError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise FreezeError(message)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def write_json_new(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"))
        stream.write(b"\n")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=pathlib.Path, required=True)
    parser.add_argument("--readiness", type=pathlib.Path, required=True)
    parser.add_argument("--readiness-sha256", required=True)
    parser.add_argument("--contract", type=pathlib.Path, required=True)
    parser.add_argument("--contract-sha256", required=True)
    parser.add_argument("--prompt", type=pathlib.Path, required=True)
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--freeze-receipt", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    try:
        root = args.project_root.resolve()
        readiness_path = args.readiness.resolve()
        contract_path = args.contract.resolve()
        prompt_path = args.prompt.resolve()
        require(sha256_file(readiness_path) == args.readiness_sha256.lower(), "Final-readiness SHA-256 mismatch.")
        require(sha256_file(contract_path) == args.contract_sha256.lower(), "Execution-contract SHA-256 mismatch.")
        readiness = load_json(readiness_path)
        contract = load_json(contract_path)
        require(readiness.get("status") == "FINAL-READINESS-PASS" and readiness.get("designId") == DESIGN_ID, "Final readiness does not pass for this design.")
        require(contract.get("status") == "FROZEN-NONEXECUTING" and contract.get("designId") == DESIGN_ID, "Execution contract status/design mismatch.")
        require(prompt_path.is_file(), "Formal authorization prompt is missing.")
        relative_paths = {
            binding["path"]
            for binding in contract["frozenPackageFiles"]
            if not pathlib.Path(binding["path"]).is_absolute()
        }
        relative_paths.update({
            "Research/Gate13R-AX2/Execution/v1/execution-contract.v3.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/compile/compile-receipt.v3.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/tool-selftests/structural-selftest.v1.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/tool-selftests/schedule-validation.v1.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/tool-selftests/p1-analysis-selftest.v1.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/tool-selftests/expected-failure-and-raw-rejection-test.v1.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/tool-selftests/formal-authorization-guard-test.v1.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/final-readiness.v1.json",
            "Research/Verification/Gate13R-AX2/precollection-readiness-v1/readiness-report.v1.md",
            "Research/Gate13R-AX2/Authorization/next-formal-collection-authorization-prompt.v1.md",
            "Research/Gate13R-AX2/Tools/build_execution_contract_v1.py",
            "Research/Gate13R-AX2/Tools/build_final_readiness_v1.py",
            "Research/Gate13R-AX2/Tools/run_expected_failure_test_v1.py",
            "Research/Gate13R-AX2/Tools/run_formal_authorization_guard_test_v1.py",
            "Research/Gate13R-AX2/Tools/freeze_readiness_package_v1.py",
        })
        entries: List[Dict[str, Any]] = []
        resolved_paths: List[pathlib.Path] = []
        for relative in sorted(relative_paths):
            path = (root / pathlib.PurePosixPath(relative)).resolve()
            require(path.is_relative_to(root) and path.is_file(), f"Readiness package file is missing/unsafe: {relative}")
            entries.append({"relativePath": relative, "sha256": sha256_file(path), "bytes": path.stat().st_size})
            resolved_paths.append(path)
        manifest = {
            "schemaVersion": 1,
            "artifactKind": "GATE13R-AX2-PRECOLLECTION-READINESS-PACKAGE-MANIFEST",
            "designId": DESIGN_ID,
            "status": "FROZEN",
            "createdAtUtc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            "finalReadinessSha256": args.readiness_sha256.lower(),
            "executionContractSha256": args.contract_sha256.lower(),
            "formalAuthorizationPromptSha256": sha256_file(prompt_path),
            "fileCount": len(entries),
            "files": entries,
            "formalCollectionAuthorized": False,
            "formalCollectionStarted": False,
        }
        manifest_path = args.manifest.resolve()
        write_json_new(manifest_path, manifest)
        freeze_receipt = {
            "schemaVersion": 1,
            "artifactKind": "GATE13R-AX2-PRECOLLECTION-READINESS-FREEZE",
            "designId": DESIGN_ID,
            "status": "READINESS-PACKAGE-IMMUTABLE",
            "frozenAtUtc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            "manifestPath": str(manifest_path),
            "manifestSha256": sha256_file(manifest_path),
            "manifestFileCount": len(entries),
            "finalReadinessSha256": args.readiness_sha256.lower(),
            "formalAuthorizationPromptSha256": sha256_file(prompt_path),
            "formalCollectionAuthorized": False,
            "formalCollectionStarted": False,
        }
        freeze_path = args.freeze_receipt.resolve()
        write_json_new(freeze_path, freeze_receipt)
        for path in resolved_paths + [manifest_path, freeze_path]:
            path.chmod(path.stat().st_mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)
        frozen_count = sum(1 for path in resolved_paths + [manifest_path, freeze_path] if not (path.stat().st_mode & stat.S_IWRITE))
        require(frozen_count == len(resolved_paths) + 2, "Not every readiness package file became read-only.")
        print(json.dumps({
            "status": "READINESS-PACKAGE-IMMUTABLE",
            "manifest": str(manifest_path),
            "manifestSha256": sha256_file(manifest_path),
            "freezeReceipt": str(freeze_path),
            "freezeReceiptSha256": sha256_file(freeze_path),
            "readOnlyFileCount": frozen_count,
            "formalCollectionStarted": False,
        }, sort_keys=True))
        return 0
    except (FreezeError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "FAIL", "errorType": type(exc).__name__, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
