# Gate 12R canonical-input upstream-reference test design

This test design applies only to the versioned correction in `Gate12R_Canonical_Input_Reference_Amendment.v1.json`. It does not change the experiment, the 5% precision target, or the frozen storage threshold.

## Static and unit gates

1. Re-hash the frozen Gate 11R bundle and all active upstream files.
2. Verify the externalizer accepts only a canonical file whose bytes, length, and SHA-256 exactly match the sample manifest and its frozen Gate 11R source.
3. Reject a source outside the frozen Gate 11R scenario root.
4. Reject local/source hash mismatch, length mismatch, absent source, absent local copy, unsafe path, already-externalized input, incomplete sample, and formal output.
5. Verify transformation is atomic: rewrite child manifest, sample summary, block manifest, wrapper summary, and a storage receipt using create-new/temporary-file replacement semantics; any failure leaves the block in a failed state.
6. Verify operations, workload result, telemetry fields, run ID, algorithm, position, predecessor, block ID, Williams order, reset flags, memory thresholds, and timing fields are byte- or value-identical before and after externalization.

## Fresh Unity positive gate

Run a complete positive Williams block in a new Unity process. Before externalization, validate the ordinary V2 result. Then externalize canonical copies and require:

- no per-sample `scenario.canonical.json` remains;
- every manifest resolves to its frozen upstream scenario;
- every resolved SHA-256 equals the original canonical SHA-256;
- the storage receipt lists the before/after manifest chain and removed raw bytes;
- the transformed block still passes process, Williams, reset, telemetry, memory, hash, provenance, and structural checks;
- structural outputs exact-match a frozen cold-process reference.

## Negative and repeatability gates

Run the existing injected failure and require fail-closed behavior with no later sample. Run independent positive blocks in distinct Unity processes and require structural exact-match. Tamper fixtures must demonstrate fail-closed rejection without weakening any threshold.

## Pilot and storage gate

Run one wholly fresh pilot in a new versioned root. Attempt-2 rows are prohibited. Block raw bytes are measured only after exact upstream externalization, so they represent incremental bytes that would actually be created in a new formal root. The unchanged nearest-rank p95, 1.5 safety multiplier, 20 GiB reserve, and fresh drive-free query are then applied. A failed storage projection remains a hard failure; no threshold may be relaxed and no cap may be introduced.
