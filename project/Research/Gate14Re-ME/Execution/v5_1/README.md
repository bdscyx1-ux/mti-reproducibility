# Gate14Re-ME formal ST implementation v5.1

This directory is a forward-only host-lifecycle corrigendum for the frozen
formal ST v5 scientific design. It does not replace, modify, or reclassify the
v5.0 implementation or any earlier execution attempt.

The v5.1 implementation changes only process-host controls:

- the Unity runner is the sole owner of terminal exit (no command-line
  `-quit`);
- Unity startup/validation, mode execution, Burst drain, and final editor exit
  have separate structural phases and separate technical deadlines;
- lifecycle receipts are written under the measured root `_control` tree and
  do not enter any measured interval or algorithm observation;
- every `System.Diagnostics.Process` handle is disposed after observation;
- timeouts remain terminal fail-closed events with no same-attempt retry,
  resume, replacement, top-up, merge, skip, reorder, or parallel completion.

All scientific inputs, algorithms, factors, sample counts, metrics, fairness
bindings, schemas, and acceptance rules remain those of frozen formal ST v5.
