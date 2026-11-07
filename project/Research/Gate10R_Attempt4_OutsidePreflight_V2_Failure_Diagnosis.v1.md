# Gate 10R Attempt 4 outside-root preflight v2 failure diagnosis

Status: `FAILED-ATOMICALLY-CLOSED-RETRY-V3-AUTHORIZED`  
Official Gate 10R execution count: 0  
Unity started: no  
Official `v4` root created: no

The v2 preflight successfully captured all three expected-negative child exits, completed the mechanically derived file-scope retained harness at 63/63, and kept attempts 1–3 plus both frozen retained inputs byte-identical. Its sole failed check was the parent predicate for the frozen original summary: it required the output path to be absent even though that original summary is intentionally pre-existing protected evidence.

The harness returned exit code 1 as required and the original summary remained SHA-256 `1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d`. The v3 preflight changes only that predicate: for the pre-existing protected summary it requires a nonzero child exit and unchanged SHA-256; for a newly named forbidden target it continues to require absence. No harness or research-semantic input changes.

