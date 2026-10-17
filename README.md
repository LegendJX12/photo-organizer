# Photo Organizer

Tools that tidy a big, messy Windows photo folder. They:

- sort photos and videos into **year → event / month** folders
- remove **exact duplicates**, checked twice (SHA256 + size) before anything is deleted
- find **look-alike copies** and **burst shots**: the sharpest shot stays on top, the rest go into a `- similar shots` subfolder
- split trips into **trip → day + place** folders using GPS, like Google Photos places
- merge a **Google Photos Takeout** export, importing only the items you don't already have
- clean up **OneDrive** and **Google Drive** copies, but only after your photos folder has a verified backup

Everything runs on your own PC with Windows PowerShell 5.1 (already built into Windows). No install needed.

> **Safety rules built into every step**
> 1. Every "change" step has a **read-only check step** before it.
> 2. Nothing is ever deleted outright. Deleted files go to the **Recycle Bin** (or Google Drive Trash).
> 3. A file is only deleted when an **exact copy** exists elsewhere, or you chose it in a review.
> 4. Every move is logged with an **undo** file and an undo launcher.

---

## Folder result

```
photos\
├─ _Organized\
│  ├─ 2009-2010 Childhood\             (merged years, flat)
│  ├─ 2023\
│  │  ├─ 2023-05\                      (loose photos by month)
│  │  ├─ 2023-06-02 Graduation\        (named event)
│  │  └─ 2023-09-21 Germany Trip\
│  │     ├─ 09-21 Munich\
│  │     └─ 09-27 Prague\
│  │        ├─ IMG_1234.jpg            (sharpest shot)
│  │        └─ IMG_1234 - similar shots\
│  └─ ...
├─ _Needs review\                      (no date found: you decide)
└─ _organize_tool\                     (this repo's tool\ folder)
```

---

## How to use it (step by step)

### 1. Put the tool next to your photos
1. Download this repo: green **Code** button → **Download ZIP** → unzip it.
2. Copy the **`tool`** folder into your photos folder and rename it **`_organize_tool`**.
   Example: `C:\Users\You\Pictures\photos\_organize_tool\`
3. Every step is a `.bat` file inside it. **Double-click** to run, wait for "Done", then close the window.

### 2. Run the steps in order
Each row is one double-click. "Review" means: open the file it made and check it before you go on.

| Step | Double-click | What it does | Changes files? |
|---|---|---|---|
| **Organize** | `0_EXTRACT_ZIPS` | Unzip all zips | adds files |
| | `1_MAKE_PLAN` | Work out a date + folder for every file. Review `summary.txt` and `plan.csv` | no |
| | `2_APPLY_PLAN` | Move files as planned | moves (undo: `3_UNDO`) |
| **Duplicates** | `4_VERIFY_DUPLICATES` | Re-check every duplicate with SHA256 | no |
| | `5_DELETE_DUPLICATES_AND_RESCAN` | Verified duplicates → Recycle Bin, then look for look-alikes. Review `lookalikes.html` | recycles |
| | `6_LOOKALIKE_CLEANUP` | Recycle the copies you chose in `lookalike_actions.csv` | recycles |
| **Trips & stacks** | `8_SCAN_FOLDER` | Read date, GPS and a picture fingerprint | no |
| | *(analysis)* `make_geo_cells.py` | Group GPS points into ~10 km areas | no |
| | `9_LOOKUP_PLACES` | Look up place names (OpenStreetMap, ~1 per second) | no |
| | *(analysis)* `plan_trips.py` and `find_stacks.py` | Plan trip folders and stacks. Review the CSVs | no |
| | `10_TRIPS_AND_STACKS` | Move trips + stack similar shots. Review `similar_shots.html` | moves (undo: `11_UNDO_TRIPS`) |
| | `12_STACK_EDITS` | Apply your stack review (`stack_edits.csv`) | moves / recycles |
| **Google Photos** | `14_TAKEOUT_UNZIP` | Check + unzip Takeout zips from Downloads | adds files |
| | `15_SCAN_GOOGLE` | Scan the Takeout photos | no |
| | *(analysis)* `match_takeout.py` | List items you don't have yet. Review `google_import.csv` | no |
| | `16_GOOGLE_IMPORT` | Copy them into your folders | copies (undo: `17_UNDO_GOOGLE_IMPORT`) |
| | `18_STACK_NEW_PHOTOS` | Stack similar shots among the new photos | moves |
| **Extras** | `20_MERGE_YEARS` | Merge year folders into one (set them in `merge_years.csv`) | moves |
| **OneDrive** | `21_ONEDRIVE_CHECK` | If OneDrive brings old copies back: check each against `_Organized` | no |
| | `22_ONEDRIVE_APPLY` | Recycle the confirmed copies (`onedrive_actions.csv`) | recycles |
| **Google Drive** | `23_GDRIVE_COMPARE` | Which Drive photos/videos are not in your folder | no |
| | `24_GDRIVE_IMPORT` | Copy the chosen ones in (`gdrive_import.csv`) | copies |
| | `25_GDRIVE_CLEANUP` | Delete from Drive only files with a same-size copy in `_Organized` | Drive → Trash |
| | `26_DRIVE_OWNED_CHECK` / `27_DRIVE_OWNED_APPLY` | Same, for files you own in shared folders | Drive → Trash |

### 3. Run the analysis steps (Python)
The *(analysis)* rows need Python 3 (free from python.org; tick **"Add to PATH"** when installing). Open **Command Prompt** in the `_organize_tool` folder (type `cmd` in the File Explorer address bar), then run, for example:

```
set A=C:\Users\You\Downloads\photo-organizer\analysis
python %A%\make_geo_cells.py folder_scan.csv geo_cells.csv
python %A%\plan_trips.py folder_scan.csv geo_names.csv trip_moves.csv --home "Singapore" --home "Malaysia/Selangor"
python %A%\find_stacks.py folder_scan.csv stacks.csv
python %A%\match_takeout.py takeout_files.csv takeout_meta.csv folder_scan.csv google_import.csv
```

In the first line, change the path to wherever you unzipped the repo. Each script explains itself with `--help`.

---

## Repo layout

| Folder | What's inside |
|---|---|
| `tool/` | PowerShell scripts + double-click `.bat` launchers. Copy this into your photos folder as `_organize_tool` |
| `analysis/` | Python planning scripts (standard library only). They only read CSVs and write CSVs, never touch photos |
| `docs/WORKFLOW.md` | Detailed rules, file formats, and lessons learned (OneDrive, Google Drive) |
| `examples/` | Example config files |

## Privacy
The tools write file lists, logs and previews (`.csv`, `.txt`, `.html`) next to the scripts. They contain your file names and GPS places, so `.gitignore` keeps them out of git. Only `geocode.ps1` goes online: it sends rounded coordinates (about 10 km) to OpenStreetMap, nothing else.
