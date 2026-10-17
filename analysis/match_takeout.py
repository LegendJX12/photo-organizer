"""Find Google Photos items (from a Takeout export) that are NOT already in your photos folder.

Input : takeout_files.csv + takeout_meta.csv (tool\\takeout_scan.ps1)
        folder_scan.csv                      (tool\\scan_folder.ps1)
Output: google_import.csv (Source, Destination, Date) -> tool\\google_import.ps1 copies them

A Google item counts as "already have it" when ANY of these match a local photo:
  1. same file size and same picture fingerprint (dHash)
  2. same file name and same day taken
  3. fingerprint differs by at most --max-distance bits (default 6) and taken within 48 hours
Google's Trash folder and the .json info files are skipped.

Where new items go: the _Organized folder that already holds most photos from that same day,
otherwise _Organized\\<year>\\<year-month>. The date comes from the file name, or from Google's
info file when the name has no date or its year disagrees with Google's year folder.

Usage: python match_takeout.py takeout_files.csv takeout_meta.csv folder_scan.csv google_import.csv
"""
import argparse
import datetime as dt
import re
from collections import Counter, defaultdict

from common import date_from_name, hamming, parse_time, read_csv, win_basename, win_dirname, write_csv

MEDIA = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".webp", ".bmp", ".tif", ".tiff", ".dng",
         ".mp4", ".mov", ".avi", ".mkv", ".m4v", ".3gp", ".mp", ".webm"}
YEAR_FOLDER = re.compile(r"Photos from (\d{4})", re.I)


def ext(name):
    i = name.rfind(".")
    return name[i:].lower() if i >= 0 else ""


def google_dates(meta):
    """Map takeout file path -> datetime from the supplemental-metadata json."""
    out = {}
    for m in meta:
        j = m["Json"]
        base = j.split(".supplemental-metadata")[0] if ".supplemental-metadata" in j else j[:-5]
        try:
            out[base.lower()] = dt.datetime.fromtimestamp(int(m["Taken"]), dt.timezone.utc).replace(tzinfo=None)
        except (TypeError, ValueError):
            pass
    return out


def match(tk_files, tk_meta, scan, max_distance=6):
    gdate = google_dates(tk_meta)
    local_by_size = defaultdict(list)
    local_by_name_day = set()
    local_by_day = defaultdict(list)
    folder_by_day = defaultdict(Counter)
    for r in scan:
        t = parse_time(r.get("Taken"))
        local_by_size[r["Size"]].append(r)
        if t:
            local_by_name_day.add((win_basename(r["Path"]).lower(), t.date()))
            local_by_day[t.date()].append(r)
            folder_by_day[t.date()][win_dirname(r["Path"])] += 1

    out, have = [], 0
    for f in tk_files:
        p = f["Path"]
        if p.lower().startswith("trash\\") or ext(p) not in MEDIA:
            continue
        name = win_basename(p)
        t_name, t_google = date_from_name(name), gdate.get(p.lower())
        yf = YEAR_FOLDER.search(p)
        t = t_name
        if t is None or (yf and t_google and t.year != int(yf.group(1))):
            t = t_google or t_name

        # rule 1: same size, and same fingerprint when both files have one (videos have none)
        found = any(not f.get("Hash") or not r.get("Hash") or f["Hash"] == r["Hash"]
                    for r in local_by_size.get(f["Size"], []))
        if not found and t is not None:
            found = (name.lower(), t.date()) in local_by_name_day
        if not found and t is not None and f.get("Hash"):
            for d in (t.date() - dt.timedelta(days=i) for i in range(-2, 3)):
                for r in local_by_day.get(d, []):
                    rt = parse_time(r["Taken"])
                    if rt and abs((rt - t).total_seconds()) <= 48 * 3600 and hamming(f["Hash"], r.get("Hash")) <= max_distance:
                        found = True
                        break
                if found:
                    break
        if found:
            have += 1
            continue

        if t is None:
            dest_dir = "_Needs review\\No date found (Google)"
        elif folder_by_day.get(t.date()):
            dest_dir = folder_by_day[t.date()].most_common(1)[0][0]
        else:
            dest_dir = f"_Organized\\{t.year}\\{t:%Y-%m}"
        if ext(name) == ".mp":  # Pixel motion-photo video part
            name = name[:-3] + ".mp4"
            dest_dir += "\\motion clips"
        out.append({"Source": p, "Destination": f"{dest_dir}\\{name}", "Date": f"{t:%Y-%m-%d %H:%M}" if t else ""})
    return have, out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("takeout_files")
    ap.add_argument("takeout_meta")
    ap.add_argument("folder_scan")
    ap.add_argument("out")
    ap.add_argument("--max-distance", type=int, default=6)
    a = ap.parse_args()
    have, rows = match(read_csv(a.takeout_files), read_csv(a.takeout_meta), read_csv(a.folder_scan), a.max_distance)
    write_csv(a.out, ["Source", "Destination", "Date"], rows)
    print(f"already in folder: {have}   new to import: {len(rows)} -> {a.out}")


if __name__ == "__main__":
    main()
