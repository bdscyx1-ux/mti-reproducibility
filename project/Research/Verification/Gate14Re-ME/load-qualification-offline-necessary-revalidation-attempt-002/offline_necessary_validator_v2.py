#!/usr/bin/env python3
"""Read-only, streaming necessary revalidation for sealed Gate14Re-ME attempt-009.

This tool deliberately does not create delivery views, run formal analysis,
unseal algorithm identities, or claim the original qualification terminal PASS.
It validates the complete raw byte set and the necessary structural contracts
while resolving and hashing each distinct row-bound source file once and
discarding row objects after their file-local checks.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, Mapping, Sequence, Tuple


RESULT_SCHEMA = "gate14re-me-offline-necessary-raw-validation-result-v1"
PASS_STATUS = "PASS_OFFLINE_NECESSARY_RAW_VALIDATION"
FAIL_STATUS = "FAIL_CLOSED_OFFLINE_NECESSARY_RAW_VALIDATION"
RUNNER_METHOD = "DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV3.Run"
OLD_TOOL_SHA256 = "85b037f50cf913753ea4c77a7642b1d25b7550a833a4d5309ab16b41ad3fca7e"
OUTPUT_SCHEMA_SHA256 = "e9a16e52e041b5818f1d25a343bdf86260d654177aff97bb0c5102637d554a7c"
D3_CONTRACT_SHA256 = "a60531b41c4a3c61e9c0cdc31828d6e34a458f5cf4ae97413538d24c07ecbdce"
IDENTITY_BINDING_SHA256 = "4e52f6f37c4ae496268a173c51ae498eba27a0efaf5303d131e6a102f8aabe08"
SEALED_TERMINAL_SHA256 = "7c7c56f7b75b9fd1f4bbfee439960b6c486e180e940bdc09f99c171c059bd705"
SEALED_MEASURED_MANIFEST_SHA256 = "bb05763473cb5af321bd82f3b00a738cd3d066522527a813fef667b6c50a493f"
SEALED_EVIDENCE_MANIFEST_SHA256 = "0e67dac637a68b3c4ce9159df5576ceca7ac6867c092b2a2b844b44c9fd28522"
ALLOWED_LANES = {"ALG-A", "ALG-B", "ALG-C", "ALG-D", "ALG-E", "ALG-F"}
MEASUREMENT_POINTS = (
    "after-initialization",
    "after-initial-queries",
    *(f"after-event-group-{index}" for index in range(24)),
)
EXPECTED_EVENT_INDEX = {
    "after-initialization": -1,
    "after-initial-queries": -1,
    **{f"after-event-group-{index}": index for index in range(24)},
}
RAW_SCAN_ORDER = (
    "oracle-agent-checks",
    "oracle-event-checks",
    "operations",
    "persistent-state",
    "process-resources",
    "d3-windows",
    "event-groups",
    "empty-boundary",
    "replacement-ledger",
    "failures-and-voids",
)

EXPECTED_LAUNCH_HASHES = {
    "executionAuthorizationSha256": "90f9c46e60b6d1b35ab1569c9507740b7dd4a034b1e1bd68f68a6527746f0746",
    "implementationManifestSha256": "2adeb1f2d85a6c5f0fb9617abe8e8ad4e66745e1706aa3db5d9c91c83749cb95",
    "executionContractSha256": "b66abe8064a65399c64e0cf0d662b92f41676d75a70a89cf7afae0b1b4917c7d",
    "planningAssetsManifestSha256": "7e0cbe77cb8bb8f84642856c6356d318f708e168b52a92e6e348cdf948169aca",
    "resourceBudgetSha256": "bef0f0c143f325eb7b3ad9e5401cc89bc7d6ff3938287a9b049e985aac04e887",
    "fairnessBindingSha256": "ed7d45a47ee5cc1882e0cfe57daf0735be73f0ee84f50f45e4724726d96e5291",
    "scheduleSha256": "328301be5b496a794b67962693183242286d22bc6030db6c746daf7873582471",
    "outputSchemaSha256": OUTPUT_SCHEMA_SHA256,
    "instrumentContractSha256": "c4f37f3457c222111914af95259630bba8b4c90db81aba892719634924166312",
    "d3ContractSha256": D3_CONTRACT_SHA256,
    "typedParquetRuntimeManifestSha256": "254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e",
    "structuralToolSha256": OLD_TOOL_SHA256,
    "deliveryToolSha256": "197b14309670fc38e26b421c458fbd4fc05abe8ba61f7f715497bbcffb19eb98",
    "identityBindingSha256": IDENTITY_BINDING_SHA256,
    "trustedIdentityRuleSha256": "f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06",
    "timestampComparatorSha256": "d024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27",
    "unityExecutableSha256": "0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf",
    "pythonExecutableSha256": "7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1",
}


class OfflineValidationError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Dict[str, Any]:
    if not path.is_file():
        raise OfflineValidationError(f"missing JSON file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise OfflineValidationError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise OfflineValidationError(f"JSON object required: {path}")
    return value


def iter_jsonl(path: Path) -> Iterator[Tuple[int, Dict[str, Any]]]:
    if not path.is_file():
        raise OfflineValidationError(f"missing JSONL file: {path}")
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except Exception as exc:
                raise OfflineValidationError(
                    f"invalid JSONL: {path}:{line_number}: {exc}"
                ) from exc
            if not isinstance(value, dict):
                raise OfflineValidationError(f"JSON object required: {path}:{line_number}")
            yield line_number, value


def write_json_atomic(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False)
        + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


class Progress:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.started = time.perf_counter()
        self.last_write = 0.0

    def emit(self, stage: str, **fields: Any) -> None:
        now = time.perf_counter()
        value = {
            "schema": "gate14re-me-offline-revalidation-progress-v1",
            "status": "RUNNING",
            "stage": stage,
            "updatedAtUtc": utc_now(),
            "elapsedSeconds": round(now - self.started, 3),
            **fields,
        }
        write_json_atomic(self.path, value)
        self.last_write = now

    def maybe(self, stage: str, **fields: Any) -> None:
        if time.perf_counter() - self.last_write >= 10.0:
            self.emit(stage, **fields)


def load_old_validator(path: Path):
    if sha256_file(path) != OLD_TOOL_SHA256:
        raise OfflineValidationError("original structural validator hash mismatch")
    spec = importlib.util.spec_from_file_location("gate14re_original_structural_v31", path)
    if spec is None or spec.loader is None:
        raise OfflineValidationError("cannot import original structural validator")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_manifest(path: Path, expected_sha: str, expected_root_label: str) -> Dict[str, Dict[str, Any]]:
    if sha256_file(path) != expected_sha:
        raise OfflineValidationError(f"sealed manifest hash mismatch: {path}")
    rows: Dict[str, Dict[str, Any]] = {}
    for line_number, row in iter_jsonl(path):
        location = f"{path}:{line_number}"
        if row.get("schema") != "gate14re-me-paused-seal-file-row-v1":
            raise OfflineValidationError(f"sealed manifest row schema mismatch: {location}")
        if row.get("root") != expected_root_label:
            raise OfflineValidationError(f"sealed manifest root label mismatch: {location}")
        relative = row.get("relativePath")
        expected_hash = row.get("sha256")
        byte_count = row.get("bytes")
        if not isinstance(relative, str) or not relative or "\\" in relative:
            raise OfflineValidationError(f"invalid manifest relative path: {location}")
        if relative in rows:
            raise OfflineValidationError(f"duplicate manifest path: {relative}")
        if not isinstance(expected_hash, str) or len(expected_hash) != 64:
            raise OfflineValidationError(f"invalid manifest SHA-256: {location}")
        if not isinstance(byte_count, int) or isinstance(byte_count, bool) or byte_count < 0:
            raise OfflineValidationError(f"invalid manifest byte count: {location}")
        rows[relative] = row
    return rows


def inventory_snapshot(root: Path) -> Dict[str, Tuple[int, int]]:
    return {
        path.relative_to(root).as_posix(): (path.stat().st_size, path.stat().st_mtime_ns)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def verify_sealed_inventory(
    root: Path,
    manifest: Mapping[str, Mapping[str, Any]],
    root_label: str,
    progress: Progress,
    workers: int = 4,
) -> Tuple[Dict[Path, str], Dict[str, Tuple[int, int]]]:
    before = inventory_snapshot(root)
    if set(before) != set(manifest):
        missing = sorted(set(manifest) - set(before))[:10]
        extra = sorted(set(before) - set(manifest))[:10]
        raise OfflineValidationError(
            f"sealed {root_label} file set mismatch; missing={missing}; extra={extra}"
        )
    for relative, (size, _) in before.items():
        if size != manifest[relative]["bytes"]:
            raise OfflineValidationError(f"sealed {root_label} byte count mismatch: {relative}")

    items = list(manifest.items())
    actual_hashes: Dict[Path, str] = {}

    def hash_one(item: Tuple[str, Mapping[str, Any]]) -> Tuple[str, str]:
        relative, _ = item
        return relative, sha256_file(root / Path(relative))

    completed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        for relative, actual in executor.map(hash_one, items, chunksize=1):
            expected = str(manifest[relative]["sha256"])
            if actual != expected:
                raise OfflineValidationError(
                    f"sealed {root_label} SHA-256 mismatch: {relative}; expected={expected}; actual={actual}"
                )
            actual_hashes[(root / Path(relative)).resolve()] = actual
            completed += 1
            progress.maybe(
                "VERIFY_SEALED_BYTES",
                root=root_label,
                completedFiles=completed,
                totalFiles=len(items),
            )

    after = inventory_snapshot(root)
    if before != after:
        raise OfflineValidationError(f"sealed {root_label} changed during inventory verification")
    return actual_hashes, before


class CachedSourceHashes:
    def __init__(self, preverified: Mapping[Path, str]) -> None:
        self.cache = {path.resolve(): value for path, value in preverified.items()}
        self.computed = 0
        self.cache_hits = 0
        self.references = 0

    def get(self, path: Path) -> str:
        resolved = path.resolve()
        self.references += 1
        if resolved in self.cache:
            self.cache_hits += 1
            return self.cache[resolved]
        value = sha256_file(resolved)
        self.cache[resolved] = value
        self.computed += 1
        return value


class CachedSourceBindings:
    """Validate each distinct row-bound path once, then use string cache hits.

    The v1 offline implementation cached file content hashes but still called
    Path.resolve()/relative_to() several times for every raw row.  With more
    than 6.8 million rows in the two dominant tables, filesystem path
    canonicalization—not hashing or JSON parsing—became the new bottleneck.
    This cache preserves the same fail-closed binding check while making all
    subsequent references to an already-seen relative path O(1) string/dict
    comparisons with no filesystem calls.
    """

    def __init__(self, project_root: Path, hashes: CachedSourceHashes) -> None:
        self.project_root = project_root.resolve()
        self.hashes = hashes
        self.cache: Dict[str, str] = {}
        self.distinct_paths = 0
        self.cache_hits = 0
        self.references = 0

    def validate(self, row: Mapping[str, Any], location: str) -> None:
        relative = row.get("sourceRelativePath")
        expected = row.get("sourceSha256")
        if not isinstance(relative, str) or not relative:
            raise OfflineValidationError(f"sourceRelativePath string required: {location}")
        if (
            not isinstance(expected, str)
            or len(expected) != 64
            or any(character not in "0123456789abcdef" for character in expected)
        ):
            raise OfflineValidationError(f"lowercase sourceSha256 required: {location}")

        self.references += 1
        cached_expected = self.cache.get(relative)
        if cached_expected is not None:
            if cached_expected != expected:
                raise OfflineValidationError(
                    f"inconsistent SHA-256 for cached source path: {location}; "
                    f"first={cached_expected}; current={expected}"
                )
            self.cache_hits += 1
            return

        relative_path = Path(relative)
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise OfflineValidationError(f"noncanonical sourceRelativePath: {location}")
        source = (self.project_root / relative_path).resolve()
        if not within(source, self.project_root) or not source.is_file():
            raise OfflineValidationError(f"row-bound source missing/outside project: {location}")
        if source.relative_to(self.project_root).as_posix() != relative.replace("\\", "/"):
            raise OfflineValidationError(f"noncanonical sourceRelativePath: {location}")
        actual = self.hashes.get(source)
        if actual != expected:
            raise OfflineValidationError(
                f"row-bound source SHA-256 mismatch: {location}; expected={expected}; actual={actual}"
            )
        self.cache[relative] = expected
        self.distinct_paths += 1


def within(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def require_partitioned_record_id(
    row: Mapping[str, Any],
    expected_prefix: str,
    seen: set[str],
    location: str,
    old: Any,
) -> str:
    record_id = old.require_string(row.get("recordId"), f"{location}:recordId")
    if not record_id.startswith(expected_prefix):
        raise OfflineValidationError(
            f"recordId does not prove disjoint file partition: {location}; prefix={expected_prefix}"
        )
    if record_id in seen:
        raise OfflineValidationError(f"duplicate recordId within partition: {location}: {record_id}")
    seen.add(record_id)
    return record_id


def validate_static_bindings(project_root: Path, evidence_root: Path, hashes: CachedSourceHashes) -> None:
    bindings = {
        evidence_root / "execution-authorization.v1.json": EXPECTED_LAUNCH_HASHES["executionAuthorizationSha256"],
        project_root / "Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_9.json": EXPECTED_LAUNCH_HASHES["implementationManifestSha256"],
        project_root / "Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_9.json": EXPECTED_LAUNCH_HASHES["executionContractSha256"],
        project_root / "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets-freeze-manifest.v1.json": EXPECTED_LAUNCH_HASHES["planningAssetsManifestSha256"],
        project_root / "Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json": EXPECTED_LAUNCH_HASHES["resourceBudgetSha256"],
        project_root / "Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1_2.json": EXPECTED_LAUNCH_HASHES["fairnessBindingSha256"],
        project_root / "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl": EXPECTED_LAUNCH_HASHES["scheduleSha256"],
        project_root / "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v3.json": OUTPUT_SCHEMA_SHA256,
        project_root / "Research/Gate14Re-ME/Execution/v3/load-qualification-instrument-contract.v3.json": EXPECTED_LAUNCH_HASHES["instrumentContractSha256"],
        project_root / "Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json": D3_CONTRACT_SHA256,
        project_root / "Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json": EXPECTED_LAUNCH_HASHES["typedParquetRuntimeManifestSha256"],
        project_root / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v3_1.py": OLD_TOOL_SHA256,
        project_root / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2_2.py": EXPECTED_LAUNCH_HASHES["deliveryToolSha256"],
        project_root / "Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json": EXPECTED_LAUNCH_HASHES["trustedIdentityRuleSha256"],
        project_root / "Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1": EXPECTED_LAUNCH_HASHES["timestampComparatorSha256"],
        project_root / "Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV3.cs": "bb5d454be82083008093c56caccbe17262d3c7bc921fe4e9205e42557270b827",
        Path("H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe"): EXPECTED_LAUNCH_HASHES["unityExecutableSha256"],
        Path("C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"): EXPECTED_LAUNCH_HASHES["pythonExecutableSha256"],
        Path("C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe"): "362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139",
    }
    for path, expected in bindings.items():
        if not path.is_file():
            raise OfflineValidationError(f"frozen binding file missing: {path}")
        actual = hashes.get(path)
        if actual != expected:
            raise OfflineValidationError(
                f"frozen binding SHA-256 mismatch: {path}; expected={expected}; actual={actual}"
            )


def validate_control_and_receipts(
    project_root: Path,
    raw_root: Path,
    evidence_root: Path,
    old: Any,
    hashes: CachedSourceHashes,
) -> Dict[str, Any]:
    launch_path = raw_root / "_control/launch-receipt.v2.json"
    launch = read_json(launch_path)
    if launch.get("schema") != "gate14re-me-qualification-launch-receipt-v2":
        raise OfflineValidationError("launch receipt schema mismatch")
    if launch.get("status") != "AUTHORIZED_QUALIFICATION_ACQUISITION_STARTED":
        raise OfflineValidationError("launch receipt status mismatch")
    if launch.get("runnerMethod") != RUNNER_METHOD:
        raise OfflineValidationError("launch receipt RunnerV3 method mismatch")
    if launch.get("replacementPolicy") != "ZERO_REPLACEMENT_FAIL_STOP":
        raise OfflineValidationError("launch receipt replacement policy mismatch")
    for field, expected in EXPECTED_LAUNCH_HASHES.items():
        if launch.get(field) != expected:
            raise OfflineValidationError(f"launch receipt frozen binding mismatch: {field}")

    acquisition = read_json(raw_root / "_control/acquisition-complete.v2.json")
    if (
        acquisition.get("schema") != "gate14re-me-qualification-acquisition-complete-v2"
        or acquisition.get("status") != "QUALIFICATION_RAW_STRUCTURAL_VALIDATION_PENDING"
    ):
        raise OfflineValidationError("acquisition-complete identity/status mismatch")
    expected_acquisition = {
        "plannedSuperblocks": 162,
        "acceptedSuperblocks": 162,
        "plannedAlgorithmLanes": 972,
        "acceptedAlgorithmLanes": 972,
        "unityProcessCount": 1147,
        "wholeSuperblockReplacements": 0,
    }
    for field, expected in expected_acquisition.items():
        if acquisition.get(field) != expected:
            raise OfflineValidationError(f"acquisition-complete count mismatch: {field}")
    for field in ("formalCollectionAuthorized", "formalAnalysisAuthorized", "rankingOrWinnerComputed"):
        if acquisition.get(field) is not False:
            raise OfflineValidationError(f"acquisition authorization boundary mismatch: {field}")

    for name in ("failures-and-voids.raw.v1.jsonl", "replacement-ledger.raw.v1.jsonl"):
        if any(True for _ in iter_jsonl(raw_root / "_control" / name)):
            raise OfflineValidationError(f"control ledger must be empty: {name}")

    accepted_paths = sorted(raw_root.rglob("accepted-superblock-receipt.v1.json"))
    oracle_paths = sorted(raw_root.rglob("oracle-pass-receipt.v1.json"))
    lane_paths = sorted(raw_root.rglob("lane-receipt.v2.json"))
    empty_paths = sorted(raw_root.rglob("empty-boundary-receipt.v2.json"))
    if (len(accepted_paths), len(oracle_paths), len(lane_paths), len(empty_paths)) != (162, 162, 972, 12):
        raise OfflineValidationError("receipt cardinality mismatch")

    accepted_ids: set[str] = set()
    for path in accepted_paths:
        receipt = read_json(path)
        if (
            receipt.get("schema") != "gate14re-me-accepted-superblock-receipt-v1"
            or receipt.get("status") != "ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK"
        ):
            raise OfflineValidationError(f"accepted-superblock receipt invalid: {path}")
        superblock = old.require_string(receipt.get("plannedSuperblockId"), f"{path}:plannedSuperblockId")
        if superblock in accepted_ids or path.parent.name != superblock:
            raise OfflineValidationError(f"accepted-superblock identity/path mismatch: {path}")
        accepted_ids.add(superblock)
        if (
            receipt.get("instanceId") != superblock
            or receipt.get("isReplacement") is not False
            or receipt.get("acceptedAnonymousLanes") != 6
            or len(list(path.parent.glob("ALG-*/lane-receipt.v2.json"))) != 6
        ):
            raise OfflineValidationError(f"accepted-superblock closure mismatch: {path}")

    oracle_by_parent: Dict[Path, Dict[str, Any]] = {}
    oracle_ids: set[str] = set()
    for path in oracle_paths:
        receipt = read_json(path)
        if (
            receipt.get("schema") != "gate14re-me-oracle-pass-receipt-v1"
            or receipt.get("status") != "PASS_ALGORITHM_NEUTRAL_GEOMETRY"
            or receipt.get("allGeometryChecksPassed") is not True
        ):
            raise OfflineValidationError(f"oracle receipt invalid: {path}")
        superblock = old.require_string(receipt.get("superblockId"), f"{path}:superblockId")
        if superblock in oracle_ids or path.parent.name != superblock:
            raise OfflineValidationError(f"oracle receipt identity/path mismatch: {path}")
        oracle_ids.add(superblock)
        oracle_by_parent[path.parent.resolve()] = receipt
    if oracle_ids != accepted_ids:
        raise OfflineValidationError("oracle and accepted-superblock sets differ")

    lane_by_parent: Dict[Path, Dict[str, Any]] = {}
    lane_keys: set[Tuple[str, str, str]] = set()
    for path in lane_paths:
        receipt = read_json(path)
        parent = path.parent.resolve()
        if (
            receipt.get("schema") != "gate14re-me-qualification-lane-receipt-v2"
            or receipt.get("status") != "COMPLETE_RAW_LANE"
            or receipt.get("completed") is not True
            or receipt.get("instrumentValid") is not True
        ):
            raise OfflineValidationError(f"lane receipt incomplete/invalid: {path}")
        lane = receipt.get("anonymousLaneId")
        if lane not in ALLOWED_LANES or parent.name != lane:
            raise OfflineValidationError(f"lane receipt anonymous identity mismatch: {path}")
        if receipt.get("identityBindingSha256") != IDENTITY_BINDING_SHA256:
            raise OfflineValidationError(f"lane receipt identity binding mismatch: {path}")
        if receipt.get("d3ContractSha256") != D3_CONTRACT_SHA256:
            raise OfflineValidationError(f"lane receipt D3 contract mismatch: {path}")
        key = (
            old.require_string(receipt.get("inputId"), f"{path}:inputId"),
            old.require_string(receipt.get("superblockId"), f"{path}:superblockId"),
            str(lane),
        )
        if key in lane_keys or parent in lane_by_parent:
            raise OfflineValidationError(f"duplicate lane receipt partition: {path}")
        lane_keys.add(key)
        lane_by_parent[parent] = receipt

    empty_by_parent: Dict[Path, Dict[str, Any]] = {}
    empty_ordinals: set[int] = set()
    for path in empty_paths:
        receipt = read_json(path)
        parent = path.parent.resolve()
        if (
            receipt.get("schema") != "gate14re-me-empty-boundary-receipt-v2"
            or receipt.get("status") != "COMPLETE_EMPTY_BOUNDARY_RAW"
        ):
            raise OfflineValidationError(f"empty-boundary receipt invalid: {path}")
        ordinal = old.require_int(receipt.get("processOrdinal"), f"{path}:processOrdinal", minimum=0)
        if ordinal in empty_ordinals or ordinal not in range(12):
            raise OfflineValidationError(f"empty-boundary ordinal duplicate/out of range: {path}")
        empty_ordinals.add(ordinal)
        if (
            receipt.get("rawIterationRows") != 1000
            or receipt.get("d3WindowRows") != 1000
            or receipt.get("plannerInvoked") is not False
            or receipt.get("d3ContractSha256") != D3_CONTRACT_SHA256
        ):
            raise OfflineValidationError(f"empty-boundary receipt closure mismatch: {path}")
        empty_by_parent[parent] = receipt

    instrument = read_json(raw_root / "instruments/csharp/instrument-csharp-receipt.v2.json")
    if (
        instrument.get("schema") != "gate14re-me-instrument-qualification-receipt-v2"
        or instrument.get("status") != "PASS_CSHARP_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING"
    ):
        raise OfflineValidationError("instrument receipt identity/status mismatch")
    for field in (
        "gridReadProxyKnownAnswerPassed",
        "gridReadProxySemanticInvariancePassed",
        "d3V31PluginReadinessPassed",
        "d3V31OneMiBPositiveControlPassed",
        "d3V31RateFormulaPassed",
        "persistentStateSizerSyntheticFixturePassed",
        "clockMonotonicityPassed",
    ):
        if instrument.get(field) is not True:
            raise OfflineValidationError(f"instrument receipt gate failed: {field}")

    ledger_path = raw_root / "_control/process-ledger.raw.v2.jsonl"
    ledger_rows = [row for _, row in iter_jsonl(ledger_path)]
    if len(ledger_rows) != 1147:
        raise OfflineValidationError("process ledger cardinality mismatch")
    expected_modes = ["instrument-self-test"] + ["oracle"] * 162 + ["empty-boundary"] * 12 + ["lane"] * 972
    identity_paths = sorted(raw_root.rglob("process-*.identity.v2.json"))
    if len(identity_paths) != 1147:
        raise OfflineValidationError("process identity receipt cardinality mismatch")
    identity_set = {path.resolve() for path in identity_paths}
    linked: set[Path] = set()
    process_composites: set[Tuple[int, str]] = set()
    for ordinal, (row, expected_mode) in enumerate(zip(ledger_rows, expected_modes)):
        location = f"{ledger_path}:{ordinal + 1}"
        if (
            row.get("schema") != "gate14re-me-process-ledger-row-v2"
            or row.get("ordinal") != ordinal
            or row.get("mode") != expected_mode
            or row.get("state") != "EXITED_ZERO_TRUSTED_IDENTITY"
            or row.get("exitCode") != 0
        ):
            raise OfflineValidationError(f"process ledger sequence/state mismatch: {location}")
        pid = old.require_int(row.get("processId"), f"{location}:processId", minimum=1)
        created = old.require_string(row.get("creationTimeUtc"), f"{location}:creationTimeUtc")
        old.require_string(row.get("exitedAtUtc"), f"{location}:exitedAtUtc")
        composite = (pid, created)
        if composite in process_composites:
            raise OfflineValidationError(f"duplicate process composite: {location}")
        process_composites.add(composite)
        relative = old.require_string(row.get("identityReceiptRelativePath"), f"{location}:identityReceiptRelativePath")
        expected_hash = old.require_string(row.get("identityReceiptSha256"), f"{location}:identityReceiptSha256")
        identity_path = (project_root / relative).resolve()
        if not within(identity_path, raw_root) or identity_path not in identity_set or identity_path in linked:
            raise OfflineValidationError(f"process identity closure mismatch: {location}")
        linked.add(identity_path)
        if hashes.get(identity_path) != expected_hash:
            raise OfflineValidationError(f"process identity receipt hash mismatch: {location}")
        identity = read_json(identity_path)
        if (
            identity.get("schema") != "gate14re-me-qualified-unity-process-identity-receipt-v2"
            or identity.get("status") != "PASS_TRUSTED_THREE_PHASE_COMPOSITE_IDENTITY_NATURAL_EXIT"
            or identity.get("ordinal") != ordinal
            or identity.get("mode") != expected_mode
            or identity.get("processId") != pid
            or identity.get("creationTimeUtc") != created
            or identity.get("exitCode") != 0
            or identity.get("executeMethod") != RUNNER_METHOD
            or identity.get("naturalExit") is not True
            or identity.get("signalOrForcedTerminationSent") is not False
            or identity.get("retryPerformed") is not False
            or identity.get("trustedIdentityRuleSha256") != EXPECTED_LAUNCH_HASHES["trustedIdentityRuleSha256"]
            or identity.get("timestampComparatorSha256") != EXPECTED_LAUNCH_HASHES["timestampComparatorSha256"]
        ):
            raise OfflineValidationError(f"process identity composite/policy mismatch: {identity_path}")
        for field in ("prelaunchFingerprint", "liveConcurrentFingerprint", "postExitFingerprint"):
            if not isinstance(identity.get(field), dict):
                raise OfflineValidationError(f"process identity phase missing: {identity_path}:{field}")
    if linked != identity_set:
        raise OfflineValidationError("process identity set not exactly closed by ledger")

    external = read_json(evidence_root / "external-terminal-observation.v1.json")
    if external.get("processId") != 89976 or external.get("exitCode") != -1:
        raise OfflineValidationError("external terminal observation mismatch after user stop")

    return {
        "launch": launch,
        "acquisition": acquisition,
        "laneByParent": lane_by_parent,
        "oracleByParent": oracle_by_parent,
        "emptyByParent": empty_by_parent,
        "acceptedSuperblockCount": len(accepted_paths),
        "oracleReceiptCount": len(oracle_paths),
        "laneReceiptCount": len(lane_paths),
        "emptyBoundaryReceiptCount": len(empty_paths),
        "processLedgerRows": len(ledger_rows),
        "processIdentityReceipts": len(identity_paths),
    }


def discover_table_files(raw_root: Path, file_name: str) -> list[Path]:
    return sorted(
        (path for path in raw_root.rglob(file_name) if path.is_file()),
        key=lambda path: path.relative_to(raw_root).as_posix(),
    )


def scan_raw_tables(
    project_root: Path,
    raw_root: Path,
    schema_path: Path,
    old: Any,
    hashes: CachedSourceHashes,
    source_bindings: CachedSourceBindings,
    control: Mapping[str, Any],
    progress: Progress,
) -> Dict[str, Any]:
    specs = old.load_specs(schema_path, OUTPUT_SCHEMA_SHA256)
    lane_by_parent: Mapping[Path, Mapping[str, Any]] = control["laneByParent"]
    oracle_by_parent: Mapping[Path, Mapping[str, Any]] = control["oracleByParent"]
    empty_by_parent: Mapping[Path, Mapping[str, Any]] = control["emptyByParent"]
    table_counts: Dict[str, int] = {}
    table_file_counts: Dict[str, int] = {}
    d3_index: Dict[str, Tuple[str, str, str, str, int, int, int, str]] = {}
    d3_referenced: set[str] = set()
    event_join_count = 0
    empty_join_count = 0
    persistent_point_pairs = 0
    total_files_scanned = 0

    for table_id in RAW_SCAN_ORDER:
        spec = specs[table_id]
        file_name = old.require_string(spec.get("fileName"), f"schema:{table_id}:fileName")
        required_fields = tuple(spec.get("requiredFields", ()))
        files = discover_table_files(raw_root, file_name)
        if not files:
            raise OfflineValidationError(f"no files found for raw table: {table_id}")
        table_file_counts[table_id] = len(files)
        table_total = 0

        for file_index, path in enumerate(files, 1):
            parent = path.parent.resolve()
            seen: set[str] = set()
            file_rows = 0
            event_indices: set[int] = set()
            d3_event_indices: set[int] = set()
            d3_scopes: Counter[str] = Counter()
            resource_points: set[str] = set()
            persistent_points: set[str] = set()
            persistent_names: Dict[str, set[str]] = defaultdict(set)
            persistent_sums: Dict[str, int] = defaultdict(int)
            persistent_totals: Dict[str, set[int]] = defaultdict(set)
            empty_iterations: set[int] = set()
            lane_receipt = lane_by_parent.get(parent)
            oracle_receipt = oracle_by_parent.get(parent)
            empty_receipt = empty_by_parent.get(parent)

            for line_number, row in iter_jsonl(path):
                location = f"{path}:{line_number}"
                try:
                    old.require_fields(row, required_fields, location)
                    old.validate_flat_scalars(row, location)
                except Exception as exc:
                    raise OfflineValidationError(str(exc)) from exc

                lane = row.get("anonymousLaneId")
                if lane not in (None, ""):
                    if lane not in ALLOWED_LANES or row.get("identityBindingSha256") != IDENTITY_BINDING_SHA256:
                        raise OfflineValidationError(f"anonymous lane/binding mismatch: {location}")
                if bool(spec.get("sourcePathAndShaRequired")):
                    source_bindings.validate(row, location)

                if table_id in {"operations", "event-groups", "persistent-state", "process-resources"}:
                    if lane_receipt is None:
                        raise OfflineValidationError(f"lane table outside lane receipt partition: {path}")
                    expected_key = (
                        lane_receipt["inputId"],
                        lane_receipt["superblockId"],
                        lane_receipt["anonymousLaneId"],
                    )
                    if (row.get("inputId"), row.get("superblockId"), row.get("anonymousLaneId")) != expected_key:
                        raise OfflineValidationError(f"lane row identity mismatch: {location}")
                    prefix = f"{expected_key[0]}:{expected_key[2]}:"
                elif table_id in {"oracle-agent-checks", "oracle-event-checks"}:
                    if oracle_receipt is None:
                        raise OfflineValidationError(f"oracle table outside oracle receipt partition: {path}")
                    if (row.get("inputId"), row.get("superblockId")) != (
                        oracle_receipt["inputId"],
                        oracle_receipt["superblockId"],
                    ):
                        raise OfflineValidationError(f"oracle row identity mismatch: {location}")
                    prefix = f"{oracle_receipt['inputId']}:"
                elif table_id == "empty-boundary":
                    if empty_receipt is None or row.get("processOrdinal") != empty_receipt["processOrdinal"]:
                        raise OfflineValidationError(f"empty-boundary partition mismatch: {location}")
                    prefix = f"empty:{empty_receipt['processOrdinal']}:"
                elif table_id == "d3-windows":
                    prefix = ""
                else:
                    prefix = ""

                if table_id == "d3-windows":
                    try:
                        envelope = old.RowEnvelope(table_id, path, line_number, row)
                        old.validate_d3_row(envelope)
                    except Exception as exc:
                        raise OfflineValidationError(str(exc)) from exc
                    record_id = old.require_string(row.get("recordId"), f"{location}:recordId")
                    if record_id in d3_index:
                        raise OfflineValidationError(f"duplicate global D3 recordId: {location}")
                    d3_index[record_id] = (
                        str(row.get("measurementScope")),
                        str(row.get("inputId")),
                        str(row.get("superblockId")),
                        str(row.get("anonymousLaneId")),
                        int(row.get("eventGroupIndex")),
                        int(row.get("processOrdinal")),
                        int(row.get("iterationIndex")),
                        str(parent),
                    )
                    d3_scopes[str(row.get("measurementScope"))] += 1
                    if row.get("measurementScope") == "event-group":
                        d3_event_indices.add(int(row["eventGroupIndex"]))
                    if lane_receipt is not None:
                        if (row.get("inputId"), row.get("superblockId"), row.get("anonymousLaneId")) != (
                            lane_receipt["inputId"], lane_receipt["superblockId"], lane_receipt["anonymousLaneId"]
                        ):
                            raise OfflineValidationError(f"lane D3 identity mismatch: {location}")
                    elif empty_receipt is not None and row.get("processOrdinal") != empty_receipt["processOrdinal"]:
                        raise OfflineValidationError(f"empty D3 ordinal mismatch: {location}")
                else:
                    require_partitioned_record_id(row, prefix, seen, location, old)

                if table_id == "operations":
                    try:
                        old.require_int(row.get("managedAllocatedBytes"), f"{location}:managedAllocatedBytes", minimum=0)
                        old.require_string(row.get("nativeMetricsSemanticsId"), f"{location}:nativeMetricsSemanticsId")
                    except Exception as exc:
                        raise OfflineValidationError(str(exc)) from exc
                elif table_id == "event-groups":
                    try:
                        envelope = old.RowEnvelope(table_id, path, line_number, row)
                        old.validate_event_row(envelope)
                    except Exception as exc:
                        raise OfflineValidationError(str(exc)) from exc
                    event_index = int(row["eventGroupIndex"])
                    if event_index in event_indices:
                        raise OfflineValidationError(f"duplicate event-group index in lane: {location}")
                    event_indices.add(event_index)
                    target_id = str(row["d3WindowRecordId"])
                    target = d3_index.get(target_id)
                    expected_join = (
                        "event-group",
                        str(row["inputId"]),
                        str(row["superblockId"]),
                        str(row["anonymousLaneId"]),
                        event_index,
                    )
                    if target is None or target[:5] != expected_join or target_id in d3_referenced:
                        raise OfflineValidationError(f"event-group D3 join mismatch/duplicate: {location}")
                    d3_referenced.add(target_id)
                    event_join_count += 1
                elif table_id == "empty-boundary":
                    try:
                        envelope = old.RowEnvelope(table_id, path, line_number, row)
                        old.validate_empty_row(envelope)
                    except Exception as exc:
                        raise OfflineValidationError(str(exc)) from exc
                    iteration = int(row["iterationIndex"])
                    if iteration in empty_iterations:
                        raise OfflineValidationError(f"duplicate empty iteration: {location}")
                    empty_iterations.add(iteration)
                    target_id = str(row["d3WindowRecordId"])
                    target = d3_index.get(target_id)
                    if (
                        target is None
                        or target[0] != "empty-boundary"
                        or target[5] != int(row["processOrdinal"])
                        or target[6] != iteration
                        or target_id in d3_referenced
                    ):
                        raise OfflineValidationError(f"empty-boundary D3 join mismatch/duplicate: {location}")
                    d3_referenced.add(target_id)
                    empty_join_count += 1
                elif table_id == "process-resources":
                    point = str(row.get("measurementPointId"))
                    if point in resource_points or point not in MEASUREMENT_POINTS:
                        raise OfflineValidationError(f"process-resource point duplicate/invalid: {location}")
                    resource_points.add(point)
                    if row.get("eventGroupIndex") != EXPECTED_EVENT_INDEX[point]:
                        raise OfflineValidationError(f"process-resource point/index mismatch: {location}")
                    try:
                        old.require_int(row.get("processId"), f"{location}:processId", minimum=1)
                        for field in ("privateMemoryBytes", "workingSetBytes", "managedMemoryBytes", "peakWorkingSetBytes"):
                            old.require_int(row.get(field), f"{location}:{field}", minimum=0)
                        old.require_string(row.get("capturedAtUtc"), f"{location}:capturedAtUtc")
                    except Exception as exc:
                        raise OfflineValidationError(str(exc)) from exc
                elif table_id == "persistent-state":
                    point = str(row.get("measurementPointId"))
                    if point not in MEASUREMENT_POINTS or row.get("eventGroupIndex") != EXPECTED_EVENT_INDEX[point]:
                        raise OfflineValidationError(f"persistent-state point/index mismatch: {location}")
                    if (
                        row.get("sizingFormulaId") != "gate14re-me-persistent-state-logical-capacity-v1"
                        or row.get("valid") is not True
                        or row.get("invalidReasonCode") != ""
                    ):
                        raise OfflineValidationError(f"persistent-state validity mismatch: {location}")
                    try:
                        name = old.require_string(row.get("persistentContainerName"), f"{location}:persistentContainerName")
                        old.require_string(row.get("containerKind"), f"{location}:containerKind")
                        for field in (
                            "persistentContainerCapacity", "persistentContainerBytesPerElement",
                            "persistentContainerCapacityBytes", "persistentPrimitiveArrayBytes", "persistentStateBytesTotal"
                        ):
                            old.require_int(row.get(field), f"{location}:{field}", minimum=0)
                    except Exception as exc:
                        raise OfflineValidationError(str(exc)) from exc
                    if name in persistent_names[point]:
                        raise OfflineValidationError(f"duplicate persistent component: {location}")
                    persistent_names[point].add(name)
                    persistent_sums[point] += int(row["persistentContainerCapacityBytes"])
                    persistent_totals[point].add(int(row["persistentStateBytesTotal"]))
                    persistent_points.add(point)

                file_rows += 1
                table_total += 1
                progress.maybe(
                    "SCAN_RAW_ROWS",
                    table=table_id,
                    currentFile=file_index,
                    totalFiles=len(files),
                    currentTableRows=table_total,
                )

            if table_id == "operations":
                if lane_receipt is None or file_rows != int(lane_receipt["operationRows"]):
                    raise OfflineValidationError(f"operation row count does not match lane receipt: {path}")
            elif table_id == "event-groups":
                if file_rows != 24 or event_indices != set(range(24)) or lane_receipt.get("eventGroupRows") != 24:
                    raise OfflineValidationError(f"event-group coverage mismatch: {path}")
            elif table_id == "persistent-state":
                if lane_receipt is None or file_rows != int(lane_receipt["persistentStateRows"]):
                    raise OfflineValidationError(f"persistent-state count mismatch: {path}")
                if persistent_points != set(MEASUREMENT_POINTS):
                    raise OfflineValidationError(f"persistent-state point coverage mismatch: {path}")
                for point in MEASUREMENT_POINTS:
                    if persistent_totals[point] != {persistent_sums[point]}:
                        raise OfflineValidationError(f"persistent-state point total mismatch: {path}:{point}")
                persistent_point_pairs += len(persistent_points)
            elif table_id == "process-resources":
                if file_rows != 26 or resource_points != set(MEASUREMENT_POINTS) or lane_receipt.get("processResourceRows") != 26:
                    raise OfflineValidationError(f"process-resource coverage mismatch: {path}")
            elif table_id == "oracle-agent-checks":
                if oracle_receipt is None or file_rows != int(oracle_receipt["agentRowCount"]):
                    raise OfflineValidationError(f"oracle-agent count mismatch: {path}")
            elif table_id == "oracle-event-checks":
                if oracle_receipt is None or file_rows != int(oracle_receipt["eventGroupRowCount"]):
                    raise OfflineValidationError(f"oracle-event count mismatch: {path}")
            elif table_id == "empty-boundary":
                if file_rows != 1000 or empty_iterations != set(range(1000)):
                    raise OfflineValidationError(f"empty-boundary coverage mismatch: {path}")
            elif table_id == "d3-windows":
                if lane_receipt is not None:
                    if file_rows != 25 or d3_scopes != Counter({"planner-initialization": 1, "event-group": 24}) or d3_event_indices != set(range(24)):
                        raise OfflineValidationError(f"lane D3 scope/cardinality mismatch: {path}")
                elif empty_receipt is not None:
                    if file_rows != 1000 or d3_scopes != Counter({"empty-boundary": 1000}):
                        raise OfflineValidationError(f"empty D3 scope/cardinality mismatch: {path}")
                else:
                    if file_rows != 1 or d3_scopes != Counter({"instrument-self-test-positive-control": 1}):
                        raise OfflineValidationError(f"instrument D3 scope/cardinality mismatch: {path}")
            elif table_id in {"replacement-ledger", "failures-and-voids"} and file_rows != 0:
                raise OfflineValidationError(f"control ledger not empty: {path}")

            total_files_scanned += 1

        table_counts[table_id] = table_total
        progress.emit(
            "SCAN_RAW_ROWS",
            table=table_id,
            completedTable=True,
            tableFiles=len(files),
            tableRows=table_total,
        )

    expected_dynamic = {
        "operations": sum(int(receipt["operationRows"]) for receipt in lane_by_parent.values()),
        "persistent-state": sum(int(receipt["persistentStateRows"]) for receipt in lane_by_parent.values()),
        "oracle-agent-checks": sum(int(receipt["agentRowCount"]) for receipt in oracle_by_parent.values()),
        "oracle-event-checks": sum(int(receipt["eventGroupRowCount"]) for receipt in oracle_by_parent.values()),
        "event-groups": 23328,
        "d3-windows": 36301,
        "process-resources": 25272,
        "empty-boundary": 12000,
        "replacement-ledger": 0,
        "failures-and-voids": 0,
    }
    for table_id, expected in expected_dynamic.items():
        if table_counts.get(table_id) != expected:
            raise OfflineValidationError(
                f"terminal raw row cardinality mismatch: {table_id}; expected={expected}; actual={table_counts.get(table_id)}"
            )
    if event_join_count != 23328 or empty_join_count != 12000:
        raise OfflineValidationError("D3 join cardinality mismatch")
    required_join_ids = {
        record_id for record_id, row in d3_index.items() if row[0] in {"event-group", "empty-boundary"}
    }
    if required_join_ids != d3_referenced:
        raise OfflineValidationError("D3 join-required set not exactly referenced")
    if persistent_point_pairs != 25272:
        raise OfflineValidationError("persistent-state measurement-point/lane pair count mismatch")

    return {
        "tableRows": table_counts,
        "tableFiles": table_file_counts,
        "rawFilesScanned": total_files_scanned,
        "eventGroupD3Joins": event_join_count,
        "emptyBoundaryD3Joins": empty_join_count,
        "persistentStateMeasurementPointLanePairs": persistent_point_pairs,
        "d3WindowRecordIdsUnique": True,
        "d3JoinsOneToOneAndComplete": True,
    }


def verify_freeze_manifest(path: Path) -> None:
    manifest = read_json(path)
    if manifest.get("schema") != "gate14re-me-offline-revalidation-pre-execution-freeze-manifest-v1":
        raise OfflineValidationError("pre-execution freeze manifest schema mismatch")
    if manifest.get("status") != "FROZEN_BEFORE_EXECUTION":
        raise OfflineValidationError("pre-execution freeze manifest status mismatch")
    for item in manifest.get("files", []):
        artifact = (path.parent / str(item.get("relativePath"))).resolve()
        expected = item.get("sha256")
        if not artifact.is_file() or sha256_file(artifact) != expected:
            raise OfflineValidationError(f"pre-execution artifact hash mismatch: {artifact}")


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--raw-root", required=True)
    parser.add_argument("--execution-evidence-root", required=True)
    parser.add_argument("--seal-root", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--freeze-manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--progress", required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    project_root = Path(args.project_root).resolve()
    raw_root = Path(args.raw_root).resolve()
    evidence_root = Path(args.execution_evidence_root).resolve()
    seal_root = Path(args.seal_root).resolve()
    output_root = Path(args.output_root).resolve()
    output_path = Path(args.output).resolve()
    progress = Progress(Path(args.progress).resolve())
    started_utc = utc_now()
    started = time.perf_counter()
    phase_timings: Dict[str, float] = {}

    try:
        if not within(raw_root, project_root) or not within(evidence_root, project_root):
            raise OfflineValidationError("source root outside project")
        if within(output_root, raw_root) or within(output_root, evidence_root):
            raise OfflineValidationError("output root must be separate from sealed source roots")
        verify_freeze_manifest(Path(args.freeze_manifest).resolve())

        terminal_receipt = seal_root / "terminal-seal-receipt.v1.json"
        if sha256_file(terminal_receipt) != SEALED_TERMINAL_SHA256:
            raise OfflineValidationError("paused seal terminal receipt hash mismatch")
        terminal = read_json(terminal_receipt)
        if (
            terminal.get("status") != "PASS_PAUSED_SEAL_CREATED_QUALIFICATION_NOT_PASS"
            or terminal.get("qualificationPass") is not False
            or terminal.get("rawDataPreserved") is not True
        ):
            raise OfflineValidationError("paused seal terminal status mismatch")

        progress.emit("VERIFY_SEALED_BYTES", root="measured", completedFiles=0, totalFiles=9789)
        phase_start = time.perf_counter()
        measured_manifest = load_manifest(
            seal_root / "measured-file-manifest.v1.jsonl",
            SEALED_MEASURED_MANIFEST_SHA256,
            "measured",
        )
        measured_hashes, measured_snapshot = verify_sealed_inventory(
            raw_root, measured_manifest, "measured", progress
        )
        evidence_manifest = load_manifest(
            seal_root / "execution-evidence-file-manifest.v1.jsonl",
            SEALED_EVIDENCE_MANIFEST_SHA256,
            "execution-evidence",
        )
        evidence_hashes, evidence_snapshot = verify_sealed_inventory(
            evidence_root, evidence_manifest, "execution-evidence", progress
        )
        phase_timings["sealedByteReplaySeconds"] = round(time.perf_counter() - phase_start, 3)

        hashes = CachedSourceHashes({**measured_hashes, **evidence_hashes})
        source_bindings = CachedSourceBindings(project_root, hashes)
        old_path = project_root / "Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v3_1.py"
        old = load_old_validator(old_path)
        old.sha256_file = lambda path: hashes.get(Path(path))
        old.RUNNER_METHOD = RUNNER_METHOD

        progress.emit("VERIFY_STATIC_AND_CONTROL_BINDINGS")
        phase_start = time.perf_counter()
        validate_static_bindings(project_root, evidence_root, hashes)
        control = validate_control_and_receipts(project_root, raw_root, evidence_root, old, hashes)
        phase_timings["controlAndReceiptSeconds"] = round(time.perf_counter() - phase_start, 3)

        progress.emit("SCAN_RAW_ROWS", table=None, completedTable=False)
        phase_start = time.perf_counter()
        raw_counts = scan_raw_tables(
            project_root,
            raw_root,
            project_root / "Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v3.json",
            old,
            hashes,
            source_bindings,
            control,
            progress,
        )
        phase_timings["streamingRawScanSeconds"] = round(time.perf_counter() - phase_start, 3)

        if inventory_snapshot(raw_root) != measured_snapshot:
            raise OfflineValidationError("measured root changed during offline validation")
        if inventory_snapshot(evidence_root) != evidence_snapshot:
            raise OfflineValidationError("execution-evidence root changed during offline validation")

        completed_utc = utc_now()
        result = {
            "schema": RESULT_SCHEMA,
            "studyId": "Gate14Re-ME",
            "status": PASS_STATUS,
            "startedAtUtc": started_utc,
            "completedAtUtc": completed_utc,
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "scope": "SEALED_RAW_NECESSARY_VALIDATION_ONLY",
            "sourceAttemptId": "load-qualification-execution-attempt-009",
            "sourceMeasuredRoot": raw_root.as_posix(),
            "qualificationTerminalPass": False,
            "offlineNecessaryRawValidationPass": True,
            "deliveryBuiltOrValidated": False,
            "typedParquetRoundTripValidated": False,
            "sealedInventory": {
                "measuredFiles": len(measured_manifest),
                "measuredBytes": sum(int(row["bytes"]) for row in measured_manifest.values()),
                "executionEvidenceFiles": len(evidence_manifest),
                "executionEvidenceBytes": sum(int(row["bytes"]) for row in evidence_manifest.values()),
                "allCurrentHashesMatchSeal": True,
                "sourceRootsUnchangedDuringValidation": True,
            },
            "controlPlane": {
                "acceptedSuperblocks": control["acceptedSuperblockCount"],
                "oracleReceipts": control["oracleReceiptCount"],
                "laneReceipts": control["laneReceiptCount"],
                "emptyBoundaryReceipts": control["emptyBoundaryReceiptCount"],
                "processLedgerRows": control["processLedgerRows"],
                "processIdentityReceipts": control["processIdentityReceipts"],
                "failureLedgerRows": 0,
                "replacementLedgerRows": 0,
                "runnerMethod": RUNNER_METHOD,
            },
            "rawValidation": raw_counts,
            "performance": {
                "phaseTimings": phase_timings,
                "distinctSourceFilesHashedOutsidePreverifiedSeal": hashes.computed,
                "sourceBindingReferences": hashes.references,
                "sourceHashCacheHits": hashes.cache_hits,
                "distinctRowBoundSourcePathsValidated": source_bindings.distinct_paths,
                "rowSourceBindingReferences": source_bindings.references,
                "rowSourceBindingPathCacheHits": source_bindings.cache_hits,
                "perRowFilesystemPathCanonicalization": False,
                "wholeDatasetRowsRetainedInMemory": False,
                "boundedGlobalD3IndexRows": raw_counts["tableRows"]["d3-windows"],
            },
            "boundaries": {
                "algorithmIdentityUnsealedDuringValidation": False,
                "algorithmEffectsComputed": False,
                "rankingOrWinnerComputed": False,
                "qualificationRowsUsedForFormalInference": False,
                "sourceRootsModified": False,
                "sameAttemptResumeOrRetryPerformed": False,
            },
            "scopeWarning": "This is not the original attempt-009 qualification terminal PASS and does not assert delivery or typed-Parquet PASS.",
        }
        write_json_atomic(output_path, result)
        progress.emit("TERMINAL", status=PASS_STATUS, output=output_path.as_posix())
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except Exception as exc:
        result = {
            "schema": RESULT_SCHEMA,
            "studyId": "Gate14Re-ME",
            "status": FAIL_STATUS,
            "startedAtUtc": started_utc,
            "completedAtUtc": utc_now(),
            "elapsedSeconds": round(time.perf_counter() - started, 3),
            "reason": str(exc),
            "qualificationTerminalPass": False,
            "offlineNecessaryRawValidationPass": False,
            "sourceRootsModified": False,
        }
        try:
            write_json_atomic(output_path, result)
            progress.emit("TERMINAL", status=FAIL_STATUS, reason=str(exc))
        except Exception:
            pass
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
