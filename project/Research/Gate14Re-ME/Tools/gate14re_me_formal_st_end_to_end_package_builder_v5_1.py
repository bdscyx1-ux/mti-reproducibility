#!/usr/bin/env python3
"""Build the Gate14Re-ME formal-ST v5 end-to-end migration package.

This wrapper reuses the frozen attempt-003 payload builder, adds the deliberate
run-to-data-package entry point and attempt-004 evidence, and binds the
end-to-end authorization chain into a new package manifest. Package build and
test remain algorithm-free and never generate formal inputs or formal data.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any, Dict


BASE_RELATIVE = Path("Research/Gate14Re-ME/Tools/gate14re_me_formal_st_package_builder_v5.py")
PACKAGE_ID = "gate14re-me-formal-st-v5-end-to-end-package-attempt-004"
UMBRELLA_RELATIVE = (
    "Research/Gate14Re-ME/Package/v5/Authorizations/"
    "end-to-end-through-data-package-authorization.v1.json"
)
UMBRELLA_SHA256 = "68d3a962a018f78b18776a436f6183b167837c6002efd991d094e285b891b508"
ORCHESTRATOR_RELATIVE = (
    "Research/Gate14Re-ME/Package/v5/"
    "Run-To-Accepted-Data-Package.v5_1.ps1"
)
ORCHESTRATOR_SHA256 = "83bb3b9a4ed7dc56f4429b93e5920351cc714b0d2f9e41e21e81f6646803c583"
INPUT_AUTH_RELATIVE = (
    "Research/Gate14Re-ME/Package/v5/Authorizations/"
    "formal-input-generation-authorization.end-to-end.v1.json"
)
INPUT_AUTH_SHA256 = "4d0c58eb4657ff77c4a88fc84b14ea4509d4e41415dee47e72f111894f0f06f8"
IDENTITY_RELATIVE = (
    "Research/Gate14Re-ME/Package/v5/Authorizations/"
    "formal-st-algorithm-identity-binding.reused.v5.json"
)
IDENTITY_SHA256 = "2a21042283b1197d2a66d7948aede3623b9c5e71ef2576c9f6534494c086dc5e"


def load_base(project_root: Path):
    source = project_root / BASE_RELATIVE
    if not source.is_file():
        raise RuntimeError(f"base package builder is missing: {source}")
    spec = importlib.util.spec_from_file_location("gate14re_me_formal_st_package_builder_v5", source)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load the frozen v5 package builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stage_package(
    base: Any,
    project_root: Path,
    stage_root: Path,
    python_runtime: Path,
    powershell_runtime: Path,
    unity_installer: Path,
) -> Dict[str, Any]:
    result = base.stage_package(
        project_root,
        stage_root,
        python_runtime,
        powershell_runtime,
        unity_installer,
    )
    for relative in (
        "RUN-TO-DATA-PACKAGE.cmd",
        "Research/Verification/Gate14Re-ME/formal-st-migration-package-build-attempt-004/"
        "user-authorization-receipt.v1.json",
        "Research/Verification/Gate14Re-ME/formal-st-migration-package-build-attempt-004/"
        "package-build-plan.v1.json",
    ):
        base.copy_project_relative(project_root, stage_root, relative)
    base.require(
        not (stage_root / "Research/FormalInputs").exists(),
        "formal input root entered end-to-end staging",
    )
    base.require(
        not (stage_root / "Research/FormalRuns").exists(),
        "formal measured root entered end-to-end staging",
    )
    base.require(
        not (stage_root / "Research/FormalDataPackages").exists(),
        "formal accepted-data root entered end-to-end staging",
    )
    result.update(
        {
            "status": "STAGED_END_TO_END_LAUNCHER_NO_FORMAL_EXECUTION",
            "packageId": PACKAGE_ID,
            "endToEndAuthorizationSha256": UMBRELLA_SHA256,
            "formalInputsCreated": 0,
            "formalCollectionStarted": False,
            "formalAcceptanceStarted": False,
        }
    )
    return result


def build_manifest(base: Any, package_root: Path) -> Dict[str, Any]:
    base.build_manifest(package_root)
    manifest_path = package_root / base.MANIFEST_RELATIVE
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    manifest["packageId"] = PACKAGE_ID
    manifest["authorizationModel"] = (
        "USER_AUTHORIZED_UMBRELLA_WITH_HASH_BOUND_MINIMAL_CHILD_AUTHORIZATIONS_"
        "THROUGH_ACCEPTED_DATA_PACKAGE"
    )
    manifest["endToEndAuthorization"] = {
        "umbrellaRelativePath": UMBRELLA_RELATIVE,
        "umbrellaSha256": UMBRELLA_SHA256,
        "orchestratorRelativePath": ORCHESTRATOR_RELATIVE,
        "orchestratorSha256": ORCHESTRATOR_SHA256,
        "inputGenerationAuthorizationRelativePath": INPUT_AUTH_RELATIVE,
        "inputGenerationAuthorizationSha256": INPUT_AUTH_SHA256,
        "identityBindingRelativePath": IDENTITY_RELATIVE,
        "identityBindingSha256": IDENTITY_SHA256,
        "terminalBoundary": "ACCEPTED_DATA_PACKAGE_READY_FORMAL_ANALYSIS_NOT_RUN",
    }
    manifest["availableEntryPoints"] = {
        "readinessOnly": "START-HERE.cmd",
        "runThroughAcceptedDataPackage": "RUN-TO-DATA-PACKAGE.cmd",
    }
    manifest["formalAcceptedDataPackagesCreated"] = 0
    base.write_json(manifest_path, manifest)
    return {
        "status": manifest["status"],
        "manifest": str(manifest_path),
        "manifestSha256": base.sha256_file(manifest_path),
        "fileCount": manifest["fileCount"],
        "totalBytes": manifest["totalBytes"],
        "packageId": PACKAGE_ID,
        "endToEndAuthorizationSha256": UMBRELLA_SHA256,
    }


def resolved(value: str) -> Path:
    return Path(value).resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    subparsers = parser.add_subparsers(dest="command", required=True)

    stage = subparsers.add_parser("stage")
    stage.add_argument("--staging-root", required=True)
    stage.add_argument("--python-runtime", required=True)
    stage.add_argument("--powershell-runtime", required=True)
    stage.add_argument("--unity-installer", required=True)

    manifest = subparsers.add_parser("manifest")
    manifest.add_argument("--package-root", required=True)

    verify = subparsers.add_parser("verify")
    verify.add_argument("--package-root", required=True)

    zip_parser = subparsers.add_parser("zip")
    zip_parser.add_argument("--package-root", required=True)
    zip_parser.add_argument("--archive", required=True)

    extract = subparsers.add_parser("extract-verify")
    extract.add_argument("--archive", required=True)
    extract.add_argument("--extraction-root", required=True)

    args = parser.parse_args()
    project_root = resolved(args.project_root)
    base = load_base(project_root)

    if args.command == "stage":
        result = stage_package(
            base,
            project_root,
            resolved(args.staging_root),
            resolved(args.python_runtime),
            resolved(args.powershell_runtime),
            resolved(args.unity_installer),
        )
    elif args.command == "manifest":
        result = build_manifest(base, resolved(args.package_root))
    elif args.command == "verify":
        result = base.verify_package(resolved(args.package_root))
    elif args.command == "zip":
        result = base.build_zip(resolved(args.package_root), resolved(args.archive))
    elif args.command == "extract-verify":
        result = base.extract_and_verify(
            resolved(args.archive),
            resolved(args.extraction_root),
        )
    else:
        raise RuntimeError(f"unsupported command: {args.command}")

    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
