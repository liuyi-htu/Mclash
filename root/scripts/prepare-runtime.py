#!/usr/bin/env python3
"""Download the official arm64 core/geodata and verify GitHub's asset digests."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request

PROJECT = Path(__file__).resolve().parents[1]
HEADERS = {"User-Agent": "Mclash-Root-Build", "Accept": "application/vnd.github+json"}


def release(repo, tag=None):
    suffix = "latest" if not tag else "tags/" + urllib.parse.quote(tag, safe="")
    headers = dict(HEADERS)
    if os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/{suffix}", headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def asset(metadata, pattern):
    matches = [item for item in metadata["assets"] if re.fullmatch(pattern, item["name"])]
    if len(matches) != 1:
        raise SystemExit(f"Expected one asset matching {pattern}, got {len(matches)}")
    item = matches[0]
    digest = item.get("digest") or ""
    if not digest.startswith("sha256:"):
        raise SystemExit(f"Missing GitHub SHA-256 digest: {item['name']}")
    request = urllib.request.Request(item["browser_download_url"], headers={"User-Agent": HEADERS["User-Agent"]})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest().lower() != digest[7:].lower():
        raise SystemExit(f"SHA-256 mismatch: {item['name']}")
    return data


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def main():
    core = release("MetaCubeX/mihomo", os.environ.get("MIHOMO_VERSION"))
    binary = PROJECT / "android/app/src/main/jniLibs/arm64-v8a/libmihomo.so"
    write_atomic(binary, gzip.decompress(asset(core, r"mihomo-android-arm64-v8-v[^/]+\.gz")))
    binary.chmod(0o755)
    geodata = release("MetaCubeX/meta-rules-dat")
    directory = PROJECT / "android/app/src/main/assets/geodata"
    for name in ("geosite.dat", "geoip.dat", "country.mmdb"):
        write_atomic(directory / name, asset(geodata, re.escape(name)))
    write_atomic(directory / "mihomo-version.txt", (core["tag_name"] + "\n").encode())
    print(f"Root runtime prepared: Mihomo {core['tag_name']}")


if __name__ == "__main__":
    main()
