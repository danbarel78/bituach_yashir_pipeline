#!/usr/bin/env python3
"""Pin image digests in a GitOps overlay from a digests file.

Input file format (one line per service, produced by the pipeline):

    engine ghcr.io/danbarel78/bituach-yashir-engine@sha256:<64 hex>
    data   ghcr.io/danbarel78/bituach-yashir-data@sha256:<64 hex>
    ingest ghcr.io/danbarel78/bituach-yashir-ingest@sha256:<64 hex>

Only the ``digest:`` line of each matching ``- name:`` entry is rewritten.
Anything unexpected (missing entry, duplicate entry) aborts without writing.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENVIRONMENTS = ("dev", "staging", "prod")
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def parse_digests(path: Path) -> dict[str, str]:
    """Return {service: 'sha256:...'} from the pipeline's digests file."""
    digests: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            sys.exit(f"malformed digests line: {raw!r}")
        service, reference = parts
        if "@" not in reference:
            sys.exit(f"digests line has no '@sha256:' reference: {raw!r}")
        digest = reference.split("@", 1)[1]
        if not DIGEST_RE.match(digest):
            sys.exit(f"not a sha256 digest: {digest!r}")
        if service in digests:
            sys.exit(f"duplicate digest entry for service {service!r}")
        digests[service] = digest
    if not digests:
        sys.exit("digests file is empty")
    return digests


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", required=True, choices=ENVIRONMENTS)
    parser.add_argument("--digests", required=True, help="path to digests.txt")
    args = parser.parse_args()

    overlay = ROOT / "gitops" / "overlays" / args.env / "kustomization.yaml"
    original = overlay.read_text(encoding="utf-8")
    text = original

    for service, digest in parse_digests(Path(args.digests)).items():
        image = f"ghcr.io/danbarel78/bituach-yashir-{service}"
        pattern = re.compile(
            r"(- name: " + re.escape(image) + r"\n[ \t]+digest: )sha256:[0-9a-f]{64}"
        )
        text, replacements = pattern.subn(r"\g<1>" + digest, text)
        if replacements != 1:
            sys.exit(
                f"expected exactly one digest entry for {image} in {overlay}, "
                f"found {replacements}"
            )

    if text == original:
        print(f"no changes: {overlay.relative_to(ROOT)} already pins these digests")
        return

    overlay.write_text(text, encoding="utf-8")
    print(f"pinned {len(parse_digests(Path(args.digests)))} image(s) in "
          f"{overlay.relative_to(ROOT)}")


if __name__ == "__main__":
    main()