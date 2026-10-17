# Workflow details

This is the full workflow behind the tools: the rules each step uses, the file it reads and writes, and lessons from running it on a real folder of about 18,000 photos and videos (plus 12,500 Google Photos items).

```
 messy folder ─► 1 organize ─► 2 duplicates ─► 3 trips + stacks ─► 4 Google Photos ─► 5 cloud clean-up
                 (plan/apply)   (verify/recycle)  (scan/geo/plan)     (takeout/match)     (OneDrive / Drive)
```

Every stage follows the same pattern:

1. a **read-only scan** writes a CSV
2. a **plan** CSV is made (by a script in `analysis/`, or by hand / with an AI assistant)
3. **you review** the plan (CSV in Excel, or the HTML preview)
4. an **apply** step changes files, logs everything and writes an undo file

---

## 1. Organize (steps 0–3)

| | |
|---|---|
| Scripts | `extract.ps1`, `plan.ps1`, `apply.ps1`, `undo.ps1` |
| Writes | `plan.csv` (Action, Source, Destination, Date, DateSource, Album, FromFolder, Note, DupOf, Size), `summary.txt`, `undo.csv` |

- **Date** comes from, in order: a date in the file name (`IMG_20230501_…`, `20230501_…`, WhatsApp `IMG-20230501-WA…`, and the epoch numbers in `mmexport…` / `FB_IMG_…` / `wx_camera_…`) → the photo's own "Date taken" info → otherwise `_Needs review`.
- **Albums you already made** keep their name and their subfolders: `YYYY-MM-DD Name` when dated, `YYYY-MM Name` when not.
- **Loose photos** go into `YYYY\YYYY-MM`. A loose photo joins an existing album when it was taken on that album's dates.
- A short undated album (≤ 10 days) only pulls in loose photos from its dates once it has **30 or more** photos. This stops a small album "stealing" unrelated photos.
- **Exact duplicates** (same size + same content) go to `_Duplicates (review then delete)`. Nothing is deleted at this stage.
- **Never** judge a duplicate by name alone: phones reuse names like `IMG_0001.JPG` for completely different pictures.

## 2. Duplicates and look-alikes (steps 4–6)

| | |
|---|---|
| Scripts | `verify.ps1`, `clean_and_rescan.ps1`, `lookalike_cleanup.ps1` |
| Reads | `dup_pairs.csv` (Duplicate, Kept, Size): the `Duplicate` rows of `plan.csv` with their `DupOf` |
| Writes | `verify_report.txt`, `rescan_report.txt`, `lookalikes.csv` / `.html`, `exact_left.csv` |
| You make | `lookalike_actions.csv` (Group, Keep, Remove, MoveKeepTo) |

- `verify` re-checks each pair with **SHA256 + exact size**. Only pairs that pass are recycled.
- **0-byte files** are all "identical" to each other. They are reported separately, never treated as duplicates.
- **Look-alikes** are the same picture saved twice at different quality (e.g. the original and a WhatsApp / Facebook copy). They are found with a 9×8 **dHash** fingerprint plus a 64×64 grey pixel comparison:
  - mean difference ≤ 1.2 → the same picture; keep the larger file
  - 2–3 or more → a burst / different moment; keep both
- Plain dark or white images give the same dHash even when years apart, so look-alikes must also be **close in time**.

## 3. Trips, places and similar-shot stacks (steps 8–12)

| | |
|---|---|
| Scripts | `scan_folder.ps1`, `geocode.ps1`, `trips_and_stacks.ps1`, `undo_trips.ps1`, `stack_edits.ps1` |
| Analysis | `make_geo_cells.py`, `plan_trips.py`, `find_stacks.py` |
| Files | `folder_scan.csv` (Path, Size, Modified, Taken, Lat, Lon, W, H, Hash) → `geo_cells.csv` (Cell, Lat, Lon, Count) → `geo_names.csv` (Cell, City, State, Country, Display) → `trip_moves.csv` (Source, Destination) + `stacks.csv` (Stack, Path) |

**Places.** GPS points are rounded to 0.1° squares (about 10 km), so OpenStreetMap is asked about ~250 areas instead of 17,000 photos. `geocode.ps1` waits 1.1 s between requests (OpenStreetMap's usage policy) and can resume if stopped.

**Trips** (`plan_trips.py`):
- You list your **home** areas, e.g. `--home Singapore --home "Malaysia/Kuala Lumpur"`. Anywhere else is a trip.
- Away days in a row are one trip, **across months and years** (a New Year trip stays together).
- Up to `--gap` days without GPS can sit inside a trip; a home day ends it.
- Folder layout: `YYYY\YYYY-MM-DD <Country> Trip\MM-DD <City>\`.
- No-GPS days inside a trip go into that trip; no-GPS days outside any trip are left where they are, for you to decide.
- Long trips (e.g. an exchange semester) can be split into phases by editing `trip_moves.csv` before applying.

**Stacks** (`find_stacks.py`): same folder, ≤ 10 s apart, dHash distance ≤ 10, same width.
- The **sharpest** shot (Laplacian variance at 512 px) stays in place.
- The others move into `<best> - similar shots\`, and `similar_shots.html` shows each stack side by side with sharpness scores.

**Reviewing stacks.** Write your decisions into `stack_edits.csv` (Action = `move` / `recycle`, From, To). Useful review words:

| You say | Meaning |
|---|---|
| "#15 and #16 same group" | merge the two stacks |
| "keep another one" | swap which photo is on top |
| "keep all" | undo the stack |
| "remove" | delete the **whole** group, best shot included |

## 4. Google Photos (steps 14–18)

| | |
|---|---|
| Scripts | `takeout_unzip.ps1`, `takeout_scan.ps1`, `google_import.ps1`, `undo_google_import.ps1`, `stacks_new.ps1` |
| Analysis | `match_takeout.py` |
| Files | `takeout_files.csv` (Path, Size, Hash, W, H) + `takeout_meta.csv` (Json, Title, Taken, Lat, Lon) → `google_import.csv` (Source, Destination, Date) |

1. Export from takeout.google.com (Google Photos only, .zip, 50 GB parts). Download the parts to **Downloads**.
2. `takeout_unzip` unzips with Windows `tar` (which checks every file's checksum) and checks the extracted sizes; errors go to `unzip_errors_*.txt`.
3. `match_takeout.py` marks a Google item as **already have** when:
   - size and fingerprint match, or
   - name and day match, or
   - dHash ≤ 6 within 48 h.

   Google's `Trash` folder is skipped.
4. **Dates:** file-name date first. If the name's year disagrees with Google's `Photos from YYYY` folder, Google's `photoTakenTime` wins. (A phone with a wrong clock produced `IMG_2026…` names for 2023 photos.)
5. Pixel **motion photos** (`.MP`) become `.mp4` in a `motion clips` subfolder.
6. `stacks_new` stacks the imported photos. Run `find_stacks.py --only-under` on the new folders to make `stacks_new.csv`.

## 5. Cloud clean-up (steps 20–27)

### OneDrive brings old files back
If the photos folder lives inside **OneDrive** and you reorganize while OneDrive is paused or closed, OneDrive can **download the old copies back** to their old paths when it resumes. This happens especially if you click "Restore" on its *"You deleted many files"* prompt.

- `onedrive_check` lists everything outside `_Organized`. Each file is compared by **size + SHA256** against `_Organized`; zips are compared entry by entry.
- Files the earlier logs confirm you deleted on purpose are marked separately. Anything unconfirmed goes to `_Review after OneDrive` instead of the Recycle Bin.
- **Lesson:** keep OneDrive **running** during big reorganizations. When it asks "Delete these items?", choose **Delete everywhere**, not Restore.

### Google Drive
- `gdrive_compare` scans the **Google Drive for desktop** drive (`G:\My Drive`). It matches by **name + size** only, so streamed files are not downloaded.
- Files in **friends' shared folders** do **not** appear under `G:\My Drive`, and a "shortcut" does not make them readable either. To reach them, move your own files into My Drive first (Drive web or API).
- Files **owned by others** don't count against your storage and must never be deleted. `drive_owned` only works on a manifest of files you own (`drive_owned_manifest.csv`: Id, Name, Size, GPath, CopyTo).
- `gdrive_cleanup` / `drive_owned -Apply` delete from Drive **only** when a same-size copy is in `_Organized`. Missing ones are copied first; if a copy fails, the file stays.
- Deleted Drive files go to **Trash**. Storage is only freed after you **Empty trash**, and syncing deletions can take a few minutes.
- **Lesson:** during a copy, Windows reserves the full file size immediately. A file showing its full size can still be copying; check that its "modified" time has stopped changing.

### Merge years
`merge_years.ps1` reads `merge_years.csv` (Target, Years separated by `;`) and flattens those year folders into one, e.g. `2009-2010 Childhood`.
- Same name + same content: the extra copy is recycled.
- Same name but a different photo: it is renamed `name (2).jpg`.

---

## Technical notes
- **Scripts are ASCII-only.** Windows PowerShell 5.1 misreads UTF-8 scripts without a BOM, so Chinese folder names are built from character codes (see `gdrive_compare.ps1`).
- **Launchers** run `chcp 65001` and `-ExecutionPolicy Bypass`, so the scripts run without changing system settings.
- **Recycle Bin deletes** use `Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(..., SendToRecycleBin)`.
- **CSV files** are written as UTF-8 with BOM so Excel and `Import-Csv` both read non-English names correctly.
- **Path handling:** in Python, `os.path.basename` does not split Windows paths on Linux or macOS. `analysis/common.py` has `win_basename()` for that.
