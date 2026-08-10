#!/usr/bin/env python3
"""Extract PhaseXpert production validation observations from Xcode test logs."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
from typing import Any


PREFIX = "PHASEXPERT_VALIDATION_OBSERVATIONS_BASE64="
EXPECTED_SCHEMA_VERSION = "phasexpert-production-observations.v2"


def canonical(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n"


def extract_payload(log_text: str) -> dict[str, Any]:
    payloads = [
        line.split(PREFIX, 1)[1].strip()
        for line in log_text.splitlines()
        if PREFIX in line
    ]
    if len(payloads) != 1:
        raise ValueError(f"Expected exactly one observation payload, found {len(payloads)}.")
    try:
        decoded = base64.b64decode(payloads[0], validate=True)
    except Exception as error:
        raise ValueError("Observation payload is not valid Base64.") from error
    try:
        document = json.loads(decoded)
    except json.JSONDecodeError as error:
        raise ValueError("Observation payload is not valid JSON.") from error
    if document.get("schema_version") != EXPECTED_SCHEMA_VERSION:
        raise ValueError(
            "Observation payload schema_version is "
            f"{document.get('schema_version')!r}, expected {EXPECTED_SCHEMA_VERSION!r}."
        )
    if not isinstance(document.get("points"), list) or len(document["points"]) == 0:
        raise ValueError("Observation payload contains no points.")
    return document


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    document = extract_payload(args.log.read_text(encoding="utf-8"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(canonical(document), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
