# backup-script

A Windows batch script that finds the project folders you've marked for backup and copies each one to a backup location with [rclone](https://rclone.org/).

- Mark a folder for backup by dropping an empty `_backup` file in it.
- Folders that already have a `.gitignore` are backed up automatically, and the `.gitignore` decides which files to leave out.
- `node_modules/` is never backed up. The `.git` folder is, so the backup keeps full git history.
- Copies by default and never deletes anything from the backup. Add `TYPE=sync` to a folder's `_backup` file to make that folder's backup an exact copy of the source instead.

## Requirements

- Windows (`cmd.exe`)
- [rclone](https://rclone.org/downloads/) on your `PATH`

## Usage

Put `backup.bat` at the top of the folder tree you want to back up, then run:

```bat
backup.bat <destination>
```

Examples:

```bat
backup.bat D:\Backups
backup.bat remote:project-main
```

The destination can be a local folder or any configured rclone remote. Each backed-up folder lands in `<destination>\<folder-name>`.

## Marker files

| File | Effect |
| --- | --- |
| `_backup` | Back up this folder. Optional settings: `SOURCE_PATH`, `DEST_PATH`, `TYPE`. |
| `.gitignore` | Back up this folder, leaving out the files it lists. |
| `backup-ignore` | Skip this folder and everything inside it. |
| `_backup-root` | Put every backup from inside this folder under a subfolder with its name. |

Example `_backup` with every setting filled in. An empty file also works.

```ini
SOURCE_PATH=C:\Users\me\projects\my-app
DEST_PATH=D:\Backups\custom-dest
TYPE=sync-dry
```

`TYPE` can be:

- `copy`: the default. Adds and updates files, never deletes.
- `sync`: makes the backup an exact copy of the source, deleting files that are gone from the source.
- `sync-dry`: prints what `sync` would do without changing anything.

See [backup-explanation.md](backup-explanation.md) for how each marker and setting works, how to read the log, and how to write ignore rules.

## Contributing

`backup.bat` must keep **CRLF** line endings, or `cmd.exe` fails with errors that make no sense. [.gitattributes](.gitattributes) makes git check the file out with CRLF. Editors and tools like `sed -i` can still save it with LF, so check before committing.

Bump `VERSION` at the top of `backup.bat` whenever its behaviour changes.
