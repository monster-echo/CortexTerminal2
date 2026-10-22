#!/usr/bin/env python3
"""Exercise PTY loading from the signed release, using a fresh bundle extraction."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def verify(target):
    target = Path(target).resolve()
    if target.is_file():
        binary = target
    else:
        binaries = list(target.rglob('assets/bin/corterm'))
        if not binaries:
            raise RuntimeError('Signed app has no bundled Worker')
        binary = binaries[0]
    with tempfile.TemporaryDirectory(prefix='corterm-pty-guard-') as temp:
        env = dict(os.environ, DOTNET_BUNDLE_EXTRACT_BASE_DIR=temp)
        result = subprocess.run(
            [str(binary), 'doctor', '--json'], env=env,
            capture_output=True, text=True, timeout=40,
        )
        # Auth/network/service checks may fail on CI. Only a real PTY is required.
        report = json.loads(result.stdout)
        pty = next(check for check in report['checks'] if check['name'] == 'PTY support')
        if pty['ok'] is not True:
            raise RuntimeError('Signed Worker PTY failed: ' + pty['detail'])
        print('Signed Worker PTY support: available (fresh native-library extraction)')


if __name__ == '__main__':
    try:
        verify(sys.argv[1])
    except (Exception, KeyboardInterrupt) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
