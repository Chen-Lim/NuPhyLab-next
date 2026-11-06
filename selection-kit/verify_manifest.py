#!/usr/bin/env python3
"""Verify delivered bytes. Standard library only; never changes project files."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys


def main():
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "MANIFEST.json").read_text(encoding="utf-8"))
    expected = set()
    errors = []
    for item in manifest["files"]:
        name = item["path"]
        parts = PurePosixPath(name)
        if parts.is_absolute() or ".." in parts.parts or name in expected:
            errors.append(f"Unsafe or duplicate manifest entry: {name}")
            continue
        expected.add(name)
        path = root.joinpath(*parts.parts)
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
            errors.append(f"Missing or unsafe file: {name}")
            continue
        data = path.read_bytes()
        if len(data) != item["bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
            errors.append(f"Content mismatch: {name}")
    # Build products generated after unpacking are deliberately not payload.
    ignored = {".build", ".swiftpm", "__pycache__", ".DS_Store"}
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*")
              if (p.is_file() or p.is_symlink()) and not any(v in ignored for v in p.relative_to(root).parts)}
    for name in sorted(actual - expected - {"MANIFEST.json"}):
        errors.append(f"Unexpected payload: {name}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Verified {len(expected)} payload files; all sizes and SHA-256 values match.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
