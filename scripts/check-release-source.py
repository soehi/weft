"""Bind an actually downloaded archive's BUILD.json to its release tag commit."""
import json
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    metadata, = [name for name in archive.namelist() if name.endswith('/BUILD.json')]
    build = json.loads(archive.read(metadata))
    assert build['commit'] == sys.argv[2], (build['commit'], sys.argv[2])
    assert build['version'] == '0.3.0' and build['plan_version'] == '0.2.0'
print('OK: downloaded Release source commit and versions match tag')
