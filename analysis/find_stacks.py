"""Find bursts / near-identical shots ("stacks") like Google Photos does.

Input : folder_scan.csv  (made by tool\\scan_folder.ps1)
Output: stacks.csv       (columns Stack, Path) -> used by tool\\trips_and_stacks.ps1 or tool\\stacks_new.ps1

Rule (all must be true for two photos to be in the same stack):
  * same folder
  * taken at most --seconds apart (default 10)
  * picture fingerprint (dHash) differs by at most --max-distance bits (default 10)
  * same image width (so a crop / screenshot is not stacked with the original)

Usage:
  python find_stacks.py folder_scan.csv stacks.csv [--seconds 10] [--max-distance 10] [--only-under PREFIX]
"""
import argparse
from collections import defaultdict

from common import hamming, parse_time, read_csv, win_dirname, write_csv


def find_stacks(rows, seconds=10, max_distance=10, only_under=None):
    by_folder = defaultdict(list)
    for r in rows:
        if only_under and not r["Path"].lower().startswith(only_under.lower()):
            continue
        t = parse_time(r.get("Taken"))
        if t is None or not r.get("Hash"):
            continue
        by_folder[win_dirname(r["Path"])].append((t, r))

    stacks = []
    for items in by_folder.values():
        items.sort(key=lambda x: x[0])
        group = [items[0]] if items else []
        for prev, cur in zip(items, items[1:]):
            close_in_time = (cur[0] - prev[0]).total_seconds() <= seconds
            looks_same = hamming(prev[1]["Hash"], cur[1]["Hash"]) <= max_distance
            same_width = prev[1].get("W") == cur[1].get("W")
            if close_in_time and looks_same and same_width:
                group.append(cur)
            else:
                if len(group) > 1:
                    stacks.append([g[1]["Path"] for g in group])
                group = [cur]
        if len(group) > 1:
            stacks.append([g[1]["Path"] for g in group])
    return stacks


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder_scan")
    ap.add_argument("out")
    ap.add_argument("--seconds", type=float, default=10)
    ap.add_argument("--max-distance", type=int, default=10)
    ap.add_argument("--only-under", help="only look at paths starting with this, e.g. _Organized\\2025")
    a = ap.parse_args()
    stacks = find_stacks(read_csv(a.folder_scan), a.seconds, a.max_distance, a.only_under)
    out = [{"Stack": i + 1, "Path": p} for i, s in enumerate(stacks) for p in s]
    write_csv(a.out, ["Stack", "Path"], out)
    print(f"{len(stacks)} stacks, {len(out)} photos -> {a.out}")


if __name__ == "__main__":
    main()
