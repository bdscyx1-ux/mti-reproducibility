# Recorded environments

The current original project's ProjectVersion.txt specifies Unity 2022.3.30f1c1, revision a6dc00fbe362. Its package manifest and lock are preserved under project/Packages. Those are source records, not a statement that every dependency is necessary for a minimal research release.

The submitted supplementary manuscript reports the following distinctions:

| Acquisition | Recorded analysis environment |
| --- | --- |
| Historical four-method planning | Standard library; analysis preflight records Python 3.14.7, but the final invocation version is not independently recorded |
| Historical expanded planning | Standard library; Python executable hash bound, patch version omitted from final output |
| Independent confirmation | Standard library; executable hash bound, final invocation version not independently recorded |
| Historical movement and MQ | Python 3.12.14 and NumPy 2.3.5 in contracts and validation records |
| SMSB | Python 3.12.14 and PyArrow 25.0.1 bound; NumPy is imported but its historical final-invocation version was not separately recorded |
| Corrected supplemental A and B | Python 3.12.14 bound; A uses standard library; B records NumPy 2.3.5 |

These are provenance statements. Do not fill historical version gaps with the versions installed during packaging. The portability validation used Python 3.12.14, NumPy 2.3.5 and Unity 2022.3.30f1c1. It reran the full supplemental analyses and compiled the separate minimal functional-check project. No new manuscript timing data were collected.

## Historical reproduction and figures (v3)

Validated with Python 3.12.14, NumPy 2.3.5, PyArrow 25.0.1 and Matplotlib 3.11.2 on Windows. Rendered PDF collision QA used PyMuPDF 2.1. Historical calculations were run in a relocated repository with original acquisition roots, the preparation repository, and development-result roots denied by audit hooks. Dependencies and checksummed input archives were supplied explicitly.
