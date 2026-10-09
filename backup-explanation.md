# backup.bat

**Version:** v1.1.0 (2026-10-10). The version is printed at the start and end of every run, so a log always shows which script made it. Bump `VERSION` in `backup.bat` whenever its behaviour changes.

## Quick start

1. Put an empty file named `_backup` in every folder you want backed up.
2. Run:

   ```bat
   backup.bat D:\Backups
   ```

3. Each marked folder is copied to `D:\Backups\<folder-name>`.

The script searches every folder below its own location. Folders without a marker are not backed up; the script just looks inside them.

## Marker files

Put one of these files in a folder to tell the script what to do with it. File contents don't matter unless stated.

| File | What it does |
| --- | --- |
| `backup-ignore` | Skip this folder and everything inside it. Beats every other marker. |
| `_backup` | Back up this folder. Can hold settings (see below). |
| `.gitignore` | Back up this folder (if it has no `_backup`). |
| `_backup-root` | Don't back up this folder itself, but put everything found inside it under a subfolder with its name. |

Checked in this order: `backup-ignore` → `_backup-root` → `_backup` → `.gitignore`.

Once a folder is backed up, the script doesn't look further inside it for more markers.

### Accepted spellings

- **`_backup`**: also `backup`, `__backup`, `backup-parameter`, `_backup-parameter`, `__backup-parameter`, each with or without `.txt`. If several exist, the first in this order wins: `backup-parameter.txt`, `backup-parameter`, `_backup-parameter.txt`, … `__backup`.
- **`_backup-root`**: also `backup-root`, `__backup-root`, each with or without `.txt`.
- **`backup-ignore`**: also `backup-ignore.txt`.

Markers must be **files**. A folder with a marker's name doesn't count.

## Settings inside `_backup`

An empty `_backup` is fine. To change behaviour, add any of these lines:

```ini
# Lines starting with # are ignored
SOURCE_PATH=C:\Users\me\projects\my-app
DEST_PATH=D:\Backups\custom-dest
TYPE=sync
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `SOURCE_PATH` | The folder holding `_backup` | Back up a different folder instead. If it doesn't exist, the unit is skipped (`[SKIP]`). |
| `DEST_PATH` | `<destination>\<folder-name>` | Exact place to copy to. Ignores `_backup-root` nesting. |
| `TYPE` | `copy` | How to copy. See below. |

### TYPE: copy or sync

| Value | Adds/updates files | Deletes files in destination that are gone from source |
| --- | --- | --- |
| `copy` (default) | Yes | **No.** Safe: the backup only grows. |
| `sync` | Yes | **Yes.** The destination becomes an exact copy of the source. |
| `sync-dry` | No | No. Only prints what `sync` *would* do. |

Values are case-insensitive. Any other value is a typo: the folder is skipped with `[SKIP]` and nothing is copied.

> [!WARNING]
> `sync` deletes files. Run `TYPE=sync-dry` first and read the output. Double-check `DEST_PATH`: syncing into the wrong folder deletes its contents.

Files excluded by filters (`node_modules/`, `.gitignore` entries) are never deleted from the destination, even with `sync`.

## Nesting with `_backup-root`

Example: `Project-Main` contains `_backup-root`, and you run `backup.bat D:\`.

| Without `_backup-root` | With `_backup-root` |
| --- | --- |
| `D:\appA` | `D:\Project-Main\appA` |

Roots stack: with another `backup-root` in `Project-Main\group`, a unit at `Project-Main\group\appB` goes to `D:\Project-Main\group\appB`.

A folder can be a root and a unit at the same time (if it also has `_backup` or `.gitignore`).

## What gets excluded

- `node_modules/` is always excluded. It's the only rule in the script.
- Everything else goes in the unit's `.gitignore`.
- `.git` **is** backed up on purpose, so the copy is a working repo with full history.

### Only the top-level .gitignore is used

> [!WARNING]
> Only the `.gitignore` at the **top of the backed-up folder** is read. `.gitignore` files in subfolders are ignored.

Example: if `kiawosch` is the unit, an entry in `kiawosch\livekit\.gitignore` does nothing. Put it in `kiawosch\.gitignore`.

A folder with `_backup` can also have a `.gitignore`; it's used only as a filter.

### Write entries in rclone style

| Entry | Works? | Why |
| --- | --- | --- |
| `.next/` | ✅ | Trailing `/` matches the folder at any depth |
| `build/` | ✅ | |
| `*.log` | ✅ | |
| `dist` | ❌ | Without a trailing `/`, it only matches a *file* named `dist`, not the folder |
| `!keep.txt` | ❌ | rclone has no `!` negation here |
| `**/.next/**` | ❌ | Misses `.next` at the top level |

**Rule:** folders get a trailing `/` and no leading `**/`.

### `.gitignore` or `backup-ignore`?

- `.gitignore`: back up this folder, minus some files.
- `backup-ignore`: don't back up this folder at all.

## Reading the log

Each folder gets one line:

| Tag | Meaning |
| --- | --- |
| `[UNIT]` | Backed up. Says which marker caused it. |
| `[PASS]` | No marker; looking inside. |
| `[IGNORE]` | `backup-ignore` found; folder and contents skipped. |
| `[ROOT]` | `_backup-root` found; shows the new destination prefix. |
| `[SKIP]` | Marker is broken: missing `SOURCE_PATH` folder or unknown `TYPE`. Nothing copied. |

After `[UNIT]`, four detail lines show the **source → destination**, where the **destination** came from, which **filters** apply, and the **type** (copy, sync or sync-dry).

`Done. Processed N folder(s)` counts units that ran (including `sync-dry`), not folders scanned.

`node_modules` and `.git` folders are skipped silently during the search, to keep the log short.

## Editing backup.bat

> [!IMPORTANT]
> Keep **CRLF** line endings. With LF endings, `cmd.exe` fails with nonsense errors like `'ackup.bat' is not recognized`. `sed -i` in Git Bash silently converts to LF, so convert back afterwards.
