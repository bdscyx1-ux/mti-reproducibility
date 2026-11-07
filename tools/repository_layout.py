"""Locate manuscript-named folders while preserving frozen acquisition paths."""
from pathlib import Path, PurePosixPath
import json
ROOT = Path(__file__).resolve().parents[1]
MAPPING = json.loads((ROOT / 'docs/DIRECTORY_RENAME_MAP.json').read_text(encoding='utf-8'))

def _translate(value, source, target):
    value = str(value).replace('\\', '/')
    rel = PurePosixPath(value)
    if rel.is_absolute() or '..' in rel.parts or ':' in value:
        raise ValueError('Expected a safe repository-relative path: ' + value)
    for entry in sorted(MAPPING, key=lambda x: len(x[source]), reverse=True):
        prefix = entry[source]
        if value == prefix or value.startswith(prefix + '/'):
            return entry[target] + value[len(prefix):]
    return value

def repository_path(legacy_relative):
    return ROOT / _translate(legacy_relative, 'old', 'new')

def legacy_relative_path(current_relative):
    return _translate(current_relative, 'new', 'old')
