#!/usr/bin/env python3
"""Generate a macOS forced-preferences payload; contains configuration, never secrets."""
import argparse
import json
import plistlib
import uuid
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('config', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
brand = json.loads((root / 'Sources/LocalAgentCore/Resources/Branding.json').read_text())
policy = json.loads(args.config.read_text())
identifier = brand['bundleIdentifier']
profile = {
    'PayloadType': 'Configuration', 'PayloadVersion': 1,
    'PayloadIdentifier': identifier + '.policy', 'PayloadUUID': str(uuid.uuid4()),
    'PayloadDisplayName': brand['displayName'] + ' Policy', 'PayloadScope': 'System',
    'PayloadContent': [{
        'PayloadType': 'com.apple.ManagedClient.preferences', 'PayloadVersion': 1,
        'PayloadIdentifier': identifier + '.preferences', 'PayloadUUID': str(uuid.uuid4()),
        'PayloadContent': {identifier: {'Forced': [{'mcx_preference_settings': {
            'PolicyJSON': json.dumps(policy, separators=(',', ':'))
        }}]}},
    }],
}
args.output.parent.mkdir(parents=True, exist_ok=True)
with args.output.open('wb') as f:
    plistlib.dump(profile, f)
print(args.output)
