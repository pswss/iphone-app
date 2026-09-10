#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path

script = Path('ci_scripts/ci_post_clone.sh').resolve()
with tempfile.TemporaryDirectory(prefix='oneul-ci-') as directory:
    root = Path(directory)
    target = root / 'Oneul/Oneul/Secrets.swift'
    target.parent.mkdir(parents=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('ONEUL_')}
    env['CI_PRIMARY_REPOSITORY_PATH'] = str(root)
    subprocess.run(['sh', str(script)], env=env, check=True)
    assert 'static let pushRegisterKey = ""' in target.read_text()
    env.update(ONEUL_PUSH_SERVER_URL_HEX='https://example.com'.encode().hex(), ONEUL_PUSH_REGISTER_KEY='x' * 32 + '"\\(fatalError())\n')
    subprocess.run(['sh', str(script)], env=env, check=True)
    subprocess.run(['xcrun', 'swiftc', '-typecheck', str(target)], env=env, check=True)
    previous = target.read_bytes()
    env['ONEUL_PUSH_SERVER_URL_HEX'] = 'not-hex'
    assert subprocess.run(['sh', str(script)], env=env, capture_output=True).returncode != 0
    assert target.read_bytes() == previous
manifest = plistlib.loads(Path('Oneul/PrivacyInfo.xcprivacy').read_bytes())
assert {item['NSPrivacyCollectedDataType'] for item in manifest['NSPrivacyCollectedDataTypes']} == {
    'NSPrivacyCollectedDataTypeDeviceID', 'NSPrivacyCollectedDataTypeOtherUserContent'}
assert not manifest['NSPrivacyTracking']
print('Cloud configuration escaping, validation and privacy manifest checks passed')
PY
