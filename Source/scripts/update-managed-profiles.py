"""Compatibility entry point for researched profile maintenance.

Default is a read-only plan. Pass --apply to update existing owned profiles.
Use build-character-profiles.mjs first after editing the research source files.
"""
import runpy
from pathlib import Path

if __name__ == '__main__':
    runpy.run_path(str(Path(__file__).with_name('apply-researched-profiles.py')), run_name='__main__')
