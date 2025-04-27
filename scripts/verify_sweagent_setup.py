#!/usr/bin/env python3
import sweagent
from pathlib import Path
import sys
# import pprint # Keep if using pprint below

cfg_dir: Path = sweagent.CONFIG_DIR
print(f"sweagent imported from   : {sweagent.__file__}")
print(f"Expected CONFIG_DIR path : {cfg_dir}")
# Silence verbose sys.path printing
# print(f'Python sys.path (first 5 + ...):')
# pprint.pprint(sys.path[:5] + ["..."])

if not cfg_dir.is_dir():
    print("❌  sweagent.CONFIG_DIR does not exist", file=sys.stderr)
    print(f"Contents of parent ({cfg_dir.parent}):")
    try:
        for p in cfg_dir.parent.glob("*"):
            print("  ", p, file=sys.stderr)
    except Exception as e:
        print(f"Error listing parent contents: {e}", file=sys.stderr)
    sys.exit(1)

print("✅  sweagent runtime directories are present")
