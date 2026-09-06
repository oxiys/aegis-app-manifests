#!/usr/bin/env python3
"""Update one application image without reformatting Kubernetes resources."""

import argparse
from pathlib import Path
import re

MANIFESTS = {
    'backend': '08-backend-deployment.yaml',
    'frontend': '09-frontend-deployment.yaml',
}


def update_image(root: Path, service: str, image: str) -> bool:
    if service not in MANIFESTS:
        raise ValueError(f'Unknown service: {service}')
    expected = rf'gcrbr/{service}:[0-9a-f]{{40}}'
    if not re.fullmatch(expected, image):
        raise ValueError(f'Expected gcrbr/{service}:<40-character lowercase commit SHA>')

    path = root / 'k8s' / MANIFESTS[service]
    original = path.read_text(encoding='utf-8')
    # This deliberately matches the existing manifest format and fails closed if
    # the container layout changes. An unrelated sidecar image is never replaced.
    pattern = re.compile(
        rf'(^[ \t]*- name: {re.escape(service)}[ \t]*\n'
        rf'[ \t]*image:[ \t]*)(\S+)([ \t]*(?:#[^\n]*)?)$',
        re.MULTILINE,
    )
    if len(list(pattern.finditer(original))) != 1:
        raise ValueError(f'Expected exactly one image for container {service} in {path}')
    updated = pattern.sub(lambda m: m[1] + image + m[3], original)
    if updated == original:
        return False
    path.write_text(updated, encoding='utf-8')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('service', choices=MANIFESTS)
    parser.add_argument('image')
    args = parser.parse_args()
    try:
        changed = update_image(Path(__file__).resolve().parents[1], args.service, args.image)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'{exc}\n')
    print('Manifest updated.' if changed else 'Manifest already uses this image.')


if __name__ == '__main__':
    main()
