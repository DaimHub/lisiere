#!/usr/bin/env python3
"""Validate release inputs without credentials; emit single-line GitHub environment values."""
import argparse
from pathlib import Path
import re


def metadata(project: str, tag: str) -> dict[str, str]:
    match = re.fullmatch(r"v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))(?:-([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?", tag)
    if not match:
        raise ValueError("Expected vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-prerelease")
    # Deliberately parse only this exact package block, not every exactVersion in the project.
    blocks = re.findall(r"^  Sparkle:\n((?:[ ]{4}.*\n|\n)+)", project, re.MULTILINE)
    if len(blocks) != 1:
        raise ValueError("Expected exactly one Sparkle package")
    versions = re.findall(r"^    exactVersion: ([0-9]+\.[0-9]+\.[0-9]+)\s*$", blocks[0], re.MULTILINE)
    if len(versions) != 1:
        raise ValueError("Sparkle must have one exact semantic version")
    return {"VERSION": tag[1:], "MARKETING_VERSION": match[1],
            "SPARKLE_VERSION": versions[0], "DMG": f"Lisiere-{tag[1:]}.dmg"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--project", type=Path, default=Path("project.yml"))
    args = parser.parse_args()
    try:
        for key, value in metadata(args.project.read_text(), args.tag).items():
            print(f"{key}={value}")
    except ValueError as error:
        parser.error(str(error))
