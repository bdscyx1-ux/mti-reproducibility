#!/usr/bin/env python3
"""Build and verify the Gate14Re-ME formal ST v5 migration package.

The builder is intentionally incapable of generating formal inputs, schedules,
measured roots, or analysis.  It copies a frozen implementation payload,
portable runtimes, and the Unity installer; creates a complete per-file
manifest; and builds a ZIP64 archive without credential material.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Sequence, Tuple


MANIFEST_RELATIVE = Path("Research/Gate14Re-ME/Package/v5/package-manifest.v1.json")
MANIFEST_SCHEMA = "gate14re-me-formal-st-v5-migration-package-manifest-v1"
MANIFEST_STATUS = "FROZEN_PACKAGE_PAYLOAD_READY_FOR_VALIDATION_FORMAL_ST_NOT_STARTED"
ARCHIVE_PREFIX = "Gate14ReME-FormalST-v5"
UNITY_INSTALLER_SHA256 = "f0d449732ac48e5058fb34b8fdc260daf90e15ef6c6b418d635796da0a448eaa"
UNITY_INSTALLER_BYTES = 3349395904
PYTHON_SHA256 = "7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1"
POWERSHELL_SHA256 = "362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139"
FREEZE_INDEX_SHA256 = "35c3b98e42cc21b200308460c6b93fb48961b4a450522acc23958c76b70b00dd"


class PackageError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PackageError(message)


def relative_posix(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def is_credential_like(relative: str) -> bool:
    normalized = relative.replace("\\", "/")
    lower = normalized.lower()
    if lower.endswith("/credentials-not-included.md"):
        return False
    if lower in {
        "migrationruntime/python/lib/secrets.py",
        "migrationruntime/python/lib/token.py",
        "migrationruntime/python/lib/lib2to3/pgen2/token.py",
    }:
        return False
    if re.search(r"(?i)(^|/)(credentials?|secrets?|tokens?|passwords?|id_rsa|id_ed25519)([._/-]|$)", normalized):
        return True
    if re.search(r"(?i)(^|/)\.env($|\.)", normalized):
        return True
    if re.search(r"(?i)unity账号", normalized):
        return True
    if re.search(r"(?i)\.(pem|key|pfx|p12|ulf|alf)$", normalized):
        return True
    return False


def ignore_generated(directory: str, names: Sequence[str]) -> set[str]:
    ignored: set[str] = set()
    for name in names:
        lower = name.lower()
        if name == "__pycache__" or lower.endswith((".pyc", ".pyo")):
            ignored.add(name)
        if name in {"Library", "Temp", "Logs", "obj", ".git"}:
            ignored.add(name)
    return ignored


def copy_tree(source: Path, target: Path, *, ignore: Any = ignore_generated) -> None:
    require(source.is_dir(), f"source directory is missing: {source}")
    require(not target.exists(), f"target directory already exists: {target}")
    shutil.copytree(source, target, copy_function=shutil.copy2, ignore=ignore)


def copy_file(source: Path, target: Path) -> None:
    require(source.is_file(), f"source file is missing: {source}")
    require(not target.exists(), f"target file already exists: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def copy_project_relative(project_root: Path, stage_root: Path, relative: str) -> None:
    source = project_root / Path(relative)
    target = stage_root / Path(relative)
    if source.is_dir():
        copy_tree(source, target)
    else:
        copy_file(source, target)


def copy_python_runtime(source: Path, target: Path) -> None:
    require(source.is_dir(), f"Python runtime is missing: {source}")
    target.mkdir(parents=True, exist_ok=False)
    for name in (
        "python.exe",
        "pythonw.exe",
        "python3.dll",
        "python312.dll",
        "vcruntime140.dll",
        "vcruntime140_1.dll",
        "LICENSE.txt",
    ):
        copy_file(source / name, target / name)
    copy_tree(source / "DLLs", target / "DLLs")

    def ignore_python_lib(directory: str, names: Sequence[str]) -> set[str]:
        ignored = ignore_generated(directory, names)
        if Path(directory).resolve() == (source / "Lib").resolve() and "site-packages" in names:
            ignored.add("site-packages")
        return ignored

    copy_tree(source / "Lib", target / "Lib", ignore=ignore_python_lib)


def stage_package(
    project_root: Path,
    stage_root: Path,
    python_runtime: Path,
    powershell_runtime: Path,
    unity_installer: Path,
) -> Dict[str, Any]:
    require(stage_root.is_dir(), "staging root must already exist")
    require(not any(stage_root.iterdir()), "staging root must be empty and fresh")
    require(sha256_file(unity_installer) == UNITY_INSTALLER_SHA256, "Unity installer SHA-256 mismatch")
    require(unity_installer.stat().st_size == UNITY_INSTALLER_BYTES, "Unity installer byte count mismatch")
    require(sha256_file(python_runtime / "python.exe") == PYTHON_SHA256, "Python runtime SHA-256 mismatch")
    require(sha256_file(powershell_runtime / "pwsh.exe") == POWERSHELL_SHA256, "PowerShell runtime SHA-256 mismatch")

    started = time.perf_counter()
    for relative in (
        "Assets/_Scripts",
        "Assets/Plugins",
        "Packages",
        "ProjectSettings",
        "Research/Gate14Re-ME",
    ):
        copy_project_relative(project_root, stage_root, relative)
    for relative in ("Assets/_Scripts.meta", "Assets/Plugins.meta", "START-HERE.cmd"):
        copy_project_relative(project_root, stage_root, relative)

    evidence_files = (
        "Research/Verification/Gate14Re-ME/formal-st-design-freeze-v5-attempt-001/terminal-receipt.v1.json",
        "Research/Verification/Gate14Re-ME/formal-st-design-freeze-v5-attempt-001/final-evidence-freeze-manifest.v1.json",
        "Research/Verification/Gate14Re-ME/formal-st-design-freeze-v5-attempt-001/freeze-manifest.v1.json",
        "Research/Verification/Gate14Re-ME/load-qualification-read-only-acceptance-attempt-001/qualification-terminal-pass-receipt.v1.json",
        "Research/Verification/Gate14Re-ME/load-qualification-post-qualification-runtime-diagnostic-attempt-002/terminal-receipt.v2.json",
        "Research/Verification/Gate14Re-ME/formal-st-anonymous-power-attempt-001/terminal-receipt.v1.json",
        "Research/Verification/Gate14Re-ME/formal-st-anonymous-power-attempt-001/final-evidence-freeze-manifest.v1.json",
        "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json",
        "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1",
        "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/generate_and_validate_planning_assets_v4_1.py",
        "Research/Verification/Gate14Re-ME/formal-st-migration-package-build-attempt-003/package-build-authorization.v1.json",
        "Research/Verification/Gate14Re-ME/formal-st-migration-package-build-attempt-003/package-build-plan.v1.json",
    )
    for relative in evidence_files:
        copy_project_relative(project_root, stage_root, relative)

    copy_python_runtime(python_runtime, stage_root / "MigrationRuntime/Python")
    copy_tree(powershell_runtime, stage_root / "MigrationRuntime/PowerShell")
    copy_file(unity_installer, stage_root / "installers/UnitySetup64-2022.3.30f1c1.exe")

    hits = [relative_posix(path, stage_root) for path in stage_root.rglob("*") if path.is_file() and is_credential_like(relative_posix(path, stage_root))]
    require(not hits, f"credential-like files detected in staged payload: {hits}")
    require(not (stage_root / "Research/FormalInputs").exists(), "formal input root entered staging")
    require(not (stage_root / "Research/FormalRuns").exists(), "formal measured root entered staging")
    return {
        "status": "STAGED_NO_FORMAL_EXECUTION",
        "elapsedSeconds": round(time.perf_counter() - started, 3),
        "filesBeforeManifest": sum(1 for path in stage_root.rglob("*") if path.is_file()),
        "credentialLikeFiles": 0,
    }


def build_manifest(package_root: Path) -> Dict[str, Any]:
    manifest_path = package_root / MANIFEST_RELATIVE
    require(not manifest_path.exists(), "package manifest already exists")
    started = time.perf_counter()
    paths = sorted((path for path in package_root.rglob("*") if path.is_file()), key=lambda item: relative_posix(item, package_root))
    files: List[Dict[str, Any]] = []
    total_bytes = 0
    for path in paths:
        relative = relative_posix(path, package_root)
        require(not is_credential_like(relative), f"credential-like file cannot enter manifest: {relative}")
        size = path.stat().st_size
        files.append({"relativePath": relative, "bytes": size, "sha256": sha256_file(path)})
        total_bytes += size
    manifest = {
        "schema": MANIFEST_SCHEMA,
        "studyId": "Gate14Re-ME",
        "designId": "gate14re-me-formal-st-bounded-gnf-v5",
        "packageId": "gate14re-me-formal-st-v5-migration-package-attempt-003",
        "status": MANIFEST_STATUS,
        "createdAtUtc": utc_now(),
        "manifestSelfExcluded": True,
        "fileCount": len(files),
        "totalBytes": total_bytes,
        "files": files,
        "frozenFormalSTFreezeIndexSha256": FREEZE_INDEX_SHA256,
        "unityInstaller": {
            "relativePath": "installers/UnitySetup64-2022.3.30f1c1.exe",
            "bytes": UNITY_INSTALLER_BYTES,
            "sha256": UNITY_INSTALLER_SHA256,
        },
        "portableRuntime": {
            "pythonRelativePath": "MigrationRuntime/Python/python.exe",
            "pythonSha256": PYTHON_SHA256,
            "powerShellRelativePath": "MigrationRuntime/PowerShell/pwsh.exe",
            "powerShellSha256": POWERSHELL_SHA256,
        },
        "credentialPolicy": {
            "credentialLikeFiles": 0,
            "unityAccountOrLicenseActivationFiles": 0,
            "credentialsCopied": False,
            "credentialsPermittedInZip": False,
            "softwareLicenseNoticesAreNotCredentials": True,
        },
        "formalInputsCreated": 0,
        "formalScheduleRowsCreated": 0,
        "formalCollectionStarted": False,
        "formalAnalysisStarted": False,
        "mqStarted": False,
        "mtStarted": False,
    }
    write_json(manifest_path, manifest)
    return {
        "status": MANIFEST_STATUS,
        "manifest": str(manifest_path),
        "manifestSha256": sha256_file(manifest_path),
        "fileCount": len(files),
        "totalBytes": total_bytes,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def verify_package(package_root: Path) -> Dict[str, Any]:
    started = time.perf_counter()
    manifest_path = package_root / MANIFEST_RELATIVE
    require(manifest_path.is_file(), "package manifest is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    require(manifest.get("schema") == MANIFEST_SCHEMA and manifest.get("status") == MANIFEST_STATUS, "package manifest header mismatch")
    expected: Dict[str, Dict[str, Any]] = {}
    total_bytes = 0
    for entry in manifest.get("files", []):
        relative = entry.get("relativePath")
        require(isinstance(relative, str) and relative and relative not in expected, "invalid or duplicate manifest path")
        require(not is_credential_like(relative), f"credential-like path is in manifest: {relative}")
        expected[relative] = entry
        path = (package_root / Path(relative)).resolve()
        try:
            path.relative_to(package_root.resolve())
        except ValueError as exc:
            raise PackageError(f"manifest path escapes package root: {relative}") from exc
        require(path.is_file(), f"manifest file is missing: {relative}")
        require(path.stat().st_size == entry.get("bytes"), f"byte mismatch: {relative}")
        require(sha256_file(path) == entry.get("sha256"), f"SHA-256 mismatch: {relative}")
        total_bytes += path.stat().st_size
    require(len(expected) == manifest.get("fileCount"), "manifest fileCount mismatch")
    require(total_bytes == manifest.get("totalBytes"), "manifest totalBytes mismatch")
    actual = {
        relative_posix(path, package_root)
        for path in package_root.rglob("*")
        if path.is_file() and path.resolve() != manifest_path.resolve()
    }
    require(actual == set(expected), f"unexpected or missing package files: extra={sorted(actual-set(expected))[:10]} missing={sorted(set(expected)-actual)[:10]}")
    hits = [relative for relative in sorted(actual | {MANIFEST_RELATIVE.as_posix()}) if is_credential_like(relative)]
    require(not hits, f"credential-like package paths detected: {hits}")
    require(not (package_root / "Research/FormalInputs").exists(), "formal input root exists in package")
    require(not (package_root / "Research/FormalRuns").exists(), "formal measured root exists in package")
    return {
        "status": "PASS_COMPLETE_FILE_HASH_AND_CREDENTIAL_EXCLUSION",
        "manifestSha256": sha256_file(manifest_path),
        "fileCount": len(expected),
        "totalBytes": total_bytes,
        "credentialLikeFiles": 0,
        "formalInputsCreated": 0,
        "formalCollectionStarted": False,
        "formalAnalysisStarted": False,
        "mqStarted": False,
        "mtStarted": False,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def clean_generated_test_artifacts(package_root: Path) -> Dict[str, Any]:
    """Remove only post-readiness files that are absent from the frozen manifest."""
    manifest_path = package_root / MANIFEST_RELATIVE
    require(manifest_path.is_file(), "package manifest is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    expected = {entry["relativePath"] for entry in manifest.get("files", [])}
    actual_paths = [path for path in package_root.rglob("*") if path.is_file() and path.resolve() != manifest_path.resolve()]
    extras = sorted((path for path in actual_paths if relative_posix(path, package_root) not in expected), key=lambda p: relative_posix(p, package_root))
    exact_allowed = {
        ".vsconfig",
        "Assembly-CSharp-Editor.csproj",
        "Assembly-CSharp.csproj",
        "attempt-003.sln",
        "Assets/_Scripts/Research/Editor/Gate14ReMEFormalSTPackageReadinessV5.cs.meta",
    }

    def allowed(relative: str) -> bool:
        if relative in exact_allowed:
            return True
        if relative.startswith(("Library/", "Logs/", "UserSettings/")):
            return True
        parts = Path(relative).parts
        return "__pycache__" in parts and relative.lower().endswith(".pyc")

    disallowed = [relative_posix(path, package_root) for path in extras if not allowed(relative_posix(path, package_root))]
    require(not disallowed, f"unrecognized post-readiness files; refusing cleanup: {disallowed[:20]}")
    root_resolved = package_root.resolve()
    for path in extras:
        resolved_path = path.resolve()
        try:
            resolved_path.relative_to(root_resolved)
        except ValueError as exc:
            raise PackageError(f"cleanup target escapes package root: {path}") from exc
        path.unlink()
    directories = sorted((path for path in package_root.rglob("*") if path.is_dir()), key=lambda p: len(p.parts), reverse=True)
    removed_directories = 0
    for directory in directories:
        try:
            next(directory.iterdir())
        except StopIteration:
            directory.rmdir()
            removed_directories += 1
    return {
        "status": "PASS_REMOVED_ONLY_UNMANIFESTED_TEST_DERIVATIVES",
        "removedFiles": len(extras),
        "removedDirectories": removed_directories,
        "manifestListedFilesRemoved": 0,
    }


def build_zip(package_root: Path, archive_path: Path) -> Dict[str, Any]:
    require(not archive_path.exists(), "archive path must be fresh")
    verification = verify_package(package_root)
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    paths = sorted((path for path in package_root.rglob("*") if path.is_file()), key=lambda item: relative_posix(item, package_root))
    with zipfile.ZipFile(archive_path, "x", allowZip64=True) as archive:
        for path in paths:
            relative = relative_posix(path, package_root)
            require(not is_credential_like(relative), f"credential-like file blocked before ZIP: {relative}")
            arcname = f"{ARCHIVE_PREFIX}/{relative}"
            compression = zipfile.ZIP_STORED if path.stat().st_size >= 256 * 1024 * 1024 else zipfile.ZIP_DEFLATED
            archive.write(path, arcname, compress_type=compression, compresslevel=1 if compression == zipfile.ZIP_DEFLATED else None)
    with zipfile.ZipFile(archive_path, "r", allowZip64=True) as archive:
        bad = archive.testzip()
        require(bad is None, f"ZIP CRC validation failed: {bad}")
        names = archive.namelist()
        require(len(names) == len(paths), "ZIP entry cardinality mismatch")
        require(not any(is_credential_like(name[len(ARCHIVE_PREFIX) + 1 :]) for name in names), "credential-like ZIP entry detected")
    return {
        "status": "PASS_ZIP64_BUILD_AND_CRC",
        "archive": str(archive_path),
        "bytes": archive_path.stat().st_size,
        "sha256": sha256_file(archive_path),
        "entries": len(paths),
        "packageManifestSha256": verification["manifestSha256"],
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def extract_and_verify(archive_path: Path, extraction_parent: Path) -> Dict[str, Any]:
    require(archive_path.is_file(), "archive is missing")
    require(not extraction_parent.exists(), "extraction root must be fresh")
    extraction_parent.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    with zipfile.ZipFile(archive_path, "r", allowZip64=True) as archive:
        for info in archive.infolist():
            normalized = Path(info.filename)
            require(not normalized.is_absolute() and ".." not in normalized.parts, f"unsafe ZIP path: {info.filename}")
            require(info.filename.startswith(ARCHIVE_PREFIX + "/"), f"unexpected ZIP prefix: {info.filename}")
            relative = info.filename[len(ARCHIVE_PREFIX) + 1 :]
            require(not is_credential_like(relative), f"credential-like ZIP entry: {relative}")
        archive.extractall(extraction_parent)
    package_root = extraction_parent / ARCHIVE_PREFIX
    verified = verify_package(package_root)
    return {
        "status": "PASS_FRESH_EXTRACTION_COMPLETE_HASH_VERIFICATION",
        "archiveSha256": sha256_file(archive_path),
        "extractedPackageRoot": str(package_root),
        "fileCount": verified["fileCount"],
        "totalBytes": verified["totalBytes"],
        "credentialLikeFiles": 0,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def resolved(path_text: str) -> Path:
    return Path(path_text).resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    stage = subparsers.add_parser("stage")
    stage.add_argument("--project-root", required=True)
    stage.add_argument("--staging-root", required=True)
    stage.add_argument("--python-runtime", required=True)
    stage.add_argument("--powershell-runtime", required=True)
    stage.add_argument("--unity-installer", required=True)
    manifest = subparsers.add_parser("manifest")
    manifest.add_argument("--package-root", required=True)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--package-root", required=True)
    clean = subparsers.add_parser("clean-generated")
    clean.add_argument("--package-root", required=True)
    zip_parser = subparsers.add_parser("zip")
    zip_parser.add_argument("--package-root", required=True)
    zip_parser.add_argument("--archive", required=True)
    extract = subparsers.add_parser("extract-verify")
    extract.add_argument("--archive", required=True)
    extract.add_argument("--extraction-root", required=True)
    args = parser.parse_args()

    if args.command == "stage":
        result = stage_package(
            resolved(args.project_root),
            resolved(args.staging_root),
            resolved(args.python_runtime),
            resolved(args.powershell_runtime),
            resolved(args.unity_installer),
        )
    elif args.command == "manifest":
        result = build_manifest(resolved(args.package_root))
    elif args.command == "verify":
        result = verify_package(resolved(args.package_root))
    elif args.command == "clean-generated":
        result = clean_generated_test_artifacts(resolved(args.package_root))
    elif args.command == "zip":
        result = build_zip(resolved(args.package_root), resolved(args.archive))
    elif args.command == "extract-verify":
        result = extract_and_verify(resolved(args.archive), resolved(args.extraction_root))
    else:
        raise AssertionError(args.command)
    print(canonical_json(result))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(canonical_json({"status": "FAIL_CLOSED", "errorType": type(exc).__name__, "error": str(exc)}), file=sys.stderr)
        raise SystemExit(1)
