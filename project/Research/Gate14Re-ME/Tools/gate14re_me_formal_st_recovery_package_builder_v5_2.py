#!/usr/bin/env python3
"""Build and independently verify the Gate14Re-ME formal-ST recovery package.

Attempt-005 is a prospective successor to the incomplete attempt-004 transfer.
It deliberately packages the complete Research source/evidence snapshot except
FormalRuns and package-output roots, binds the six algorithm implementations and
specifications, carries only the already-frozen portable Python/PowerShell
runtimes, and requires an exact preinstalled Unity editor.  The build and test
path is algorithm-free and cannot start formal input generation, collection,
acceptance, analysis, MQ, or MT.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence


ATTEMPT = "005"
FORMAL_ATTEMPT = "002"
PACKAGE_ID = "gate14re-me-formal-st-v5-end-to-end-package-attempt-005"
ARCHIVE_STEM = "Gate14ReME-FormalST-v5-end-to-end-attempt-005"
ARCHIVE_PREFIX = ARCHIVE_STEM
AUTHORIZATION_ID = "gate14re-me-formal-st-end-to-end-fb991714-8586-4b21-8deb-e8540b489220"
USER_SCOPE_STATEMENTS = [
    "授权后续工作",
    "重新生成迁移包",
    "这次的打包不需要添加UnityEditor和UnityHub安装包",
    "把Research里除了FormalRuns的所有文件都打包吧，避免再次缺失文件",
]
USER_SCOPE_SHA256 = "2c4a54779d75be1683dfcfa8291f626b0963e831dc17488e117e2dd62d9b77f8"

MANIFEST_RELATIVE = Path("Research/Gate14Re-ME/Package/v5/package-manifest.v1.json")
MANIFEST_SCHEMA = "gate14re-me-formal-st-v5-migration-package-manifest-v1"
MANIFEST_STATUS = "FROZEN_PACKAGE_PAYLOAD_READY_FOR_VALIDATION_FORMAL_ST_NOT_STARTED"
READINESS_RELATIVE = Path("Research/Gate14Re-ME/Package/v5/Install-And-Verify-Gate14ReMEFormalST.v5_2.ps1")
ORCHESTRATOR_RELATIVE = Path("Research/Gate14Re-ME/Package/v5/Run-To-Accepted-Data-Package.v5_2.ps1")
UMBRELLA_RELATIVE = Path(
    "Research/Gate14Re-ME/Package/v5/Authorizations/"
    "end-to-end-through-data-package-authorization.v2.json"
)
INPUT_AUTH_RELATIVE = Path(
    "Research/Gate14Re-ME/Package/v5/Authorizations/"
    "formal-input-generation-authorization.end-to-end.v2.json"
)
IDENTITY_RELATIVE = Path(
    "Research/Gate14Re-ME/Package/v5/Authorizations/"
    "formal-st-algorithm-identity-binding.reused.v5.json"
)
BUILD_AUTH_RELATIVE = Path(
    "Research/Verification/Gate14Re-ME/"
    "formal-st-migration-package-build-attempt-005/package-build-authorization.v1.json"
)
RESEARCH_INVENTORY_RELATIVE = Path(
    "Research/Gate14Re-ME/Package/v5/research-source-inventory.attempt-005.jsonl"
)
RESEARCH_INVENTORY_SUMMARY_RELATIVE = Path(
    "Research/Gate14Re-ME/Package/v5/research-source-inventory-summary.attempt-005.json"
)

OLD_READINESS_RELATIVE = Path("Research/Gate14Re-ME/Package/v5/Install-And-Verify-Gate14ReMEFormalST.v5_0.ps1")
OLD_ORCHESTRATOR_RELATIVE = Path("Research/Gate14Re-ME/Package/v5/Run-To-Accepted-Data-Package.v5_1.ps1")
FAIRNESS_RELATIVE = Path("Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json")

STAGING_RELATIVE = Path("Research/PackageStaging/Gate14Re-ME/formal-st/v5/attempt-005")
BUILD_RELATIVE = Path("Research/Packages/Gate14Re-ME/formal-st/v5/attempt-005")
TEST_RELATIVE = Path("Research/PackageTests/Gate14Re-ME/formal-st/v5/attempt-005")
EVIDENCE_RELATIVE = Path(
    "Research/Verification/Gate14Re-ME/formal-st-migration-package-build-attempt-005"
)

OLD_OUTER_RELATIVE = Path(
    "Research/Packages/Gate14Re-ME/formal-st/v5/attempt-004/实验一键迁移包-cyx.zip"
)
OLD_INNER_NAME = "Gate14ReME-FormalST-v5-end-to-end-attempt-004.zip"
OLD_INNER_SHA256 = "493c2e7ebbd2f77b2a12803d0878c5a4f18bafd60a554380718a38bbc04fcedf"

UNITY_SHA256 = "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf"
PYTHON_SHA256 = "7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1"
POWERSHELL_SHA256 = "362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139"
PRIOR_UMBRELLA_SHA256 = "68d3a962a018f78b18776a436f6183b167837c6002efd991d094e285b891b508"

FROZEN_HASHES = {
    "Research/Gate14Re-ME/Execution/v5/formal-st-freeze-index.v5_0.json":
        "35c3b98e42cc21b200308460c6b93fb48961b4a450522acc23958c76b70b00dd",
    "Research/Gate14Re-ME/Execution/v5/formal-st-implementation-manifest.v5_0.json":
        "161a12b9325ca9ef181b9673cd4c7e73b5fa68a016911afd694c1493c86af3e3",
    "Research/Gate14Re-ME/Execution/v5/formal-st-acquisition-contract.v5_0.json":
        "0eebffd7560c06414e7990cf9cb95e80aeaa3993643719fffe507981fb58be58",
    "Research/Gate14Re-ME/Execution/v5/formal-st-operational-resource-budget.v5_0.json":
        "5f8d3febcf774118f05e29bd668ee55544882893426bb21464d2ed3bfdd77533",
    "Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json":
        "5a2ba89c08efa86f79c756ee3b0cc54a68c310e2414760f18f286e95095319ca",
    "Research/Gate14Re-ME/Execution/v5/formal-st-independent-acceptance-contract.v5_0.json":
        "c807266e6ed8d9cd3c3a57e3aa72bfe6e82a5f42db06f10762a9a713bd72f366",
    "Research/Gate14Re-ME/Tools/gate14re_me_formal_st_material_generator_v5.py":
        "6eff9c061601c158ecfe1eeed7137ebb30e21206b5394586dc071e462319563b",
    "Research/Gate14Re-ME/Execution/v5/Run-Gate14ReMEFormalST.v5_0.ps1":
        "281c8eef6d2070ce96df12b3dd8fd1b320fb0c7dcd3caa7dbf09f1a7b16c7f17",
    "Research/Gate14Re-ME/Execution/v5/Run-Gate14ReMEFormalSTReadOnlyAcceptance.v5_0.ps1":
        "ae937579d000a1fc1dd56e98d8f30a77e04317b072f5279443cb67bccd2bea26",
    "Research/Gate14Re-ME/Tools/gate14re_me_formal_st_acceptance_v5.py":
        "18e876973c8e68a9c836a207adc5fda3ffdbe7158fd5c5102fbcf59dcf80ac82",
}

RESEARCH_EXCLUDED_TOP_LEVEL = {"FormalRuns", "Packages", "PackageStaging", "PackageTests"}
PACKAGE_OUTPUT_EXPLANATION = {
    "Research/FormalRuns": "user-requested exclusion of measured/formal run data",
    "Research/Packages": "package-output exclusion prevents recursive embedding and excludes the superseded Unity-bearing archive",
    "Research/PackageStaging": "ephemeral package-construction output; excluded to prevent self-inclusion",
    "Research/PackageTests": "ephemeral extraction/readiness output; excluded to prevent self-inclusion",
}


class PackageError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PackageError(message)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def write_json(path: Path, value: Any, *, exclusive: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = "x" if exclusive else "w"
    with path.open(mode, encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def write_text(path: Path, value: str, *, exclusive: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = "x" if exclusive else "w"
    with path.open(mode, encoding="utf-8", newline="\n") as handle:
        handle.write(value)


def relative_posix(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def is_credential_like(relative: str) -> bool:
    normalized = relative.replace("\\", "/")
    lower = normalized.lower()
    if lower.endswith("/credentials-not-included.md"):
        return False
    if lower.endswith("/credential-exclusion-receipt.v1.json"):
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


def is_unity_installer_like(relative: str) -> bool:
    lower = relative.replace("\\", "/").lower()
    name = Path(lower).name
    if "unitysetup" in name or "unityhub" in name or "unity-hub" in name:
        return True
    if lower.startswith("installers/") and name.endswith((".exe", ".msi", ".msix", ".appx")):
        return True
    return False


def source_research_files(project_root: Path) -> Iterator[Path]:
    research_root = project_root / "Research"
    require(research_root.is_dir(), f"Research root is missing: {research_root}")
    for path in research_root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(research_root)
        if relative.parts and relative.parts[0] in RESEARCH_EXCLUDED_TOP_LEVEL:
            continue
        yield path


def package_files(root: Path, *, exclude_manifest: bool = False) -> list[Path]:
    manifest = (root / MANIFEST_RELATIVE).resolve()
    return sorted(
        (
            path
            for path in root.rglob("*")
            if path.is_file() and (not exclude_manifest or path.resolve() != manifest)
        ),
        key=lambda path: relative_posix(path, root),
    )


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    require(count == 1, f"{label}: expected exactly one source fragment, found {count}")
    return text.replace(old, new, 1)


def parse_powershell(script: str, pwsh: Path, label: str) -> None:
    parser = r"""
$tokens = $null
$errors = $null
$text = [Console]::In.ReadToEnd()
$null = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
  $errors | ForEach-Object { [Console]::Error.WriteLine($_.ToString()) }
  exit 1
}
"""
    result = subprocess.run(
        [str(pwsh), "-NoLogo", "-NoProfile", "-Command", parser],
        input=script,
        text=True,
        capture_output=True,
        check=False,
    )
    require(result.returncode == 0, f"{label} PowerShell parse failed: {result.stderr.strip()}")


def verify_frozen_hashes(project_root: Path) -> dict[str, str]:
    actual: dict[str, str] = {}
    for relative, expected in FROZEN_HASHES.items():
        path = project_root / relative
        require(path.is_file(), f"frozen file is missing: {relative}")
        digest = sha256_file(path)
        require(digest == expected, f"frozen SHA-256 mismatch: {relative}: expected={expected} actual={digest}")
        actual[relative] = digest
    return actual


def semantic_closure(project_root: Path) -> list[dict[str, Any]]:
    binding_path = project_root / FAIRNESS_RELATIVE
    binding = json.loads(binding_path.read_text(encoding="utf-8-sig"))
    require(binding.get("schema") == "gate14re-me-six-algorithm-fairness-binding-v1", "fairness binding schema mismatch")
    algorithms = binding.get("algorithms")
    require(isinstance(algorithms, list) and len(algorithms) == 6, "fairness binding must contain exactly six algorithms")
    entries: list[dict[str, Any]] = []
    for algorithm in algorithms:
        for role, path_key, hash_key in (
            ("implementation", "implementationRelativePath", "implementationSha256"),
            ("specification", "specificationRelativePath", "specificationSha256"),
        ):
            relative = algorithm.get(path_key)
            expected = algorithm.get(hash_key)
            require(isinstance(relative, str) and isinstance(expected, str), f"invalid {role} binding")
            path = project_root / relative
            require(path.is_file(), f"semantic dependency is missing: {relative}")
            actual = sha256_file(path)
            require(actual == expected, f"semantic dependency SHA-256 mismatch: {relative}")
            entries.append(
                {
                    "algorithmId": algorithm.get("algorithmId"),
                    "role": role,
                    "relativePath": relative,
                    "bytes": path.stat().st_size,
                    "sha256": actual,
                }
            )
    for role, path_key, hash_key in (
        ("navigation-contract", "navigationContractsRelativePath", "navigationContractsSha256"),
        ("navigation-grid", "navigationGridRelativePath", "navigationGridSha256"),
    ):
        relative = binding.get(path_key)
        expected = binding.get(hash_key)
        require(isinstance(relative, str) and isinstance(expected, str), f"invalid {role} binding")
        path = project_root / relative
        require(path.is_file(), f"semantic dependency is missing: {relative}")
        actual = sha256_file(path)
        require(actual == expected, f"semantic dependency SHA-256 mismatch: {relative}")
        entries.append({"role": role, "relativePath": relative, "bytes": path.stat().st_size, "sha256": actual})
    require(sum(1 for entry in entries if entry["role"] == "specification") == 6, "six specification files were not closed")
    return entries


def derive_readiness(project_root: Path) -> str:
    text = (project_root / OLD_READINESS_RELATIVE).read_text(encoding="utf-8-sig")
    text = text.replace("\r\n", "\n")
    text = replace_once(
        text,
        """param(
    [string]$UnityExecutable,
    [string]$ReceiptRoot,
    [switch]$InstallUnityIfMissing
)""",
        """param(
    [string]$UnityExecutable,
    [string]$ReceiptRoot
)""",
        "readiness parameter surface",
    )
    text = replace_once(
        text,
        "$expectedInstallerSha256 = 'f0d449732ac48e5058fb34b8fdc260daf90e15ef6c6b418d635796da0a448eaa'\n",
        "",
        "readiness installer constant",
    )
    old_resolver = re.compile(
        r"function Resolve-UnityExecutable\(\[string\]\$ProjectRoot, \[string\]\$Requested, \[bool\]\$MayInstall\) \{.*?\n\}\n\n\$projectRoot =",
        re.DOTALL,
    )
    new_resolver = r"""function Resolve-UnityExecutable([string]$ProjectRoot, [string]$Requested) {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) { $candidates.Add($Requested) }
    if (-not [string]::IsNullOrWhiteSpace($env:GATE14RE_ME_UNITY)) { $candidates.Add($env:GATE14RE_ME_UNITY) }
    $candidates.Add((Join-Path $ProjectRoot 'UnityEditor/2022.3.30f1c1/Editor/Unity.exe'))
    $candidates.Add('H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe')
    $candidates.Add('C:/Program Files/Unity/Hub/Editor/2022.3.30f1c1/Editor/Unity.exe')
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $full = [System.IO.Path]::GetFullPath($candidate)
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                Assert-Hash $full $expectedUnitySha256 'Unity 2022.3.30f1c1 executable'
                return $full
            }
        }
    }
    throw [System.InvalidOperationException]::new('The exact Unity 2022.3.30f1c1 editor is not preinstalled or its SHA-256 does not match. This package intentionally contains no Unity Editor or Unity Hub installer.')
}

$projectRoot ="""
    text, replacements = old_resolver.subn(lambda _: new_resolver, text, count=1)
    require(replacements == 1, "readiness Unity resolver source fragment mismatch")
    text = replace_once(
        text,
        "    if ($normalized.EndsWith('/CREDENTIALS-NOT-INCLUDED.md', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }\n",
        "    if ($normalized.EndsWith('/CREDENTIALS-NOT-INCLUDED.md', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }\n"
        "    if ($normalized.EndsWith('/credential-exclusion-receipt.v1.json', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }\n",
        "readiness credential-evidence exemption",
    )
    text = replace_once(
        text,
        "$verifiedFiles = 0\n$verifiedBytes = [int64]0\nforeach ($entry in @($manifest.files)) {\n",
        "$verifiedFiles = 0\n$verifiedBytes = [int64]0\n$manifestIndex = @{}\nforeach ($entry in @($manifest.files)) {\n",
        "readiness manifest index initialization",
    )
    text = replace_once(
        text,
        "    $relative = [string]$entry.relativePath\n    Require-Condition (-not (Test-CredentialLikeRelativePath $relative))",
        "    $relative = [string]$entry.relativePath\n"
        "    Require-Condition (-not [string]::IsNullOrWhiteSpace($relative) -and -not $manifestIndex.ContainsKey($relative)) \"Invalid or duplicate manifest path: $relative\"\n"
        "    $manifestIndex[$relative] = $entry\n"
        "    Require-Condition (-not (Test-CredentialLikeRelativePath $relative))",
        "readiness manifest index population",
    )
    semantic_block = r"""

$fairnessRelative = 'Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json'
$fairnessPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $fairnessRelative))
Assert-Hash $fairnessPath '5a2ba89c08efa86f79c756ee3b0cc54a68c310e2414760f18f286e95095319ca' 'six-algorithm fairness binding'
Require-Condition $manifestIndex.ContainsKey($fairnessRelative) 'Package manifest omits the six-algorithm fairness binding.'
$fairness = Read-Json $fairnessPath
Require-Condition (@($fairness.algorithms).Count -eq 6) 'Fairness binding algorithm cardinality mismatch.'
$semanticClosure = [System.Collections.Generic.List[object]]::new()
foreach ($algorithm in @($fairness.algorithms)) {
    foreach ($pair in @(
        @([string]$algorithm.implementationRelativePath, [string]$algorithm.implementationSha256, 'implementation'),
        @([string]$algorithm.specificationRelativePath, [string]$algorithm.specificationSha256, 'specification')
    )) {
        $semanticClosure.Add([ordered]@{ relativePath = $pair[0]; sha256 = $pair[1]; role = $pair[2] })
    }
}
$semanticClosure.Add([ordered]@{ relativePath = [string]$fairness.navigationContractsRelativePath; sha256 = [string]$fairness.navigationContractsSha256; role = 'navigation-contract' })
$semanticClosure.Add([ordered]@{ relativePath = [string]$fairness.navigationGridRelativePath; sha256 = [string]$fairness.navigationGridSha256; role = 'navigation-grid' })
Require-Condition ($semanticClosure.Count -eq 14) 'Semantic dependency closure cardinality mismatch.'
Require-Condition (@($semanticClosure | Where-Object { $_.role -eq 'specification' }).Count -eq 6) 'Exactly six algorithm specifications are required.'
foreach ($dependency in $semanticClosure) {
    $relative = [string]$dependency.relativePath
    Require-Condition $manifestIndex.ContainsKey($relative) "Package manifest omits semantic dependency: $relative"
    $full = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
    Require-Condition (Test-Path -LiteralPath $full -PathType Leaf) "Semantic dependency is missing: $relative"
    Assert-Hash $full ([string]$dependency.sha256) "semantic dependency $relative"
    Require-Condition ([string]$manifestIndex[$relative].sha256 -ceq [string]$dependency.sha256) "Manifest semantic-dependency hash mismatch: $relative"
}
"""
    text = replace_once(
        text,
        "Require-Condition ($verifiedFiles -eq [int]$manifest.fileCount -and $verifiedBytes -eq [int64]$manifest.totalBytes) 'Package manifest aggregate mismatch.'\n",
        "Require-Condition ($verifiedFiles -eq [int]$manifest.fileCount -and $verifiedBytes -eq [int64]$manifest.totalBytes) 'Package manifest aggregate mismatch.'\n"
        + semantic_block,
        "readiness semantic closure insertion",
    )
    text = replace_once(
        text,
        "$installerPath = Join-Path $projectRoot 'installers/UnitySetup64-2022.3.30f1c1.exe'\n",
        "",
        "readiness installer path",
    )
    text = replace_once(
        text,
        "Assert-Hash $installerPath $expectedInstallerSha256 'bundled Unity installer'\n",
        "",
        "readiness installer assertion",
    )
    text = text.replace(
        "formal-st-migration-package-build-attempt-003/package-build-authorization.v1.json",
        "formal-st-migration-package-build-attempt-005/package-build-authorization.v1.json",
    )
    text = replace_once(
        text,
        "$unity = Resolve-UnityExecutable -ProjectRoot $projectRoot -Requested $UnityExecutable -MayInstall $InstallUnityIfMissing.IsPresent",
        "$unity = Resolve-UnityExecutable -ProjectRoot $projectRoot -Requested $UnityExecutable",
        "readiness Unity resolve call",
    )
    text = text.replace(
        "gate14re-me-formal-st-v5-deployment-readiness-terminal-v1",
        "gate14re-me-formal-st-v5-deployment-readiness-terminal-v2",
    )
    text = text.replace(
        "PASS_MIGRATION_PACKAGE_INSTALL_AND_ALGORITHM_FREE_READINESS",
        "PASS_MIGRATION_PACKAGE_PREINSTALLED_UNITY_AND_ALGORITHM_FREE_READINESS",
    )
    text = replace_once(
        text,
        "    installerSha256 = $expectedInstallerSha256\n",
        "    unityEditorInstallerBundled = $false\n"
        "    unityHubInstallerBundled = $false\n"
        "    semanticDependencyClosureFiles = $semanticClosure.Count\n"
        "    algorithmSpecificationFiles = 6\n",
        "readiness terminal installer field",
    )
    require("InstallUnityIfMissing" not in text, "derived readiness retains installer switch")
    require("expectedInstallerSha256" not in text, "derived readiness retains installer hash")
    require("UnitySetup64" not in text, "derived readiness retains installer path")
    return text.rstrip() + "\n"


def derive_orchestrator(
    project_root: Path,
    *,
    input_authorization_sha256: str,
    readiness_sha256: str,
) -> str:
    text = (project_root / OLD_ORCHESTRATOR_RELATIVE).read_text(encoding="utf-8-sig")
    text = text.replace("\r\n", "\n")
    text = replace_once(text, "    [switch]$InstallUnityIfMissing,\n", "", "orchestrator installer switch parameter")
    text = text.replace("gate14re-me-formal-st-v5-end-to-end-package-attempt-004", PACKAGE_ID)
    text = text.replace("0dafa5724cdea831a27d8490fc6f6f5df6b1d2815a1bd9ad2328d9f767a50409", USER_SCOPE_SHA256)
    text = text.replace(
        "end-to-end-through-data-package-authorization.v1.json",
        "end-to-end-through-data-package-authorization.v2.json",
    )
    text = text.replace(
        "formal-input-generation-authorization.end-to-end.v1.json",
        "formal-input-generation-authorization.end-to-end.v2.json",
    )
    text = text.replace(
        "Install-And-Verify-Gate14ReMEFormalST.v5_0.ps1",
        "Install-And-Verify-Gate14ReMEFormalST.v5_2.ps1",
    )
    text = text.replace(
        "4d0c58eb4657ff77c4a88fc84b14ea4509d4e41415dee47e72f111894f0f06f8",
        input_authorization_sha256,
    )
    text = text.replace(
        "d9a4c54dd8f9fa80c555e1893254df8d13e5227428def0fd79400032d4d92e9a",
        readiness_sha256,
    )
    require(text.count("attempt-001") == 5, "orchestrator attempt-001 source cardinality drifted")
    text = text.replace("attempt-001", f"attempt-{FORMAL_ATTEMPT}")
    text = text.replace(
        "gate14re-me-formal-st-end-to-end-package-authorization-v1",
        "gate14re-me-formal-st-end-to-end-package-authorization-v2",
    )
    text = text.replace(
        "This launcher requires the end-to-end attempt-004 package.",
        "This launcher requires the end-to-end attempt-005 recovery package.",
    )
    install_forward = """    if ($InstallUnityIfMissing.IsPresent) {
        $readinessParameters.InstallUnityIfMissing = $true
    }
"""
    text = replace_once(text, install_forward, "", "orchestrator installer switch forwarding")
    text = text.replace(
        "PASS_MIGRATION_PACKAGE_INSTALL_AND_ALGORITHM_FREE_READINESS",
        "PASS_MIGRATION_PACKAGE_PREINSTALLED_UNITY_AND_ALGORITHM_FREE_READINESS",
    )
    closure_function = r"""

function Assert-SemanticDependencyClosure {
    param(
        [hashtable]$ManifestIndex,
        [string]$ProjectRoot,
        [string]$FairnessPath
    )
    $binding = Read-Json -Path $FairnessPath
    Require-Condition ($binding.schema -ceq 'gate14re-me-six-algorithm-fairness-binding-v1' -and @($binding.algorithms).Count -eq 6) 'Six-algorithm fairness binding schema/cardinality mismatch.'
    $dependencies = [System.Collections.Generic.List[object]]::new()
    foreach ($algorithm in @($binding.algorithms)) {
        $dependencies.Add([ordered]@{ relativePath = [string]$algorithm.implementationRelativePath; sha256 = [string]$algorithm.implementationSha256; role = 'implementation' })
        $dependencies.Add([ordered]@{ relativePath = [string]$algorithm.specificationRelativePath; sha256 = [string]$algorithm.specificationSha256; role = 'specification' })
    }
    $dependencies.Add([ordered]@{ relativePath = [string]$binding.navigationContractsRelativePath; sha256 = [string]$binding.navigationContractsSha256; role = 'navigation-contract' })
    $dependencies.Add([ordered]@{ relativePath = [string]$binding.navigationGridRelativePath; sha256 = [string]$binding.navigationGridSha256; role = 'navigation-grid' })
    Require-Condition ($dependencies.Count -eq 14) 'Semantic dependency closure must contain 14 bound files.'
    Require-Condition (@($dependencies | Where-Object { $_.role -eq 'specification' }).Count -eq 6) 'Semantic dependency closure must contain six specifications.'
    foreach ($dependency in $dependencies) {
        Assert-ManifestEntry -Index $ManifestIndex -RelativePath ([string]$dependency.relativePath) -ExpectedSha256 ([string]$dependency.sha256) -ProjectRoot $ProjectRoot
    }
    return $dependencies.Count
}
"""
    marker = "\nfunction New-FormalExecutionAuthorization {"
    text = replace_once(text, marker, closure_function + marker, "orchestrator semantic closure function")
    closure_call = """

    $semanticClosureCount = Assert-SemanticDependencyClosure -ManifestIndex $manifestIndex -ProjectRoot $projectRoot -FairnessPath (Resolve-ProjectPath -ProjectRoot $projectRoot -RelativePath $relative.fairnessBinding)
    Require-Condition ([string]$manifest.researchInclusionPolicy.status -ceq 'PASS_COMPLETE_RESEARCH_SNAPSHOT_WITH_EXPLICIT_OUTPUT_EXCLUSIONS') 'Research inclusion policy is missing or invalid.'
    Require-Condition ($manifest.unityProvisioning.unityEditorInstallerBundled -eq $false -and $manifest.unityProvisioning.unityHubInstallerBundled -eq $false) 'This recovery package must not bundle Unity Editor or Unity Hub installers.'
"""
    text = replace_once(
        text,
        "\n    $inputAuthorization = Read-Json -Path $inputAuthorizationPath\n",
        closure_call + "\n    $inputAuthorization = Read-Json -Path $inputAuthorizationPath\n",
        "orchestrator semantic closure call",
    )
    text = replace_once(
        text,
        "            identityBindingSha256 = $expectedHashes.identityBinding\n",
        "            identityBindingSha256 = $expectedHashes.identityBinding\n"
        "            semanticDependencyClosureFiles = $semanticClosureCount\n"
        "            algorithmSpecificationFiles = 6\n"
        "            unityEditorInstallerBundled = $false\n"
        "            unityHubInstallerBundled = $false\n",
        "orchestrator dry-run closure fields",
    )
    require("InstallUnityIfMissing" not in text, "derived orchestrator retains installer switch")
    return text.rstrip() + "\n"


def make_input_authorization() -> dict[str, Any]:
    return {
        "schema": "gate14re-me-formal-st-input-generation-authorization-v5",
        "studyId": "Gate14Re-ME",
        "designId": "gate14re-me-formal-st-bounded-gnf-v5",
        "protocolId": "gate14re-me-formal-st-v5",
        "authorizationId": AUTHORIZATION_ID + "/input-generation",
        "status": "AUTHORIZED_FORMAL_INPUT_GENERATION_ONLY",
        "authorizationSource": {
            "userScopeSha256": USER_SCOPE_SHA256,
            "umbrellaAuthorizationRelativePath": UMBRELLA_RELATIVE.as_posix(),
            "derivation": "Preissued child authorization under the continuing user-authorized end-to-end package scope.",
            "priorUmbrellaAuthorizationSha256": PRIOR_UMBRELLA_SHA256,
        },
        "formalInputGenerationAuthorized": True,
        "formalRootCreationAuthorized": False,
        "formalCollectionAuthorized": False,
        "formalAcceptanceExecutionAuthorized": False,
        "formalAnalysisAuthorized": False,
        "mqAuthorized": False,
        "mtAuthorized": False,
        "outputRootRelativePath": f"Research/FormalInputs/Gate14Re-ME/formal-st/v5/attempt-{FORMAL_ATTEMPT}",
        "masterSeedHex": "bfe036f32c862ea591df2387346fc1544256b32a25957bba7fc5ab9688c2c674",
        "masterSeedCommitmentSha256": "71f79bc16850bf63c02b2ce6884b792c47a133d2d9ad0e27e08cc242160d53e5",
        "identityBindingRelativePath": IDENTITY_RELATIVE.as_posix(),
        "identityBindingSha256": "2a21042283b1197d2a66d7948aede3623b9c5e71ef2576c9f6534494c086dc5e",
        "singleUseRules": {
            "outputRootMustBeFresh": True,
            "retryInSameAttempt": False,
            "resumeInSameAttempt": False,
            "topUpInSameAttempt": False,
            "formalExecutionStartsFromThisAuthorization": False,
        },
    }


def make_umbrella(input_sha: str, orchestrator_sha: str, readiness_sha: str) -> dict[str, Any]:
    return {
        "schema": "gate14re-me-formal-st-end-to-end-package-authorization-v2",
        "studyId": "Gate14Re-ME",
        "designId": "gate14re-me-formal-st-bounded-gnf-v5",
        "protocolId": "gate14re-me-formal-st-v5",
        "packageId": PACKAGE_ID,
        "authorizationId": AUTHORIZATION_ID,
        "status": "AUTHORIZED_ONE_CLICK_THROUGH_ACCEPTED_DATA_PACKAGE_NOT_ANALYSIS",
        "userAuthorization": {
            "verbatimStatements": USER_SCOPE_STATEMENTS,
            "userScopeSha256": USER_SCOPE_SHA256,
            "continuingPriorUmbrellaAuthorizationSha256": PRIOR_UMBRELLA_SHA256,
            "interpretation": (
                "The successor transfer may repeat the already-authorized formal-ST pipeline in wholly fresh attempt-002 roots "
                "after the missing semantic-document closure is repaired. It stops at the accepted data package."
            ),
            "launchGuardIsNotNewScientificAuthorization": True,
        },
        "permissions": {
            "readiness": True,
            "formalInputGeneration": True,
            "formalCollection": True,
            "readOnlyAcceptance": True,
            "acceptedDataPackageCreation": True,
            "formalAnalysis": False,
            "algorithmEffectInterpretation": False,
            "rankingOrWinnerDecision": False,
            "mq": False,
            "mt": False,
            "credentialPackaging": False,
        },
        "roots": {
            "formalInputRootRelativePath": f"Research/FormalInputs/Gate14Re-ME/formal-st/v5/attempt-{FORMAL_ATTEMPT}",
            "measuredRootRelativePath": f"Research/FormalRuns/Gate14Re-ME/formal-st/v5/attempt-{FORMAL_ATTEMPT}",
            "acceptedDataPackageRootRelativePath": f"Research/FormalDataPackages/Gate14Re-ME/formal-st/v5/attempt-{FORMAL_ATTEMPT}",
            "executionEvidenceRootRelativePath": f"Research/Verification/Gate14Re-ME/formal-st-end-to-end-execution-attempt-{FORMAL_ATTEMPT}",
            "readinessRootRelativePath": f"PackageReadiness/end-to-end-attempt-{FORMAL_ATTEMPT}",
            "allRootsMustBeFresh": True,
            "priorTargetAttempt001MustNotBeReusedOrMerged": True,
        },
        "execution": {
            "oracleBatchCount": 54,
            "oracleInputsPerBatch": 24,
            "strictSerialFreshUnityProcesses": True,
            "maximumConcurrentUnityProcesses": 1,
            "wholeSuperblockTechnicalReplacements": 0,
            "retryInSameAttempt": False,
            "resumeInSameAttempt": False,
            "topUpInSameAttempt": False,
            "mergeAcrossAttempts": False,
            "skip": False,
            "reorder": False,
            "parallelCompletion": False,
            "failurePolicy": "FAIL_CLOSED_PRESERVE_ALL_ROOTS_AND_REQUIRE_A_NEW_ATTEMPT",
        },
        "childAuthorizationPolicy": {
            "preissuedInputGenerationAuthorization": True,
            "collectionAuthorizationMayBeIssuedOnlyAfterInputFreeze": True,
            "collectionAuthorizationMustBindExactInputFreezeAndScheduleHashes": True,
            "acceptanceAuthorizationMayBeIssuedOnlyAfterRawAcquisitionFreeze": True,
            "acceptanceAuthorizationMustBindExactRawFreezeAndTerminalHashes": True,
            "childAuthorizationsMayNotExpandThisUmbrellaScope": True,
            "noAdditionalUserAuthorizationRequiredWithinThisScope": True,
        },
        "bindings": {
            "orchestratorRelativePath": ORCHESTRATOR_RELATIVE.as_posix(),
            "orchestratorSha256": orchestrator_sha,
            "readinessRelativePath": READINESS_RELATIVE.as_posix(),
            "readinessSha256": readiness_sha,
            "inputGenerationAuthorizationRelativePath": INPUT_AUTH_RELATIVE.as_posix(),
            "inputGenerationAuthorizationSha256": input_sha,
            "identityBindingRelativePath": IDENTITY_RELATIVE.as_posix(),
            "identityBindingSha256": "2a21042283b1197d2a66d7948aede3623b9c5e71ef2576c9f6534494c086dc5e",
            "formalImplementationManifestSha256": FROZEN_HASHES["Research/Gate14Re-ME/Execution/v5/formal-st-implementation-manifest.v5_0.json"],
            "formalAcquisitionContractSha256": FROZEN_HASHES["Research/Gate14Re-ME/Execution/v5/formal-st-acquisition-contract.v5_0.json"],
            "formalOperationalResourceBudgetSha256": FROZEN_HASHES["Research/Gate14Re-ME/Execution/v5/formal-st-operational-resource-budget.v5_0.json"],
            "qualifiedSixAlgorithmFairnessBindingSha256": FROZEN_HASHES[FAIRNESS_RELATIVE.as_posix()],
            "formalAcceptanceContractSha256": FROZEN_HASHES["Research/Gate14Re-ME/Execution/v5/formal-st-independent-acceptance-contract.v5_0.json"],
        },
        "deployment": {
            "unityEditorInstallerBundled": False,
            "unityHubInstallerBundled": False,
            "exactUnityMustBePreinstalled": True,
            "expectedUnityExecutableSha256": UNITY_SHA256,
        },
        "terminalBoundary": {
            "requiredStatus": "PASS_ACCEPTED_FORMAL_ST_DATA_PACKAGE_READY_FORMAL_ANALYSIS_NOT_RUN",
            "acceptedSuperblocks": 1296,
            "namedAlgorithmLanes": 7776,
            "typedParquetFullRoundTripRequired": True,
            "sourceMeasuredRootWriteBackPermitted": False,
            "formalAnalysisMustRemainNotRun": True,
            "mqMustRemainNotRun": True,
            "mtMustRemainNotRun": True,
        },
    }


def make_build_authorization() -> dict[str, Any]:
    return {
        "schema": "gate14re-me-formal-st-migration-package-build-authorization-v1",
        "studyId": "Gate14Re-ME",
        "designId": "gate14re-me-formal-st-bounded-gnf-v5",
        "authorizationId": "gate14re-me-formal-st-v5-package-build-attempt-005",
        "status": "AUTHORIZED_PACKAGE_BUILD_AND_VALIDATION_ONLY",
        "userAuthorizationVerbatim": USER_SCOPE_STATEMENTS,
        "userScopeSha256": USER_SCOPE_SHA256,
        "authorized": {
            "createFreshPackageStagingRoot": True,
            "createFreshPackageBuildRoot": True,
            "createFreshPackageTestRoot": True,
            "copyCompleteResearchSnapshotExceptFormalRunsAndPackageOutputRoots": True,
            "copyUnityInstaller": False,
            "copyUnityHubInstaller": False,
            "buildZip64Archive": True,
            "extractAndValidatePackage": True,
            "algorithmFreeCompileReadiness": True,
        },
        "prohibited": {
            "unityEditorInstallerInArchive": True,
            "unityHubInstallerInArchive": True,
            "credentialCopy": True,
            "credentialsInArchive": True,
            "formalInputOrScheduleMaterialization": True,
            "formalMeasuredOrDeliveryRootCreation": True,
            "formalSTCollection": True,
            "formalAnalysis": True,
            "MQ": True,
            "MT": True,
        },
        "researchInclusionPolicy": {
            "requested": "all files below Research except Research/FormalRuns",
            "effectiveSourceSnapshotExclusions": PACKAGE_OUTPUT_EXPLANATION,
            "allOtherResearchFilesRequired": True,
        },
        "priorPackageAttempt": {
            "terminalRelativePath": "Research/Verification/Gate14Re-ME/formal-st-migration-package-build-attempt-004/terminal-receipt.v1.json",
            "terminalSha256": "6451ae0e03eed02ab7ad0e906c75403e5978cf4136756a580785a668fca521df",
            "supersededForTransferBecauseSemanticSpecificationClosureWasIncomplete": True,
            "mustNotBeModifiedOrReusedAsSuccessor": True,
        },
        "frozenFormalSTFreezeIndex": {
            "relativePath": "Research/Gate14Re-ME/Execution/v5/formal-st-freeze-index.v5_0.json",
            "sha256": FROZEN_HASHES["Research/Gate14Re-ME/Execution/v5/formal-st-freeze-index.v5_0.json"],
        },
        "roots": {
            "staging": STAGING_RELATIVE.as_posix(),
            "build": BUILD_RELATIVE.as_posix(),
            "test": TEST_RELATIVE.as_posix(),
            "evidence": EVIDENCE_RELATIVE.as_posix(),
        },
        "authorizedAtUtc": utc_now(),
    }


def make_plan() -> dict[str, Any]:
    return {
        "schema": "gate14re-me-formal-st-migration-package-build-plan-v2",
        "status": "FROZEN_ATTEMPT_005_PLAN_BEFORE_MUTATION",
        "packageId": PACKAGE_ID,
        "userScopeSha256": USER_SCOPE_SHA256,
        "scope": {
            "researchSource": "Research/**",
            "explicitExclusions": PACKAGE_OUTPUT_EXPLANATION,
            "projectPayload": ["Assets/_Scripts", "Assets/Plugins", "Packages", "ProjectSettings"],
            "portableRuntimes": ["Python", "PowerShell"],
            "unityEditorInstaller": False,
            "unityHubInstaller": False,
        },
        "tests": [
            "frozen-hash validation",
            "complete Research source inventory reconciliation",
            "six-algorithm implementation/specification semantic closure",
            "credential and Unity-installer exclusion",
            "complete per-file manifest validation",
            "authorization-chain dry run",
            "ZIP64 CRC and fresh extraction",
            "algorithm-free Unity compile/readiness using exact preinstalled Unity",
        ],
        "failurePolicy": "FAIL_CLOSED_PRESERVE_ATTEMPT_005_ROOTS_NO_SAME_ATTEMPT_RETRY",
        "formalExecutionBoundary": {
            "formalInputsCreated": 0,
            "formalCollectionStarted": False,
            "formalAnalysisStarted": False,
            "mqStarted": False,
            "mtStarted": False,
        },
        "plannedAtUtc": utc_now(),
    }


def make_user_receipt() -> dict[str, Any]:
    calculated = sha256_text("\n".join(USER_SCOPE_STATEMENTS))
    require(calculated == USER_SCOPE_SHA256, "user-scope statement hash mismatch")
    return {
        "schema": "gate14re-me-formal-st-migration-package-user-authorization-receipt-v2",
        "status": "AUTHORIZED_FRESH_RECOVERY_PACKAGE_BUILD_AND_ALGORITHM_FREE_VALIDATION",
        "statements": USER_SCOPE_STATEMENTS,
        "statementJoinRule": "UTF-8, LF between statements, no trailing LF",
        "userScopeSha256": USER_SCOPE_SHA256,
        "interpretation": (
            "Build a fresh package that includes the complete current Research file snapshot except FormalRuns and unavoidable package-output roots; "
            "do not bundle Unity Editor or Unity Hub installers; preserve the prior package and do not start formal ST."
        ),
        "receivedAtUtc": utc_now(),
    }


def copy_project_payload(project_root: Path, stage_root: Path) -> None:
    def ignore_generated(_directory: str, names: Sequence[str]) -> set[str]:
        ignored = set()
        for name in names:
            if name in {"Library", "Temp", "Logs", "obj", ".git", "__pycache__"}:
                ignored.add(name)
            if name.lower().endswith((".pyc", ".pyo")):
                ignored.add(name)
        return ignored

    for relative in ("Assets/_Scripts", "Assets/Plugins", "Packages", "ProjectSettings"):
        source = project_root / relative
        target = stage_root / relative
        require(source.is_dir(), f"project payload directory is missing: {relative}")
        require(not target.exists(), f"project payload target already exists: {relative}")
        shutil.copytree(source, target, copy_function=shutil.copy2, ignore=ignore_generated)
    for relative in ("Assets/_Scripts.meta", "Assets/Plugins.meta"):
        source = project_root / relative
        require(source.is_file(), f"project payload file is missing: {relative}")
        target = stage_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def copy_research_snapshot(project_root: Path, stage_root: Path) -> dict[str, Any]:
    source_files = sorted(source_research_files(project_root), key=lambda path: relative_posix(path, project_root))
    inventory_path = stage_root / RESEARCH_INVENTORY_RELATIVE
    inventory_path.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    total_bytes = 0
    with inventory_path.open("x", encoding="utf-8", newline="\n") as inventory:
        for source in source_files:
            relative = relative_posix(source, project_root)
            require(not is_credential_like(relative), f"credential-like source file is prohibited: {relative}")
            require(not is_unity_installer_like(relative), f"Unity installer-like source file is prohibited: {relative}")
            target = stage_root / relative
            require(not target.exists(), f"Research target collision: {relative}")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            source_sha = sha256_file(source)
            require(sha256_file(target) == source_sha, f"Research copy SHA-256 mismatch: {relative}")
            row = {
                "relativePath": relative,
                "bytes": source.stat().st_size,
                "sha256": source_sha,
            }
            line = canonical_json(row) + "\n"
            inventory.write(line)
            digest.update(line.encode("utf-8"))
            total_bytes += source.stat().st_size
    summary = {
        "schema": "gate14re-me-formal-st-research-source-inventory-summary-v2",
        "status": "PASS_COMPLETE_RESEARCH_SNAPSHOT_WITH_EXPLICIT_OUTPUT_EXCLUSIONS",
        "snapshotAtUtc": utc_now(),
        "sourceRoot": "Research",
        "includedSourceFiles": len(source_files),
        "includedSourceBytes": total_bytes,
        "inventoryRelativePath": RESEARCH_INVENTORY_RELATIVE.as_posix(),
        "inventorySha256": digest.hexdigest(),
        "inventorySelfExcluded": True,
        "explicitExclusions": PACKAGE_OUTPUT_EXPLANATION,
        "allOtherResearchFilesRequired": True,
    }
    write_json(stage_root / RESEARCH_INVENTORY_SUMMARY_RELATIVE, summary)
    return summary


def extract_portable_runtimes(project_root: Path, stage_root: Path, temp_inner: Path) -> dict[str, Any]:
    outer = project_root / OLD_OUTER_RELATIVE
    require(outer.is_file(), f"prior runtime source bundle is missing: {outer}")
    require(not temp_inner.exists(), f"runtime temporary inner archive already exists: {temp_inner}")
    with zipfile.ZipFile(outer, "r", allowZip64=True) as archive:
        names = archive.namelist()
        require(OLD_INNER_NAME in names, "prior outer bundle does not contain the expected canonical archive")
        require(not any(name.lower().endswith(("unityhubsetup.exe", "unityhub.msi")) for name in names), "unexpected outer Unity Hub entry")
        with archive.open(OLD_INNER_NAME, "r") as source, temp_inner.open("xb") as target:
            shutil.copyfileobj(source, target, length=8 * 1024 * 1024)
    require(sha256_file(temp_inner) == OLD_INNER_SHA256, "prior canonical archive SHA-256 mismatch")

    extracted = 0
    extracted_bytes = 0
    with zipfile.ZipFile(temp_inner, "r", allowZip64=True) as archive:
        for info in archive.infolist():
            normalized = Path(info.filename)
            require(not normalized.is_absolute() and ".." not in normalized.parts, f"unsafe prior ZIP path: {info.filename}")
            parts = normalized.parts
            if len(parts) < 3 or parts[1] != "MigrationRuntime" or parts[2] not in {"Python", "PowerShell"}:
                continue
            relative = Path(*parts[1:])
            require(not is_unity_installer_like(relative.as_posix()), f"installer entered runtime selection: {relative}")
            target = stage_root / relative
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            require(not target.exists(), f"runtime target collision: {relative}")
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info, "r") as source, target.open("xb") as output:
                shutil.copyfileobj(source, output, length=8 * 1024 * 1024)
            extracted += 1
            extracted_bytes += info.file_size
    require(extracted > 0, "no portable runtime files were extracted")
    python = stage_root / "MigrationRuntime/Python/python.exe"
    pwsh = stage_root / "MigrationRuntime/PowerShell/pwsh.exe"
    require(sha256_file(python) == PYTHON_SHA256, "portable Python SHA-256 mismatch")
    require(sha256_file(pwsh) == POWERSHELL_SHA256, "portable PowerShell SHA-256 mismatch")
    temp_inner.unlink()
    return {
        "status": "PASS_PORTABLE_RUNTIME_ONLY_NO_UNITY_INSTALLERS",
        "files": extracted,
        "bytes": extracted_bytes,
        "pythonSha256": PYTHON_SHA256,
        "powerShellSha256": POWERSHELL_SHA256,
        "temporaryPriorArchiveRemoved": True,
    }


def write_derived_package_files(project_root: Path, stage_root: Path) -> dict[str, str]:
    readiness = derive_readiness(project_root)
    input_auth = make_input_authorization()
    input_auth_text = json.dumps(input_auth, ensure_ascii=False, indent=2) + "\n"
    input_sha = sha256_text(input_auth_text)
    readiness_sha = sha256_text(readiness)
    orchestrator = derive_orchestrator(
        project_root,
        input_authorization_sha256=input_sha,
        readiness_sha256=readiness_sha,
    )
    orchestrator_sha = sha256_text(orchestrator)
    umbrella = make_umbrella(input_sha, orchestrator_sha, readiness_sha)

    write_text(stage_root / READINESS_RELATIVE, readiness)
    write_text(stage_root / ORCHESTRATOR_RELATIVE, orchestrator)
    write_text(stage_root / INPUT_AUTH_RELATIVE, input_auth_text)
    write_json(stage_root / UMBRELLA_RELATIVE, umbrella)

    start_cmd = r"""@echo off
setlocal
set "PACKAGE_ROOT=%~dp0"
set "PWSH=%PACKAGE_ROOT%MigrationRuntime\PowerShell\pwsh.exe"
set "SCRIPT=%PACKAGE_ROOT%Research\Gate14Re-ME\Package\v5\Install-And-Verify-Gate14ReMEFormalST.v5_2.ps1"
if not exist "%PWSH%" (
  echo Bundled PowerShell runtime is missing: %PWSH%
  exit /b 2
)
echo This package requires the exact preinstalled Unity 2022.3.30f1c1 editor.
echo No Unity Editor or Unity Hub installer is bundled.
"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" pause
exit /b %RESULT%
"""
    run_cmd = r"""@echo off
setlocal
set "PACKAGE_ROOT=%~dp0"
set "PWSH=%PACKAGE_ROOT%MigrationRuntime\PowerShell\pwsh.exe"
set "SCRIPT=%PACKAGE_ROOT%Research\Gate14Re-ME\Package\v5\Run-To-Accepted-Data-Package.v5_2.ps1"
if not exist "%PWSH%" (
  echo Bundled PowerShell runtime is missing: %PWSH%
  exit /b 2
)
echo.
echo Gate14Re-ME formal ST successor attempt-002 end-to-end run
echo Exact preinstalled Unity 2022.3.30f1c1 is required; no installer is bundled.
echo This deliberate launch may run for several days and stops at the accepted data package.
echo Formal analysis, MQ, MT, and credential packaging remain prohibited.
echo.
"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -ConfirmFormalCollection
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" pause
exit /b %RESULT%
"""
    write_text(stage_root / "START-HERE.cmd", start_cmd)
    write_text(stage_root / "RUN-TO-DATA-PACKAGE.cmd", run_cmd)

    chinese = f"""# Gate14Re-ME formal ST v5 恢复迁移包（attempt-005）

本包是 attempt-004 的全新后继包，修复了六算法规格文档未进入旧包的问题。包内包含构建时 `Research` 下除 `FormalRuns` 与打包输出目录以外的全部文件，并以逐文件 SHA-256 清单冻结。

## 重要边界

- 不包含 Unity Editor 安装包，也不包含 Unity Hub 安装包。
- 目标机必须预装 Unity `2022.3.30f1c1`，其 `Unity.exe` SHA-256 必须为 `{UNITY_SHA256}`；不匹配即 fail closed。
- `START-HERE.cmd` 只执行算法零实例化 readiness，不生成 formal inputs，不启动 formal ST。
- `RUN-TO-DATA-PACKAGE.cmd` 是明确的正式入口；只在你确实要启动全新 successor formal attempt-002 时运行。它在 accepted data package 处停止，不做 formal analysis、MQ 或 MT。
- 目标机上的旧 attempt-001 不得 retry、resume、top-up、merge 或复用。

## 完整性

顶层 `Research/Gate14Re-ME/Package/v5/package-manifest.v1.json` 列出包内每个文件的大小与 SHA-256。readiness 与正式入口均验证六份算法规格、六份实现及两份导航依赖的语义闭包。
"""
    english = f"""# Gate14Re-ME formal ST v5 recovery migration package (attempt-005)

This is a fresh successor to attempt-004. It repairs the missing six-algorithm specification closure and freezes every packaged file by SHA-256. The source snapshot includes every file under `Research` except `FormalRuns` and package-output roots that would recursively embed this or the superseded Unity-bearing package.

No Unity Editor or Unity Hub installer is bundled. The target must already have Unity 2022.3.30f1c1 with `Unity.exe` SHA-256 `{UNITY_SHA256}`. `START-HERE.cmd` performs algorithm-free readiness only. `RUN-TO-DATA-PACKAGE.cmd` deliberately starts fresh successor formal attempt-002 and stops at the accepted data package; formal analysis, MQ, and MT remain unauthorized.
"""
    write_text(stage_root / "README-中文.md", chinese)
    write_text(stage_root / "README-English.md", english)
    return {
        "readinessSha256": readiness_sha,
        "inputAuthorizationSha256": input_sha,
        "orchestratorSha256": orchestrator_sha,
        "umbrellaAuthorizationSha256": sha256_file(stage_root / UMBRELLA_RELATIVE),
    }


def build_manifest(stage_root: Path, derived: dict[str, str], research_summary: dict[str, Any]) -> dict[str, Any]:
    manifest_path = stage_root / MANIFEST_RELATIVE
    require(not manifest_path.exists(), "package manifest already exists")
    files: list[dict[str, Any]] = []
    total_bytes = 0
    credential_hits: list[str] = []
    installer_hits: list[str] = []
    for path in package_files(stage_root):
        relative = relative_posix(path, stage_root)
        if is_credential_like(relative):
            credential_hits.append(relative)
        if is_unity_installer_like(relative):
            installer_hits.append(relative)
        size = path.stat().st_size
        files.append({"relativePath": relative, "bytes": size, "sha256": sha256_file(path)})
        total_bytes += size
    require(not credential_hits, f"credential-like files detected: {credential_hits[:20]}")
    require(not installer_hits, f"Unity installer-like files detected: {installer_hits[:20]}")
    umbrella_sha = sha256_file(stage_root / UMBRELLA_RELATIVE)
    require(umbrella_sha == derived["umbrellaAuthorizationSha256"], "umbrella hash drifted before manifest")
    manifest = {
        "schema": MANIFEST_SCHEMA,
        "studyId": "Gate14Re-ME",
        "designId": "gate14re-me-formal-st-bounded-gnf-v5",
        "packageId": PACKAGE_ID,
        "status": MANIFEST_STATUS,
        "createdAtUtc": utc_now(),
        "manifestSelfExcluded": True,
        "fileCount": len(files),
        "totalBytes": total_bytes,
        "files": files,
        "frozenFormalSTFreezeIndexSha256": FROZEN_HASHES["Research/Gate14Re-ME/Execution/v5/formal-st-freeze-index.v5_0.json"],
        "researchInclusionPolicy": {
            "status": "PASS_COMPLETE_RESEARCH_SNAPSHOT_WITH_EXPLICIT_OUTPUT_EXCLUSIONS",
            "requestedScope": "all files below Research except Research/FormalRuns",
            "effectiveExclusions": PACKAGE_OUTPUT_EXPLANATION,
            "allOtherResearchFilesRequired": True,
            "includedSourceFiles": research_summary["includedSourceFiles"],
            "includedSourceBytes": research_summary["includedSourceBytes"],
            "sourceInventoryRelativePath": RESEARCH_INVENTORY_RELATIVE.as_posix(),
            "sourceInventorySha256": research_summary["inventorySha256"],
        },
        "semanticDependencyClosure": {
            "fairnessBindingRelativePath": FAIRNESS_RELATIVE.as_posix(),
            "fairnessBindingSha256": FROZEN_HASHES[FAIRNESS_RELATIVE.as_posix()],
            "algorithms": 6,
            "implementationFiles": 6,
            "specificationFiles": 6,
            "navigationDependencyFiles": 2,
            "totalBoundFiles": 14,
        },
        "unityProvisioning": {
            "unityEditorInstallerBundled": False,
            "unityHubInstallerBundled": False,
            "exactPreinstalledUnityRequired": True,
            "unityVersion": "2022.3.30f1c1",
            "unityExecutableSha256": UNITY_SHA256,
        },
        "portableRuntime": {
            "pythonRelativePath": "MigrationRuntime/Python/python.exe",
            "pythonSha256": PYTHON_SHA256,
            "powerShellRelativePath": "MigrationRuntime/PowerShell/pwsh.exe",
            "powerShellSha256": POWERSHELL_SHA256,
        },
        "authorizationModel": "CONTINUING_USER_AUTHORIZED_FRESH_SUCCESSOR_ATTEMPT_THROUGH_ACCEPTED_DATA_PACKAGE",
        "endToEndAuthorization": {
            "umbrellaRelativePath": UMBRELLA_RELATIVE.as_posix(),
            "umbrellaSha256": umbrella_sha,
            "orchestratorRelativePath": ORCHESTRATOR_RELATIVE.as_posix(),
            "orchestratorSha256": derived["orchestratorSha256"],
            "readinessRelativePath": READINESS_RELATIVE.as_posix(),
            "readinessSha256": derived["readinessSha256"],
            "inputGenerationAuthorizationRelativePath": INPUT_AUTH_RELATIVE.as_posix(),
            "inputGenerationAuthorizationSha256": derived["inputAuthorizationSha256"],
            "identityBindingRelativePath": IDENTITY_RELATIVE.as_posix(),
            "identityBindingSha256": "2a21042283b1197d2a66d7948aede3623b9c5e71ef2576c9f6534494c086dc5e",
            "formalAttempt": FORMAL_ATTEMPT,
            "terminalBoundary": "ACCEPTED_DATA_PACKAGE_READY_FORMAL_ANALYSIS_NOT_RUN",
        },
        "availableEntryPoints": {
            "readinessOnly": "START-HERE.cmd",
            "runThroughAcceptedDataPackage": "RUN-TO-DATA-PACKAGE.cmd",
        },
        "credentialPolicy": {
            "credentialLikeFiles": 0,
            "credentialsCopied": False,
            "credentialsPermittedInZip": False,
        },
        "formalInputsCreated": 0,
        "formalScheduleRowsCreated": 0,
        "formalCollectionStarted": False,
        "formalAcceptedDataPackagesCreated": 0,
        "formalAnalysisStarted": False,
        "mqStarted": False,
        "mtStarted": False,
    }
    write_json(manifest_path, manifest)
    return {
        "status": MANIFEST_STATUS,
        "manifestRelativePath": MANIFEST_RELATIVE.as_posix(),
        "manifestSha256": sha256_file(manifest_path),
        "fileCount": len(files),
        "totalBytes": total_bytes,
        "credentialLikeFiles": 0,
        "unityInstallerFiles": 0,
    }


def verify_package(root: Path) -> dict[str, Any]:
    manifest_path = root / MANIFEST_RELATIVE
    require(manifest_path.is_file(), "package manifest is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    require(manifest.get("schema") == MANIFEST_SCHEMA and manifest.get("status") == MANIFEST_STATUS, "package manifest header mismatch")
    require(manifest.get("packageId") == PACKAGE_ID, "package ID mismatch")
    require(manifest.get("unityProvisioning", {}).get("unityEditorInstallerBundled") is False, "Unity Editor installer policy mismatch")
    require(manifest.get("unityProvisioning", {}).get("unityHubInstallerBundled") is False, "Unity Hub installer policy mismatch")
    expected: dict[str, dict[str, Any]] = {}
    total_bytes = 0
    for entry in manifest.get("files", []):
        relative = entry.get("relativePath")
        require(isinstance(relative, str) and relative and relative not in expected, "invalid or duplicate manifest path")
        require(not is_credential_like(relative), f"credential-like manifest path: {relative}")
        require(not is_unity_installer_like(relative), f"Unity installer-like manifest path: {relative}")
        path = (root / relative).resolve()
        try:
            path.relative_to(root.resolve())
        except ValueError as exc:
            raise PackageError(f"manifest path escapes package root: {relative}") from exc
        require(path.is_file(), f"manifest file is missing: {relative}")
        require(path.stat().st_size == entry.get("bytes"), f"manifest byte mismatch: {relative}")
        require(sha256_file(path) == entry.get("sha256"), f"manifest SHA-256 mismatch: {relative}")
        expected[relative] = entry
        total_bytes += path.stat().st_size
    require(len(expected) == manifest.get("fileCount"), "manifest fileCount mismatch")
    require(total_bytes == manifest.get("totalBytes"), "manifest totalBytes mismatch")
    actual = {
        relative_posix(path, root)
        for path in package_files(root, exclude_manifest=True)
    }
    require(actual == set(expected), f"package file-set mismatch: extra={sorted(actual-set(expected))[:10]} missing={sorted(set(expected)-actual)[:10]}")
    closure = semantic_closure(root)
    for entry in closure:
        relative = entry["relativePath"]
        require(relative in expected, f"semantic dependency is not manifest-listed: {relative}")
        require(expected[relative]["sha256"] == entry["sha256"], f"semantic dependency manifest hash mismatch: {relative}")
    source_summary = json.loads((root / RESEARCH_INVENTORY_SUMMARY_RELATIVE).read_text(encoding="utf-8-sig"))
    require(source_summary.get("status") == "PASS_COMPLETE_RESEARCH_SNAPSHOT_WITH_EXPLICIT_OUTPUT_EXCLUSIONS", "Research inventory summary mismatch")
    inventory_path = root / RESEARCH_INVENTORY_RELATIVE
    require(sha256_file(inventory_path) == source_summary.get("inventorySha256"), "Research source inventory SHA-256 mismatch")
    inventory_paths: set[str] = set()
    with inventory_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            row = json.loads(line)
            relative = row["relativePath"]
            require(relative not in inventory_paths, f"duplicate Research inventory path: {relative}")
            inventory_paths.add(relative)
            require(relative in expected, f"source Research file is missing from package manifest: {relative}")
            require(expected[relative]["sha256"] == row["sha256"] and expected[relative]["bytes"] == row["bytes"], f"source Research inventory/manifest mismatch: {relative}")
    require(len(inventory_paths) == source_summary.get("includedSourceFiles"), "Research inventory cardinality mismatch")
    require(not (root / "Research/FormalRuns").exists(), "Research/FormalRuns entered package")
    require(not (root / "Research/Packages").exists(), "Research/Packages entered package")
    require(not (root / "Research/PackageStaging").exists(), "Research/PackageStaging entered package")
    require(not (root / "Research/PackageTests").exists(), "Research/PackageTests entered package")
    installer_hits = [relative for relative in actual if is_unity_installer_like(relative)]
    credential_hits = [relative for relative in actual if is_credential_like(relative)]
    require(not installer_hits, f"Unity installer-like files detected: {installer_hits[:20]}")
    require(not credential_hits, f"credential-like files detected: {credential_hits[:20]}")
    return {
        "status": "PASS_COMPLETE_HASH_SCOPE_SEMANTIC_CLOSURE_AND_INSTALLER_EXCLUSION",
        "manifestSha256": sha256_file(manifest_path),
        "fileCount": len(expected),
        "totalBytes": total_bytes,
        "researchSourceFiles": len(inventory_paths),
        "semanticDependencyFiles": len(closure),
        "algorithmSpecificationFiles": sum(1 for entry in closure if entry["role"] == "specification"),
        "credentialLikeFiles": 0,
        "unityEditorInstallerFiles": 0,
        "unityHubInstallerFiles": 0,
    }


def build_archive(package_root: Path, archive_path: Path) -> dict[str, Any]:
    require(not archive_path.exists(), f"archive already exists: {archive_path}")
    verified = verify_package(package_root)
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    paths = package_files(package_root)
    started = time.perf_counter()
    with zipfile.ZipFile(archive_path, "x", allowZip64=True) as archive:
        for path in paths:
            relative = relative_posix(path, package_root)
            require(not is_credential_like(relative), f"credential-like file blocked before ZIP: {relative}")
            require(not is_unity_installer_like(relative), f"Unity installer-like file blocked before ZIP: {relative}")
            compression = zipfile.ZIP_STORED if path.stat().st_size >= 256 * 1024 * 1024 else zipfile.ZIP_DEFLATED
            archive.write(
                path,
                f"{ARCHIVE_PREFIX}/{relative}",
                compress_type=compression,
                compresslevel=None if compression == zipfile.ZIP_STORED else 1,
            )
    with zipfile.ZipFile(archive_path, "r", allowZip64=True) as archive:
        bad = archive.testzip()
        require(bad is None, f"ZIP CRC failure: {bad}")
        require(len(archive.infolist()) == len(paths), "ZIP entry cardinality mismatch")
    return {
        "status": "PASS_ZIP64_BUILD_AND_FULL_CRC",
        "archive": str(archive_path),
        "bytes": archive_path.stat().st_size,
        "sha256": sha256_file(archive_path),
        "entries": len(paths),
        "packageManifestSha256": verified["manifestSha256"],
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def extract_archive(archive_path: Path, test_root: Path) -> tuple[Path, dict[str, Any]]:
    require(not test_root.exists(), f"test root already exists: {test_root}")
    test_root.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    with zipfile.ZipFile(archive_path, "r", allowZip64=True) as archive:
        for info in archive.infolist():
            path = Path(info.filename)
            require(not path.is_absolute() and ".." not in path.parts, f"unsafe ZIP entry: {info.filename}")
            require(info.filename.startswith(ARCHIVE_PREFIX + "/"), f"unexpected ZIP prefix: {info.filename}")
            relative = info.filename[len(ARCHIVE_PREFIX) + 1 :]
            require(not is_credential_like(relative), f"credential-like ZIP entry: {relative}")
            require(not is_unity_installer_like(relative), f"Unity installer-like ZIP entry: {relative}")
        archive.extractall(test_root)
    package_root = test_root / ARCHIVE_PREFIX
    verified = verify_package(package_root)
    return package_root, {
        "status": "PASS_FRESH_EXTRACTION_COMPLETE_HASH_SCOPE_AND_SEMANTIC_CLOSURE",
        "archiveSha256": sha256_file(archive_path),
        "extractedPackageRoot": str(package_root),
        "fileCount": verified["fileCount"],
        "totalBytes": verified["totalBytes"],
        "researchSourceFiles": verified["researchSourceFiles"],
        "algorithmSpecificationFiles": verified["algorithmSpecificationFiles"],
        "credentialLikeFiles": 0,
        "unityInstallerFiles": 0,
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def run_checked(command: list[str], *, cwd: Path, label: str, timeout: int | None = None) -> dict[str, Any]:
    started = time.perf_counter()
    result = subprocess.run(command, cwd=str(cwd), text=True, capture_output=True, timeout=timeout, check=False)
    require(result.returncode == 0, f"{label} failed with exit code {result.returncode}: {result.stderr[-4000:]} {result.stdout[-4000:]}")
    return {
        "status": "PASS",
        "label": label,
        "exitCode": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }


def preflight(project_root: Path, *, require_fresh: bool = True) -> dict[str, Any]:
    verify_frozen_hashes(project_root)
    closure = semantic_closure(project_root)
    calculated_scope = sha256_text("\n".join(USER_SCOPE_STATEMENTS))
    require(calculated_scope == USER_SCOPE_SHA256, "user authorization scope hash mismatch")
    outer = project_root / OLD_OUTER_RELATIVE
    require(outer.is_file(), "prior package used as runtime source is missing")
    with zipfile.ZipFile(outer, "r", allowZip64=True) as archive:
        require(OLD_INNER_NAME in archive.namelist(), "prior outer package inner archive is missing")
    unity = project_root.parent / "UnityEditor/2022.3.30f1c1/Editor/Unity.exe"
    if not unity.is_file():
        unity = Path("H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe")
    require(unity.is_file(), "exact preinstalled Unity executable is missing")
    require(sha256_file(unity) == UNITY_SHA256, "preinstalled Unity executable SHA-256 mismatch")
    if require_fresh:
        for relative in (STAGING_RELATIVE, BUILD_RELATIVE, TEST_RELATIVE, EVIDENCE_RELATIVE):
            require(not (project_root / relative).exists(), f"attempt-005 root is not fresh: {relative.as_posix()}")
    source_files = list(source_research_files(project_root))
    credential_hits = [relative_posix(path, project_root) for path in source_files if is_credential_like(relative_posix(path, project_root))]
    installer_hits = [relative_posix(path, project_root) for path in source_files if is_unity_installer_like(relative_posix(path, project_root))]
    require(not credential_hits, f"credential-like source files detected: {credential_hits[:20]}")
    require(not installer_hits, f"Unity installer-like source files detected: {installer_hits[:20]}")
    pwsh_candidates = [
        Path("C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe"),
        Path(shutil.which("pwsh") or ""),
    ]
    pwsh = next((path for path in pwsh_candidates if path and path.is_file()), None)
    require(pwsh is not None, "PowerShell parser runtime is unavailable")
    readiness = derive_readiness(project_root)
    input_text = json.dumps(make_input_authorization(), ensure_ascii=False, indent=2) + "\n"
    orchestrator = derive_orchestrator(
        project_root,
        input_authorization_sha256=sha256_text(input_text),
        readiness_sha256=sha256_text(readiness),
    )
    parse_powershell(readiness, pwsh, "derived readiness")
    parse_powershell(orchestrator, pwsh, "derived orchestrator")
    return {
        "schema": "gate14re-me-formal-st-recovery-package-preflight-v2",
        "status": "PASS_READ_ONLY_PREFLIGHT_READY_FOR_FRESH_ATTEMPT_005",
        "checkedAtUtc": utc_now(),
        "researchSourceFiles": len(source_files),
        "researchSourceBytes": sum(path.stat().st_size for path in source_files),
        "semanticDependencyFiles": len(closure),
        "algorithmImplementationFiles": sum(1 for entry in closure if entry["role"] == "implementation"),
        "algorithmSpecificationFiles": sum(1 for entry in closure if entry["role"] == "specification"),
        "credentialLikeFiles": 0,
        "unityInstallerFiles": 0,
        "unityExecutable": str(unity).replace("\\", "/"),
        "unitySha256": UNITY_SHA256,
        "unityEditorInstallerBundled": False,
        "unityHubInstallerBundled": False,
        "derivedPowerShellParse": "PASS",
        "formalInputsCreated": 0,
        "formalCollectionStarted": False,
        "formalAnalysisStarted": False,
        "mqStarted": False,
        "mtStarted": False,
    }


def build_all(project_root: Path) -> dict[str, Any]:
    initial = preflight(project_root, require_fresh=True)
    evidence_root = project_root / EVIDENCE_RELATIVE
    staging_parent = project_root / STAGING_RELATIVE
    build_root = project_root / BUILD_RELATIVE
    test_root = project_root / TEST_RELATIVE
    stage_root = staging_parent / ARCHIVE_PREFIX
    archive_path = build_root / f"{ARCHIVE_STEM}.zip"
    phase = "EVIDENCE_INITIALIZATION"
    started = time.perf_counter()
    evidence_root.mkdir(parents=True, exist_ok=False)
    try:
        write_json(evidence_root / "user-authorization-receipt.v2.json", make_user_receipt())
        write_json(evidence_root / "package-build-authorization.v1.json", make_build_authorization())
        write_json(evidence_root / "package-build-plan.v2.json", make_plan())
        write_json(evidence_root / "preflight-receipt.v2.json", initial)

        phase = "STAGING"
        staging_parent.mkdir(parents=True, exist_ok=False)
        stage_root.mkdir(parents=True, exist_ok=False)
        copy_project_payload(project_root, stage_root)
        research_summary = copy_research_snapshot(project_root, stage_root)
        runtime_receipt = extract_portable_runtimes(
            project_root,
            stage_root,
            staging_parent / "runtime-source-attempt-004.tmp.zip",
        )
        derived = write_derived_package_files(project_root, stage_root)
        parse_powershell(
            (stage_root / READINESS_RELATIVE).read_text(encoding="utf-8-sig"),
            stage_root / "MigrationRuntime/PowerShell/pwsh.exe",
            "staged readiness",
        )
        parse_powershell(
            (stage_root / ORCHESTRATOR_RELATIVE).read_text(encoding="utf-8-sig"),
            stage_root / "MigrationRuntime/PowerShell/pwsh.exe",
            "staged orchestrator",
        )

        phase = "MANIFEST_AND_STAGING_VERIFICATION"
        manifest_receipt = build_manifest(stage_root, derived, research_summary)
        stage_verify = verify_package(stage_root)
        write_json(
            evidence_root / "staging-and-manifest-test.v2.json",
            {
                "schema": "gate14re-me-formal-st-staging-and-manifest-test-v2",
                "status": "PASS_STAGING_COMPLETE_MANIFEST_EXACT",
                "manifest": manifest_receipt,
                "verification": stage_verify,
                "portableRuntime": runtime_receipt,
                "testedAtUtc": utc_now(),
            },
        )
        write_json(
            evidence_root / "research-scope-completeness.v2.json",
            {
                "schema": "gate14re-me-formal-st-research-scope-completeness-v2",
                "status": "PASS_COMPLETE_RESEARCH_SNAPSHOT_WITH_EXPLICIT_OUTPUT_EXCLUSIONS",
                **research_summary,
                "packageManifestSha256": manifest_receipt["manifestSha256"],
                "testedAtUtc": utc_now(),
            },
        )
        closure = semantic_closure(stage_root)
        write_json(
            evidence_root / "semantic-dependency-closure.v2.json",
            {
                "schema": "gate14re-me-formal-st-semantic-dependency-closure-v2",
                "status": "PASS_SIX_ALGORITHM_SPECIFICATION_AND_IMPLEMENTATION_CLOSURE",
                "fairnessBindingSha256": FROZEN_HASHES[FAIRNESS_RELATIVE.as_posix()],
                "boundFileCount": len(closure),
                "algorithmSpecificationFiles": 6,
                "algorithmImplementationFiles": 6,
                "navigationDependencyFiles": 2,
                "files": closure,
                "testedAtUtc": utc_now(),
            },
        )

        phase = "STAGED_AUTHORIZATION_DRY_RUN"
        dry_run = run_checked(
            [
                str(stage_root / "MigrationRuntime/PowerShell/pwsh.exe"),
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(stage_root / ORCHESTRATOR_RELATIVE),
                "-ValidateAuthorizationChainOnly",
            ],
            cwd=stage_root,
            label="staged authorization chain dry run",
            timeout=600,
        )
        require("PASS_END_TO_END_AUTHORIZATION_CHAIN_DRY_RUN_NO_FORMAL_EXECUTION" in dry_run["stdout"], "staged dry-run terminal status missing")

        phase = "ZIP64_ARCHIVE"
        build_root.mkdir(parents=True, exist_ok=False)
        archive_receipt = build_archive(stage_root, archive_path)
        write_text(
            build_root / f"{ARCHIVE_STEM}.zip.sha256",
            f"{archive_receipt['sha256']} *{ARCHIVE_STEM}.zip\n",
        )

        phase = "FRESH_EXTRACTION"
        extracted_root, extraction_receipt = extract_archive(archive_path, test_root)
        extracted_dry_run = run_checked(
            [
                str(extracted_root / "MigrationRuntime/PowerShell/pwsh.exe"),
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(extracted_root / ORCHESTRATOR_RELATIVE),
                "-ValidateAuthorizationChainOnly",
            ],
            cwd=extracted_root,
            label="fresh-extraction authorization chain dry run",
            timeout=600,
        )
        require("PASS_END_TO_END_AUTHORIZATION_CHAIN_DRY_RUN_NO_FORMAL_EXECUTION" in extracted_dry_run["stdout"], "extracted dry-run terminal status missing")
        write_json(
            evidence_root / "authorization-chain-dry-run-test.v2.json",
            {
                "schema": "gate14re-me-formal-st-authorization-chain-dry-run-test-v2",
                "status": "PASS_STAGED_AND_FRESH_EXTRACTION_AUTHORIZATION_CHAIN_NO_FORMAL_EXECUTION",
                "staged": dry_run,
                "freshExtraction": extracted_dry_run,
                "formalInputsCreated": 0,
                "formalCollectionStarted": False,
                "formalAnalysisStarted": False,
                "testedAtUtc": utc_now(),
            },
        )
        write_json(
            evidence_root / "archive-and-fresh-extraction-test.v2.json",
            {
                "schema": "gate14re-me-formal-st-archive-and-fresh-extraction-test-v2",
                "status": "PASS_ZIP64_CRC_FRESH_EXTRACTION_COMPLETE_HASH_AND_SCOPE",
                "archive": archive_receipt,
                "extraction": extraction_receipt,
                "testedAtUtc": utc_now(),
            },
        )

        phase = "ALGORITHM_FREE_READINESS"
        readiness_receipt_root = test_root / "algorithm-free-readiness-evidence"
        unity_path = Path(initial["unityExecutable"])
        readiness_run = run_checked(
            [
                str(extracted_root / "MigrationRuntime/PowerShell/pwsh.exe"),
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(extracted_root / READINESS_RELATIVE),
                "-UnityExecutable",
                str(unity_path),
                "-ReceiptRoot",
                str(readiness_receipt_root),
            ],
            cwd=extracted_root,
            label="fresh-extraction algorithm-free readiness",
            timeout=7200,
        )
        readiness_terminal_path = readiness_receipt_root / "deployment-readiness-terminal.v1.json"
        require(readiness_terminal_path.is_file(), "algorithm-free readiness terminal is missing")
        readiness_terminal = json.loads(readiness_terminal_path.read_text(encoding="utf-8-sig"))
        require(
            readiness_terminal.get("status") == "PASS_MIGRATION_PACKAGE_PREINSTALLED_UNITY_AND_ALGORITHM_FREE_READINESS",
            "algorithm-free readiness terminal is not PASS",
        )
        require(readiness_terminal.get("formalCollectionStarted") is False, "readiness started formal collection")
        require(readiness_terminal.get("formalAnalysisStarted") is False, "readiness started formal analysis")
        require(readiness_terminal.get("semanticDependencyClosureFiles") == 14, "readiness semantic closure mismatch")
        require(readiness_terminal.get("algorithmSpecificationFiles") == 6, "readiness specification closure mismatch")
        write_json(
            evidence_root / "algorithm-free-readiness-test.v2.json",
            {
                "schema": "gate14re-me-formal-st-algorithm-free-readiness-test-v2",
                "status": "PASS_PREINSTALLED_UNITY_ALGORITHM_FREE_READINESS_FORMAL_ST_NOT_STARTED",
                "process": readiness_run,
                "terminalRelativeToTestRoot": relative_posix(readiness_terminal_path, test_root),
                "terminalSha256": sha256_file(readiness_terminal_path),
                "terminal": readiness_terminal,
                "unityEditorInstallerBundled": False,
                "unityHubInstallerBundled": False,
                "testedAtUtc": utc_now(),
            },
        )

        phase = "RELEASE_AND_EVIDENCE_SEAL"
        release_readme = f"""# Gate14Re-ME formal ST v5 recovery package attempt-005

- Archive: `{ARCHIVE_STEM}.zip`
- SHA-256: `{archive_receipt['sha256']}`
- Bytes: `{archive_receipt['bytes']}`
- Package manifest SHA-256: `{manifest_receipt['manifestSha256']}`
- Source Research files included: `{research_summary['includedSourceFiles']}`
- Source Research bytes included: `{research_summary['includedSourceBytes']}`
- Six algorithm specifications: PASS (6/6)
- Six algorithm implementations: PASS (6/6)
- Unity Editor installer bundled: no
- Unity Hub installer bundled: no
- Algorithm-free readiness: PASS
- Formal ST collection started during build: no
- Formal analysis/MQ/MT started: no

`Research/FormalRuns` and package-output roots are excluded. All other source files under `Research` at the frozen snapshot cutoff are listed in the inventory inside the archive.
"""
        write_text(build_root / "README-中文与English.md", release_readme)
        terminal = {
            "schema": "gate14re-me-formal-st-migration-package-build-terminal-v2",
            "status": "PASS_RECOVERY_MIGRATION_PACKAGE_READY_FORMAL_ST_NOT_STARTED",
            "packageId": PACKAGE_ID,
            "archiveRelativePath": relative_posix(archive_path, project_root),
            "archiveBytes": archive_receipt["bytes"],
            "archiveSha256": archive_receipt["sha256"],
            "packageManifestSha256": manifest_receipt["manifestSha256"],
            "packageFiles": manifest_receipt["fileCount"] + 1,
            "packagePayloadBytes": manifest_receipt["totalBytes"],
            "researchSourceFiles": research_summary["includedSourceFiles"],
            "researchSourceBytes": research_summary["includedSourceBytes"],
            "semanticDependencyFiles": 14,
            "algorithmSpecificationFiles": 6,
            "algorithmImplementationFiles": 6,
            "credentialLikeFiles": 0,
            "unityEditorInstallerFiles": 0,
            "unityHubInstallerFiles": 0,
            "algorithmFreeReadiness": "PASS",
            "formalAttemptPrepared": FORMAL_ATTEMPT,
            "formalInputsCreated": 0,
            "formalCollectionStarted": False,
            "formalAnalysisStarted": False,
            "mqStarted": False,
            "mtStarted": False,
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "completedAtUtc": utc_now(),
        }
        terminal_path = evidence_root / "terminal-receipt.v2.json"
        write_json(terminal_path, terminal)
        artifacts = []
        for path in sorted(evidence_root.iterdir(), key=lambda p: p.name):
            if path.is_file() and path.name != "final-evidence-freeze-manifest.v2.json":
                artifacts.append(
                    {
                        "relativePath": relative_posix(path, project_root),
                        "bytes": path.stat().st_size,
                        "sha256": sha256_file(path),
                    }
                )
        seal = {
            "schema": "gate14re-me-formal-st-migration-package-final-evidence-freeze-manifest-v2",
            "status": "FROZEN_PASS_RECOVERY_PACKAGE_BUILD_EVIDENCE",
            "packageId": PACKAGE_ID,
            "artifactCount": len(artifacts),
            "artifacts": artifacts,
            "archiveRelativePath": relative_posix(archive_path, project_root),
            "archiveSha256": archive_receipt["sha256"],
            "formalCollectionStarted": False,
            "formalAnalysisStarted": False,
            "mqStarted": False,
            "mtStarted": False,
            "sealedAtUtc": utc_now(),
        }
        write_json(evidence_root / "final-evidence-freeze-manifest.v2.json", seal)
        return terminal
    except Exception as exc:
        failure_path = evidence_root / "failure-receipt.v2.json"
        if not failure_path.exists():
            write_json(
                failure_path,
                {
                    "schema": "gate14re-me-formal-st-migration-package-build-failure-v2",
                    "status": "FAILED_CLOSED_PRESERVE_ATTEMPT_005_ROOTS_NO_SAME_ATTEMPT_RETRY",
                    "failedPhase": phase,
                    "errorType": type(exc).__name__,
                    "error": str(exc),
                    "stagingRoot": STAGING_RELATIVE.as_posix(),
                    "buildRoot": BUILD_RELATIVE.as_posix(),
                    "testRoot": TEST_RELATIVE.as_posix(),
                    "evidenceRoot": EVIDENCE_RELATIVE.as_posix(),
                    "sameAttemptRetryPermitted": False,
                    "sameAttemptResumePermitted": False,
                    "formalCollectionStarted": False,
                    "formalAnalysisStarted": False,
                    "mqStarted": False,
                    "mtStarted": False,
                    "failedAtUtc": utc_now(),
                },
            )
        raise


def resolved(value: str) -> Path:
    return Path(value).resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("command", choices=("preflight", "build-all"))
    args = parser.parse_args()
    project_root = resolved(args.project_root)
    result = preflight(project_root, require_fresh=True) if args.command == "preflight" else build_all(project_root)
    print(canonical_json(result))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(
            canonical_json(
                {
                    "status": "FAIL_CLOSED",
                    "errorType": type(exc).__name__,
                    "error": str(exc),
                }
            ),
            file=sys.stderr,
        )
        raise SystemExit(1)
