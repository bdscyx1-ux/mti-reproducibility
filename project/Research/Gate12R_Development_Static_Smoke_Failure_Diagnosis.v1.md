# Gate 12R development static-smoke failure diagnosis v1

Status: `DIAGNOSED-BEFORE-OFFICIAL-ATTEMPT`

The isolated non-Unity development smoke at
`Research/Verification/Gate12R_ProcessReuse_5pct/development-static-smoke-v1`
failed one preservation assertion and created neither the official Gate 12R
verification root nor the Gate 12R pilot root.

## Confirmed cause

`Research/Gate12R_PreWrite_Preservation_Baseline.v1.json` copied the Gate 10R
terminal tree identity `ac7f70...53b2` into a field named
`ordinalTreeSha256`.  The bytes, file count, and raw-byte count are unchanged,
but the two identifiers use different ordering contracts:

- Gate 10R terminal identity sorts absolute `FullName` values with the
  PowerShell `Sort-Object` contract and yields `ac7f70...53b2`.
- The Gate 11R canonical preservation contract sorts project-relative rows
  with `StringComparer.Ordinal` and yields `a62fcb...beb6a`.

The latter identity was independently reproduced under Windows PowerShell 5.1
and PowerShell 7 during Gate 11R attempt 2.  Current read-only recomputation is
also `169` files, `14,661,848` raw bytes, and ordinal tree SHA-256
`a62fcb5c0104e1ce493d8ca006f753cbd20341839c588c6ffd856cbe438beb6a`.

## Controlled correction

The v1 baseline, v1 provenance, and failed development-smoke evidence remain
byte-preserved.  A new v2 compatibility baseline records both identities and
changes no protected input, experiment design, Williams order, threshold,
telemetry rule, reset rule, 5% precision rule, no-cap policy, scenario, or
Playable mapping.  Official execution may use only a new provenance that binds
the v2 baseline and a versioned file-scope static-audit wrapper.

