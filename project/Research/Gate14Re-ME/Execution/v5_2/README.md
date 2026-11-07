# Gate14Re-ME formal ST execution v5.2

This is a forward-only supervisor preflight corrigendum. It preserves the v5.1
Unity runner, host-lifecycle protocol, scientific design, six-algorithm cohort,
formal inputs, schedule, endpoints, metrics, sample rules, and all timeout
values.

The v5.1 external launch failed before measured-root creation because
PowerShell variable names are case-insensitive: the typed string parameter
`InputFreezeManifest` and the parsed-object local variable
`inputFreezeManifest` occupied the same variable slot. Assigning the parsed
JSON object therefore coerced it back to a string, and strict-mode access to
`.schema` failed.

v5.2 makes only these operational changes:

1. the parsed input-freeze object uses the non-colliding name
   `inputFreezeDocument`;
2. required JSON object properties are checked explicitly before property
   access;
3. the supervisor parses its own AST and rejects any case-insensitive
   assignment to a script parameter name;
4. an optional `PreflightOnly` switch runs the complete read-only preflight and
   returns before the measured-root mutation boundary;
5. detailed PowerShell error rendering is enabled for external diagnostics.

The failed attempt-001 is sealed and must never be retried or reused. A formal
collection, if separately confirmed, must use a new execution authorization,
evidence root, and measured root.
