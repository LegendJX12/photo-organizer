"""Shared helpers for the analysis scripts (Python 3, standard library only)."""
import csv
import datetime as dt
import os
import re

DATE_FMT = "%Y-%m-%d %H:%M:%S"
NAME_DATE = re.compile(r"(20\d\d|19\d\d)[-_]?(\d\d)[-_]?(\d\d)[-_ ]?(\d\d)?[-_.]?(\d\d)?[-_.]?(\d\d)?")


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path, fieldnames, rows):
    """Write a UTF-8 (with BOM) CSV that PowerShell's Import-Csv reads correctly."""
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
        w.writeheader()
        w.writerows(rows)


def win_basename(path):
    """Basename of a Windows path (os.path.basename does not split on backslash on Linux/macOS)."""
    return path.replace("/", "\\").rsplit("\\", 1)[-1]


def win_dirname(path):
    p = path.replace("/", "\\")
    return p.rsplit("\\", 1)[0] if "\\" in p else ""


def parse_time(text):
    if not text:
        return None
    for fmt in (DATE_FMT, "%Y-%m-%d %H:%M", "%Y-%m-%d"):
        try:
            return dt.datetime.strptime(text.strip(), fmt)
        except ValueError:
            pass
    return None


def date_from_name(name):
    """Date/time encoded in a camera-style file name (IMG_20230501_123456.jpg), or None."""
    m = NAME_DATE.search(name)
    if not m:
        return None
    y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    hh, mm, ss = (int(g) if g else 0 for g in m.groups()[3:6])
    try:
        return dt.datetime(y, mo, d, min(hh, 23), min(mm, 59), min(ss, 59))
    except ValueError:
        return None


def hamming(a, b):
    """Distance between two 64-bit dHash strings of '0'/'1'. Large number if either is missing."""
    if not a or not b or len(a) != len(b):
        return 999
    return sum(x != y for x, y in zip(a, b))


def to_float(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def ensure_dir_of(path):
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
