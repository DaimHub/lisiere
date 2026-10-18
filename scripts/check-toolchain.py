#!/usr/bin/env python3
"""Fail explicitly when project generation uses an unreviewed XcodeGen version."""
from pathlib import Path
import subprocess

expected = (Path(__file__).resolve().parents[1] / ".xcodegen-version").read_text().strip()
actual = subprocess.check_output(["xcodegen", "--version"], text=True).strip().removeprefix("Version: ")
if actual != expected:
    raise SystemExit(f"XcodeGen {expected} required, found {actual}. Review project generation before updating .xcodegen-version.")
