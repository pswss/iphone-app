#!/bin/sh
# Xcode Cloud runs this beside Oneul.xcodeproj. Never echo secrets.
set -eu
cd "$(dirname "$0")"
python3 - <<'PYTHON'
import json
import os
from pathlib import Path
from urllib.parse import urlsplit

root = Path(os.environ.get("CI_PRIMARY_REPOSITORY_PATH", "../..")).resolve()
target = root / "Oneul/Oneul/Secrets.swift"

def url_value(name):
    value = os.environ.get(name, "").strip()
    if not value:
        return ""
    try:
        decoded = bytes.fromhex(value).decode("utf-8")
        url = urlsplit(decoded)
        if url.scheme != "https" or not url.hostname or url.username or url.password:
            raise ValueError()
        return decoded
    except (ValueError, UnicodeError):
        raise SystemExit(f"{name} must be a hex-encoded HTTPS URL")

values = {
    "pushServerURL": url_value("ONEUL_PUSH_SERVER_URL_HEX"),
    "pushRegisterKey": os.environ.get("ONEUL_PUSH_REGISTER_KEY", ""),
    "neisProxyBase": url_value("ONEUL_NEIS_PROXY_BASE_HEX"),
    "neisBakedKey": "",
}
if bool(values["pushServerURL"]) != bool(values["pushRegisterKey"]):
    raise SystemExit("Set both push URL and registration key, or leave both unset")
if values["pushRegisterKey"] and len(values["pushRegisterKey"]) < 32:
    raise SystemExit("ONEUL_PUSH_REGISTER_KEY must have at least 32 characters")
if not target.parent.is_dir():
    raise SystemExit("Cannot find Oneul/Oneul in the primary repository")
# JSON string escaping also prevents quotes, newlines and Swift interpolation from changing source.
source = "import Foundation\n\nenum Secrets {\n"
source += "".join(f"    static let {key} = {json.dumps(value, ensure_ascii=False)}\n" for key, value in values.items())
source += "}\n"
target.write_text(source)
print("Secrets.swift generated (values hidden)")
PYTHON
