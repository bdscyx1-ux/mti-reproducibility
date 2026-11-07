#!/usr/bin/env python3
"""Versioned v2 entry point correcting only canonical path ordering identity."""

from __future__ import annotations

import importlib.util
from pathlib import Path


CORE_PATH = Path(__file__).with_name("Analyze-Gate13RPR2Attempt2FailureV1.py")
SPEC = importlib.util.spec_from_file_location("gate13r_pr2_fd1_v1_core", CORE_PATH)
CORE = importlib.util.module_from_spec(SPEC)
if SPEC.loader is None:
    raise RuntimeError("Unable to load the frozen v1 diagnostic core")
SPEC.loader.exec_module(CORE)
CORE.EXPECTED_PREWRITE_TREE_SHA256 = "aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e"


if __name__ == "__main__":
    CORE.main()
