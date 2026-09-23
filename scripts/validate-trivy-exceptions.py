#!/usr/bin/env python3
"""Validate narrowly scoped, temporary Trivy vulnerability exemptions."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Iterable

MAX_EXCEPTION_DAYS = 30
ENTRY_KEYS = {"id", "purls", "statement", "expired_at"}
STATEMENT_KEYS = {"ticket", "owner", "approved_by", "justification"}
ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]+$")


class PolicyError(ValueError):
    """Raised when exemption policy validation fails."""


def parse_statement(statement: str, label: str) -> None:
    metadata: dict[str, str] = {}
    for part in statement.split(";"):
        key, separator, value = part.strip().partition("=")
        if not separator or not key or not value.strip():
            raise PolicyError(
                f"{label}.statement must contain semicolon-separated key=value fields"
            )
        if key in metadata:
            raise PolicyError(f"{label}.statement repeats {key!r}")
        metadata[key] = value.strip()
    if set(metadata) != STATEMENT_KEYS:
        missing = sorted(STATEMENT_KEYS - set(metadata))
        unknown = sorted(set(metadata) - STATEMENT_KEYS)
        raise PolicyError(
            f"{label}.statement fields are invalid; missing={missing}, unknown={unknown}"
        )
    if len(metadata["justification"]) < 20:
        raise PolicyError(f"{label}.statement justification must be at least 20 characters")


def validate_policy(data: Any, today: date) -> list[dict[str, Any]]:
    if not isinstance(data, dict) or set(data) != {"vulnerabilities"}:
        raise PolicyError("policy must contain exactly one top-level vulnerabilities key")
    entries = data["vulnerabilities"]
    if not isinstance(entries, list):
        raise PolicyError("vulnerabilities must be a list")
    seen: set[tuple[str, str]] = set()
    for index, entry in enumerate(entries):
        label = f"vulnerabilities[{index}]"
        if not isinstance(entry, dict):
            raise PolicyError(f"{label} must be an object")
        if set(entry) != ENTRY_KEYS:
            missing = sorted(ENTRY_KEYS - set(entry))
            unknown = sorted(set(entry) - ENTRY_KEYS)
            raise PolicyError(f"{label} fields are invalid; missing={missing}, unknown={unknown}")
        vulnerability_id = entry["id"]
        if not isinstance(vulnerability_id, str) or not ID_PATTERN.fullmatch(vulnerability_id):
            raise PolicyError(f"{label}.id is not a valid vulnerability identifier")
        purls = entry["purls"]
        if not isinstance(purls, list) or not purls:
            raise PolicyError(f"{label}.purls must be a non-empty list")
        if len(purls) != len(set(purls)):
            raise PolicyError(f"{label}.purls contains duplicate values")
        for purl in purls:
            if (
                not isinstance(purl, str)
                or not purl.startswith("pkg:")
                or "@" not in purl
                # '?' introduces standard Package URL qualifiers; it is not a
                # wildcard here. Reject only actual glob metacharacters.
                or any(character in purl for character in "*[]")
            ):
                raise PolicyError(f"{label}.purls must contain exact, versioned package URLs")
            key = (vulnerability_id, purl)
            if key in seen:
                raise PolicyError(f"duplicate exemption for {vulnerability_id} and {purl}")
            seen.add(key)
        statement = entry["statement"]
        if not isinstance(statement, str):
            raise PolicyError(f"{label}.statement must be a string")
        parse_statement(statement, label)
        expiry_text = entry["expired_at"]
        if not isinstance(expiry_text, str) or not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T00:00:00Z", expiry_text
        ):
            raise PolicyError(f"{label}.expired_at must use YYYY-MM-DDT00:00:00Z")
        try:
            expiry = datetime.strptime(expiry_text, "%Y-%m-%dT%H:%M:%SZ").date()
        except ValueError as error:
            raise PolicyError(f"{label}.expired_at is not a valid UTC timestamp") from error
        days = (expiry - today).days
        if days <= 0:
            raise PolicyError(f"{label} expired on {expiry_text}")
        if days > MAX_EXCEPTION_DAYS:
            raise PolicyError(
                f"{label} expires in {days} days; maximum is {MAX_EXCEPTION_DAYS}"
            )
    return entries


def load_policy(path: Path, today: date) -> list[dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PolicyError(f"cannot parse {path} as strict JSON-compatible YAML: {error}") from error
    return validate_policy(data, today)


def vulnerability_pairs(node: Any) -> Iterable[tuple[str, str]]:
    if isinstance(node, dict):
        vulnerability_id = node.get("VulnerabilityID")
        identifier = node.get("PkgIdentifier")
        if isinstance(vulnerability_id, str) and isinstance(identifier, dict):
            purl = identifier.get("PURL")
            if isinstance(purl, str):
                yield vulnerability_id, purl
        for value in node.values():
            yield from vulnerability_pairs(value)
    elif isinstance(node, list):
        for value in node:
            yield from vulnerability_pairs(value)


def validate_evidence(entries: list[dict[str, Any]], reports: list[Path]) -> None:
    if not reports:
        return
    observed: set[tuple[str, str]] = set()
    for report in reports:
        try:
            data = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise PolicyError(f"cannot parse Trivy report {report}: {error}") from error
        observed.update(vulnerability_pairs(data.get("Results", [])))
        observed.update(vulnerability_pairs(data.get("ExperimentalModifiedFindings", [])))
    expected = {(entry["id"], purl) for entry in entries for purl in entry["purls"]}
    unused = sorted(expected - observed)
    if unused:
        formatted = ", ".join(f"{item[0]} ({item[1]})" for item in unused)
        raise PolicyError(f"unused exemptions must be removed or corrected: {formatted}")


def self_test() -> None:
    today = date(2026, 9, 23)
    valid = {
        "vulnerabilities": [{
            "id": "CVE-2026-12345",
            "purls": ["pkg:maven/example/component@1.0.0?type=jar"],
            "statement": (
                "ticket=SEC-123; owner=platform; approved_by=security; "
                "justification=Vulnerable feature is unreachable in this deployment"
            ),
            "expired_at": "2026-10-20T00:00:00Z",
        }]
    }
    validate_policy(valid, today)
    invalid_cases = []
    for mutation in ("expired", "too_long", "unknown", "unversioned", "metadata"):
        candidate = json.loads(json.dumps(valid))
        entry = candidate["vulnerabilities"][0]
        if mutation == "expired":
            entry["expired_at"] = "2026-09-23T00:00:00Z"
        elif mutation == "too_long":
            entry["expired_at"] = "2026-11-01T00:00:00Z"
        elif mutation == "unknown":
            entry["expires"] = entry.pop("expired_at")
        elif mutation == "unversioned":
            entry["purls"] = ["pkg:maven/example/component"]
        else:
            entry["statement"] = "ticket=SEC-123; justification=This is deliberately incomplete"
        invalid_cases.append(candidate)
    for candidate in invalid_cases:
        try:
            validate_policy(candidate, today)
        except PolicyError:
            continue
        raise AssertionError("validator accepted an invalid exemption policy")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", nargs="?", type=Path)
    parser.add_argument("--report", action="append", default=[], type=Path)
    parser.add_argument("--today", type=date.fromisoformat)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--count", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("[clamp] Trivy exemption validator self-tests passed")
        return 0
    if args.policy is None:
        parser.error("policy is required unless --self-test is used")
    today = args.today or datetime.now(timezone.utc).date()
    entries = load_policy(args.policy, today)
    if args.count:
        print(len(entries))
        return 0
    validate_evidence(entries, args.report)
    print(f"[clamp] Validated {len(entries)} controlled Trivy exemption(s)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PolicyError as error:
        print(f"[clamp] ERROR: {error}", file=sys.stderr)
        sys.exit(1)
