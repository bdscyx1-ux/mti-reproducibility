#!/usr/bin/env python3
"""Freeze or verify the isolated Gate14Re-ME typed-Parquet runtime.

This tool inventories dependency wheels and installed package bytes only. It
does not read or create any qualification input, schedule, measured root, lane,
formal observation, comparison, ranking, or winner.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Sequence


SCHEMA = "gate14re-me-typed-parquet-runtime-manifest-v1"
EXPECTED_RUNTIME_RELATIVE = Path("Research/Gate14Re-ME/Runtime/v1")
EXPECTED_PACKAGES_RELATIVE = EXPECTED_RUNTIME_RELATIVE / "python-packages"
EXPECTED_WHEELS_RELATIVE = EXPECTED_RUNTIME_RELATIVE / "wheels"
EXPECTED_VERSION = "25.0.1"
EXPECTED_IMPLEMENTATION_MANIFEST_SHA256 = "9bbefec10e28eb68ddcd25143b33a9a84b4047d4440c153e4a8ed86c62edcba4"


class RuntimeFreezeError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def within(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def project_relative(path: Path, project_root: Path) -> str:
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except ValueError as exc:
        raise RuntimeFreezeError(f"path is outside project root: {path}") from exc


def file_rows(root: Path, project_root: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for path in sorted((item for item in root.rglob("*") if item.is_file()), key=lambda item: item.as_posix().lower()):
        if path.suffix.lower() == ".pyc" or "__pycache__" in path.parts:
            raise RuntimeFreezeError(f"bytecode cache is prohibited in frozen runtime: {path}")
        rows.append(
            {
                "relativePath": project_relative(path, project_root),
                "sha256": sha256_file(path),
                "bytes": path.stat().st_size,
            }
        )
    return rows


def parse_metadata(metadata_path: Path) -> Mapping[str, str]:
    values: Dict[str, str] = {}
    for line in metadata_path.read_text(encoding="utf-8", errors="strict").splitlines():
        if line.startswith("Name: "):
            values["name"] = line[6:].strip()
        elif line.startswith("Version: "):
            values["version"] = line[9:].strip()
    return values


def exact_runtime_paths(project_root: Path, runtime_root: Path, wheels_root: Path, packages_root: Path) -> None:
    expected_runtime = (project_root / EXPECTED_RUNTIME_RELATIVE).resolve()
    expected_wheels = (project_root / EXPECTED_WHEELS_RELATIVE).resolve()
    expected_packages = (project_root / EXPECTED_PACKAGES_RELATIVE).resolve()
    if runtime_root.resolve() != expected_runtime or wheels_root.resolve() != expected_wheels or packages_root.resolve() != expected_packages:
        raise RuntimeFreezeError("runtime, wheel, or package path differs from the authorization-bound project-local path")
    if not within(runtime_root, project_root) or not within(wheels_root, runtime_root) or not within(packages_root, runtime_root):
        raise RuntimeFreezeError("runtime path containment failed")


def build_manifest(project_root: Path, runtime_root: Path, wheels_root: Path, packages_root: Path) -> Dict[str, Any]:
    exact_runtime_paths(project_root, runtime_root, wheels_root, packages_root)
    if not wheels_root.is_dir() or not packages_root.is_dir():
        raise RuntimeFreezeError("wheel or installed-package directory is missing")
    metadata_candidates = list(packages_root.glob("pyarrow-*.dist-info/METADATA"))
    if len(metadata_candidates) != 1:
        raise RuntimeFreezeError("exactly one installed pyarrow distribution metadata file is required")
    metadata = parse_metadata(metadata_candidates[0])
    if metadata.get("name", "").lower() != "pyarrow" or metadata.get("version") != EXPECTED_VERSION:
        raise RuntimeFreezeError("installed pyarrow identity/version mismatch")
    wheel_rows = file_rows(wheels_root, project_root)
    package_rows = file_rows(packages_root, project_root)
    pyarrow_wheels = [row for row in wheel_rows if Path(row["relativePath"]).name.lower().startswith(f"pyarrow-{EXPECTED_VERSION}-")]
    if len(pyarrow_wheels) != 1 or not pyarrow_wheels[0]["relativePath"].lower().endswith("cp312-cp312-win_amd64.whl"):
        raise RuntimeFreezeError("the exact CPython 3.12 Windows x86-64 pyarrow wheel is required")
    if not package_rows:
        raise RuntimeFreezeError("installed package inventory is empty")
    return {
        "schema": SCHEMA,
        "studyId": "Gate14Re-ME",
        "authorizationId": "gate14re-me-runtime-qualification-attempt-001",
        "status": "FROZEN_TYPED_PARQUET_RUNTIME",
        "version": 1,
        "createdAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "distribution": {"name": "pyarrow", "version": EXPECTED_VERSION, "pythonAbi": "cp312", "platform": "win_amd64"},
        "runtimeRootRelativePath": EXPECTED_RUNTIME_RELATIVE.as_posix(),
        "wheelRootRelativePath": EXPECTED_WHEELS_RELATIVE.as_posix(),
        "packageRootRelativePath": EXPECTED_PACKAGES_RELATIVE.as_posix(),
        "implementationManifestSha256": EXPECTED_IMPLEMENTATION_MANIFEST_SHA256,
        "wheelArtifacts": wheel_rows,
        "installedFiles": package_rows,
        "wheelArtifactCount": len(wheel_rows),
        "installedFileCount": len(package_rows),
        "bytecodeCacheFiles": 0,
        "readOnlyFreezeAppliedAfterManifestCreation": True,
        "evidenceBoundary": {
            "qualificationScheduleRows": 0,
            "qualificationInputs": 0,
            "anonymousIdentityMappings": 0,
            "qualificationObservations": 0,
            "algorithmLanes": 0,
            "formalObservations": 0,
            "formalAnalysisPerformed": False,
            "rankingOrWinnerComputed": False,
        },
    }


def write_json_atomic(path: Path, value: Mapping[str, Any]) -> None:
    if path.exists():
        raise RuntimeFreezeError("runtime manifest already exists; overwrite is prohibited")
    temporary = path.with_name(path.name + f".tmp.{os.getpid()}")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_json(path: Path) -> Dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise RuntimeFreezeError("runtime manifest must be a JSON object")
    return value


def verify_rows(rows: Iterable[Mapping[str, Any]], actual_root: Path, project_root: Path, label: str) -> None:
    expected: Dict[str, Mapping[str, Any]] = {}
    for row in rows:
        relative = str(row.get("relativePath", ""))
        if relative in expected:
            raise RuntimeFreezeError(f"duplicate {label} path: {relative}")
        expected[relative] = row
    actual = {project_relative(path, project_root): path for path in actual_root.rglob("*") if path.is_file()}
    if set(expected) != set(actual):
        raise RuntimeFreezeError(f"{label} file set mismatch")
    for relative, row in expected.items():
        path = actual[relative]
        if path.stat().st_size != int(row.get("bytes", -1)) or sha256_file(path) != row.get("sha256"):
            raise RuntimeFreezeError(f"{label} hash/size mismatch: {relative}")


def verify_manifest(project_root: Path, manifest_path: Path) -> Dict[str, Any]:
    manifest = read_json(manifest_path)
    if manifest.get("schema") != SCHEMA or manifest.get("status") != "FROZEN_TYPED_PARQUET_RUNTIME":
        raise RuntimeFreezeError("runtime manifest identity/status mismatch")
    if manifest.get("implementationManifestSha256") != EXPECTED_IMPLEMENTATION_MANIFEST_SHA256:
        raise RuntimeFreezeError("runtime manifest implementation binding mismatch")
    distribution = manifest.get("distribution", {})
    if distribution != {"name": "pyarrow", "version": EXPECTED_VERSION, "pythonAbi": "cp312", "platform": "win_amd64"}:
        raise RuntimeFreezeError("runtime distribution binding mismatch")
    runtime_root = (project_root / EXPECTED_RUNTIME_RELATIVE).resolve()
    wheels_root = (project_root / EXPECTED_WHEELS_RELATIVE).resolve()
    packages_root = (project_root / EXPECTED_PACKAGES_RELATIVE).resolve()
    exact_runtime_paths(project_root, runtime_root, wheels_root, packages_root)
    verify_rows(manifest.get("wheelArtifacts", []), wheels_root, project_root, "wheel")
    verify_rows(manifest.get("installedFiles", []), packages_root, project_root, "installed package")
    if int(manifest.get("wheelArtifactCount", -1)) != len(manifest.get("wheelArtifacts", [])):
        raise RuntimeFreezeError("wheel artifact count mismatch")
    if int(manifest.get("installedFileCount", -1)) != len(manifest.get("installedFiles", [])):
        raise RuntimeFreezeError("installed-file count mismatch")
    if int(manifest.get("bytecodeCacheFiles", -1)) != 0:
        raise RuntimeFreezeError("bytecode cache count must be zero")
    return manifest


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    freeze = subparsers.add_parser("freeze")
    verify = subparsers.add_parser("verify")
    for command in (freeze, verify):
        command.add_argument("--project-root", required=True)
        command.add_argument("--manifest", required=True)
    freeze.add_argument("--runtime-root", required=True)
    freeze.add_argument("--wheels-root", required=True)
    freeze.add_argument("--packages-root", required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        project_root = Path(args.project_root).resolve()
        manifest_path = Path(args.manifest).resolve()
        if manifest_path != (project_root / EXPECTED_RUNTIME_RELATIVE / "typed-parquet-runtime-manifest.v1.json").resolve():
            raise RuntimeFreezeError("runtime manifest path differs from the frozen path")
        if args.command == "freeze":
            manifest = build_manifest(
                project_root,
                Path(args.runtime_root).resolve(),
                Path(args.wheels_root).resolve(),
                Path(args.packages_root).resolve(),
            )
            write_json_atomic(manifest_path, manifest)
        else:
            manifest = verify_manifest(project_root, manifest_path)
        print(json.dumps({
            "schema": "gate14re-me-typed-parquet-runtime-freeze-tool-result-v1",
            "status": "PASS_TYPED_PARQUET_RUNTIME_FROZEN" if args.command == "freeze" else "PASS_TYPED_PARQUET_RUNTIME_VERIFIED",
            "manifestSha256": sha256_file(manifest_path),
            "wheelArtifactCount": manifest["wheelArtifactCount"],
            "installedFileCount": manifest["installedFileCount"],
            "qualificationObservationCount": 0,
            "algorithmLanes": 0,
        }, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        print(json.dumps({"schema": "gate14re-me-typed-parquet-runtime-freeze-tool-result-v1", "status": "FAIL_CLOSED", "reason": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
