# Gate14Re-ME formal ST execution v5.3

This is a forward-only execution-authorization contract-parity corrigendum. It
preserves the v5.1 Unity runner, host-lifecycle protocol, scientific design,
six-algorithm cohort, formal inputs, schedule, endpoints, metrics, sample
rules, process cardinalities, and every timeout value.

The failed attempt-002 reached the ordinal-zero instrument self-test, where the
Unity runner rejected the execution authorization before any instrument or
algorithm work. The attempt authorization carried the collection-only scope
booleans and hashes but omitted typed fields required by
`Gate14ReMEFormalSTExecutionAuthorizationV5`, including the nonce and exact
artifact path bindings. The v5.2 PowerShell preflight did not enforce parity
with that complete runner contract.

v5.3 makes only these operational changes:

1. the supervisor requires every field consumed by the typed Unity execution
   authorization contract before crossing the measured-root mutation boundary;
2. all authorization path fields are compared with the exact launch artifacts;
3. the authorization nonce must be a lower-case UUIDv4;
4. preflight and process identity receipts identify revision v5.3 and record
   successful authorization-contract parity.

The failed attempts 001 and 002 are sealed and must never be retried, resumed,
or reused. A formal collection requires a fresh execution authorization,
evidence root, measured root, and a newly confirmed exact command.
