"""Plan trip folders from photo GPS (like Google Photos "Trips" / places).

Input : folder_scan.csv (tool\\scan_folder.ps1) + geo_names.csv (tool\\geocode.ps1)
Output: trip_moves.csv  (Source, Destination) -> tool\\trips_and_stacks.ps1 moves the files

How it decides:
  1. Every photo with GPS gets a place (city / state / country) from geo_names.csv.
  2. A day is an "away" day when most of that day's GPS photos are outside your --home places.
  3. Away days in a row form one trip, even across months and years. Short gaps of days with no
     GPS photos (up to --gap days) stay inside the trip. A "home" day ends the trip.
  4. Trip folder:  _Organized\\<year>\\<first day> <Country> Trip\\<MM-DD> <City>\\<file>
     Photos without GPS taken on a trip day go into that day's folder.
  5. By default only photos sitting in plain month folders (_Organized\\YYYY\\YYYY-MM) are moved,
     so albums you named yourself are never split up. Use --include-albums to change that.

Usage:
  python plan_trips.py folder_scan.csv geo_names.csv trip_moves.csv \\
      --home "Singapore" --home "Malaysia/Kuala Lumpur" --home "Malaysia/Selangor"
  (--home is "Country" or "Country/State"; repeat it for each home area)
"""
import argparse
import re
from collections import Counter, defaultdict
from datetime import timedelta

from make_geo_cells import cell_of
from common import parse_time, read_csv, to_float, win_basename, write_csv

MONTH_FOLDER = re.compile(r"^_Organized\\\d{4}\\\d{4}-\d{2}\\[^\\]+$", re.I)
BAD_CHARS = re.compile(r'[<>:"/\\|?*]')


def is_home(place, homes):
    country, state = (place.get("Country") or "").lower(), (place.get("State") or "").lower()
    city = (place.get("City") or "").lower()
    for h in homes:
        parts = [p.strip().lower() for p in h.split("/")]
        if parts[0] != country:
            continue
        if len(parts) == 1 or parts[1] in (state, city):
            return True
    return False


def clean(name):
    return BAD_CHARS.sub("-", name).strip() or "Unknown"


def plan(scan, names, homes, gap=2, include_albums=False):
    places = {r["Cell"]: r for r in names}
    day_votes = defaultdict(Counter)       # date -> Counter(home/away)
    day_city = defaultdict(Counter)
    day_country = defaultdict(Counter)
    photos_by_day = defaultdict(list)
    for r in scan:
        t = parse_time(r.get("Taken"))
        if t is None:
            continue
        movable = include_albums or MONTH_FOLDER.match(r["Path"])
        if movable:
            photos_by_day[t.date()].append(r["Path"])
        lat, lon = to_float(r.get("Lat")), to_float(r.get("Lon"))
        if lat is None or lon is None or (lat == 0 and lon == 0):
            continue
        p = places.get(cell_of(lat, lon))
        if not p or p.get("Display") == "ERROR":
            continue
        home = is_home(p, homes)
        day_votes[t.date()]["home" if home else "away"] += 1
        if not home:
            day_city[t.date()][p.get("City") or p.get("State") or p.get("Country")] += 1
            day_country[t.date()][p.get("Country") or "Abroad"] += 1

    away = sorted(d for d, v in day_votes.items() if v["away"] > v["home"])
    home_days = {d for d, v in day_votes.items() if v["home"] >= v["away"]}

    trips, cur = [], []
    for d in away:
        if cur:
            gap_days = [cur[-1] + timedelta(days=i) for i in range(1, (d - cur[-1]).days)]
            if len(gap_days) > gap or any(g in home_days for g in gap_days):
                trips.append(cur)
                cur = []
        cur.append(d)
    if cur:
        trips.append(cur)

    moves = []
    for days in trips:
        start, end = days[0], days[-1]
        country = Counter()
        for d in days:
            country.update(day_country[d])
        top = country.most_common(1)[0][0] if country else "Abroad"
        trip_dir = f"_Organized\\{start.year}\\{start:%Y-%m-%d} {clean(top)} Trip"
        d = start
        last_city = None
        while d <= end:
            if d in day_city:
                last_city = day_city[d].most_common(1)[0][0]
            if d not in home_days:
                stop = f"{d:%m-%d} {clean(last_city or top)}"
                for src in photos_by_day.get(d, []):
                    moves.append({"Source": src, "Destination": f"{trip_dir}\\{stop}\\{win_basename(src)}"})
            d += timedelta(days=1)
    return trips, moves


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder_scan")
    ap.add_argument("geo_names")
    ap.add_argument("out")
    ap.add_argument("--home", action="append", required=True, help='"Country" or "Country/State"')
    ap.add_argument("--gap", type=int, default=2, help="no-GPS days allowed inside a trip (default 2)")
    ap.add_argument("--include-albums", action="store_true")
    a = ap.parse_args()
    trips, moves = plan(read_csv(a.folder_scan), read_csv(a.geo_names), a.home, a.gap, a.include_albums)
    write_csv(a.out, ["Source", "Destination"], moves)
    for t in trips:
        print(f"  trip {t[0]} -> {t[-1]}  ({len(t)} days with GPS away)")
    print(f"{len(trips)} trips, {len(moves)} files to move -> {a.out}")


if __name__ == "__main__":
    main()
