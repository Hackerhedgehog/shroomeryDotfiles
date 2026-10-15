"""Protocol v2: subscriptions in, frames and errors out (README.md section 3).

Newline-delimited UTF-8 JSON. Adding fields is fine within v2; renaming or
removing one, or changing a zone order, means version 3. Subscriptions are
validated in regions.py.
"""
import json

VERSION = 2


def parse_line(line):
    """One client line -> its JSON object, or None for anything else."""
    try:
        msg = json.loads(line)
    except (ValueError, TypeError):
        return None
    return msg if isinstance(msg, dict) else None


def frame(monitor, source, windows, regions, t_ms):
    """regions: {id: {"colors": [hex...], "average": hex}}."""
    return {"v": VERSION, "type": "frame", "t": int(t_ms), "monitor": monitor,
            "source": source, "windows": int(windows), "regions": regions}


def error(message):
    return {"v": VERSION, "type": "error", "message": str(message)}


def encode(message):
    return (json.dumps(message, separators=(",", ":")) + "\n").encode()
