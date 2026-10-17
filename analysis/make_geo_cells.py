"""Group photo GPS points into ~10 km squares so places can be looked up once per area.

Input : folder_scan.csv (from tool\\scan_folder.ps1)
Output: geo_cells.csv   (Cell, Lat, Lon, Count) -> tool\\geocode.ps1 turns it into geo_names.csv

Usage: python make_geo_cells.py folder_scan.csv geo_cells.csv [--step 0.1]
"""
import argparse
from collections import Counter

from common import read_csv, to_float, write_csv


def cell_of(lat, lon, step=0.1):
    return f"{round(lat / step) * step:.1f},{round(lon / step) * step:.1f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder_scan")
    ap.add_argument("out")
    ap.add_argument("--step", type=float, default=0.1)
    a = ap.parse_args()
    c = Counter()
    for r in read_csv(a.folder_scan):
        lat, lon = to_float(r.get("Lat")), to_float(r.get("Lon"))
        if lat is None or lon is None or (lat == 0 and lon == 0):
            continue
        c[cell_of(lat, lon, a.step)] += 1
    rows = [{"Cell": k, "Lat": k.split(",")[0], "Lon": k.split(",")[1], "Count": n} for k, n in c.most_common()]
    write_csv(a.out, ["Cell", "Lat", "Lon", "Count"], rows)
    print(f"{len(rows)} areas -> {a.out}")


if __name__ == "__main__":
    main()
