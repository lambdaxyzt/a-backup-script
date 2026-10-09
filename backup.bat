@echo off
setlocal EnableDelayedExpansion

REM --- Version ---------------------------------------------------------------
REM     Bump VERSION whenever this script's behaviour changes, so a log can be
REM     matched to the script that produced it.
set "VERSION=1.1.0"
set "VERSION_DATE=2026-10-10"

REM ==========================================================================
REM  backup.bat
REM
REM  Recursively walks the folder tree (starting from this script's folder)
REM  looking for a backup-parameter marker (backup-parameter[.txt] or backup[.txt],
REM  each also with one or two leading underscores) or a ".gitignore".
REM  As soon as a folder contains one, that folder is treated as a backup unit.
REM  A folder holding "backup-ignore" is skipped entirely, subtree included.
REM  A folder holding "backup-root" (or _backup-root, __backup-root) is not a
REM  unit itself, but every unit below it nests under its name: with _backup-root
REM  in Project-Main and a destination of D:\, units land in D:\Project-Main\...
REM  If a backup-parameter marker is found: SOURCE_PATH and optional DEST_PATH are
REM  read from it. If only .gitignore is found: the folder itself is the source.
REM  "rclone copy" copies the folder into the destination, honoring .gitignore.
REM  A marker may set TYPE=sync (destination made identical to source - DELETES
REM  files missing from source) or TYPE=sync-dry (sync, but only report).
REM  If DEST_PATH is not in the marker, the command-line default is used. The walk
REM  does NOT descend past a folder once a marker is found (so node_modules
REM  and other subtrees are skipped for free).
REM
REM  Usage:
REM      backup.bat <destination>
REM
REM  Examples:
REM      backup.bat D:\Backups\Project-Main
REM      backup.bat remote:project-main         (any rclone destination)
REM ==========================================================================

REM --- Validate argument: must supply a destination path ----------------------
if "%~1"=="" (
    echo Usage: backup.bat ^<destination^>
    echo   e.g. backup.bat D:\Backups\Project-Main
    exit /b 1
)

REM --- Store destination and determine the script's own folder (ROOT) ---------
set "DEST=%~1"
set "ROOT=%~dp0"
if "!ROOT:~-1!"=="\" set "ROOT=!ROOT:~0,-1!"

REM --- Print banner ----------------------------------------------------------
echo backup.bat v%VERSION%  (%VERSION_DATE%)
echo Root       : %ROOT%
echo Destination: %DEST%
echo Searching for backup-parameter markers / .gitignore ...
echo.

REM --- Start recursive scan, then report result ------------------------------
REM counter for how many folders get backed up
set /a COUNT=0
REM begin recursive walk from script's folder
call :scan "%ROOT%" "%DEST%"

echo.
echo Done. Processed !COUNT! folder(s).   [backup.bat v%VERSION%]
exit /b 0

REM --------------------------------------------------------------------------
REM :scan <dir>
REM   If <dir> holds backup-ignore, the whole subtree is skipped (wins over all).
REM   If <dir> holds a backup-parameter marker or .gitignore, back it up and stop.
REM   Otherwise recurse into each immediate subfolder.
REM   The pruning (not descending past a found marker) is what skips
REM   node_modules and other subtrees for free.
REM --------------------------------------------------------------------------
:scan
set "DIR=%~1"
set "PREFIX=%~2"

REM --- backup-ignore present: skip this folder AND its entire subtree --------
REM     Checked before any other marker, so it always wins.
if exist "%DIR%\backup-ignore" (
    echo [IGNORE] "!DIR!"
    echo          reason: backup-ignore found - folder and whole subtree skipped
    goto :eof
)
if exist "%DIR%\backup-ignore.txt" (
    echo [IGNORE] "!DIR!"
    echo          reason: backup-ignore.txt found - folder and whole subtree skipped
    goto :eof
)

REM --- backup-root: everything BELOW this folder nests under its name ---------
REM     Accepts backup-root, _backup-root, __backup-root, with or without .txt.
REM     The folder keeps scanning - backup-root does not make it a backup unit.
REM     Example: with "_backup-root" in Project-Main and a destination of D:\,
REM     units inside it land in D:\Project-Main\<unit> instead of D:\<unit>.
set "CHILDPREFIX=%PREFIX%"
set "ISROOT="
for %%R in ("backup-root" "backup-root.txt" "_backup-root" "_backup-root.txt" "__backup-root" "__backup-root.txt") do (
    if not defined ISROOT if exist "%DIR%\%%~R" if not exist "%DIR%\%%~R\" (
        set "ISROOT=%%~R"
    )
)
if defined ISROOT (
    for %%D in ("%DIR%") do set "CHILDPREFIX=%PREFIX%\%%~nxD"
    echo [ROOT]   "!DIR!"
    echo          reason: !ISROOT! found - everything below it nests under "!CHILDPREFIX!"
)

REM --- If this folder has a backup-parameter marker, use it -------------------
REM     All of these spellings count, with or without the .txt extension:
REM         backup-parameter.txt    backup-parameter
REM         _backup-parameter.txt   _backup-parameter
REM         __backup-parameter.txt  __backup-parameter
REM         backup.txt              backup
REM         _backup.txt             _backup
REM         __backup.txt            __backup
REM     First match wins, in the order listed below.
for %%M in ("backup-parameter.txt" "backup-parameter" "_backup-parameter.txt" "_backup-parameter" "__backup-parameter.txt" "__backup-parameter" "backup.txt" "backup" "_backup.txt" "_backup" "__backup.txt" "__backup") do (
    if exist "%DIR%\%%~M" if not exist "%DIR%\%%~M\" (
        echo [UNIT]   "!DIR!"
        echo          reason: marker "%%~M" found - this folder is a backup unit
        call :backup_one "%DIR%\%%~M" "%DIR%" "!PREFIX!"
        goto :eof
    )
)

REM --- If this folder has .gitignore, treat folder itself as backup unit ------
if exist "%DIR%\.gitignore" (
    echo [UNIT]   "!DIR!"
    echo          reason: .gitignore found - folder itself is the backup source
    call :backup_one "" "%DIR%" "!PREFIX!"
    goto :eof
)

REM --- No marker here: recurse into each immediate subdirectory --------------
REM     Skip node_modules and .git - they never contain markers
echo [PASS]   "!DIR!"
echo          reason: no marker here - not backed up, looking inside subfolders
for /d %%S in ("%DIR%\*") do (
    if /i not "%%~nS"=="node_modules" if /i not "%%~nS"==".git" (
        call :scan "%%~fS" "%CHILDPREFIX%"
    )
)
goto :eof

REM --------------------------------------------------------------------------
REM :backup_one <path-to-marker|empty> <fallback-dir>
REM   If a marker path is given, reads SOURCE_PATH, optional DEST_PATH and
REM   optional TYPE (copy | sync | sync-dry, default copy) from it.
REM   If marker path is empty, uses <fallback-dir> as the source directly.
REM   Then runs rclone copy (or sync) to put the source into the destination.
REM   If DEST_PATH is set in the marker, it is used as the full destination.
REM   Otherwise the default DEST\<folder-name> is used.
REM   Honors the source folder's .gitignore via rclone --exclude-from.
REM --------------------------------------------------------------------------
:backup_one
set "PARAM=%~1"
set "FALLBACK=%~2"
set "DESTBASE=%~3"
if not defined DESTBASE set "DESTBASE=%DEST%"
set "SOURCE="
set "DEST_OVERRIDE="
set "MODE="

if not "%PARAM%"=="" (
    REM --- Parse the marker file for SOURCE_PATH=, DEST_PATH= and TYPE= --------
    for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%PARAM%") do (
        if /i "%%A"=="SOURCE_PATH" set "SOURCE=%%B"
        if /i "%%A"=="DEST_PATH" set "DEST_OVERRIDE=%%B"
        if /i "%%A"=="TYPE" set "MODE=%%B"
    )
) else (
    REM --- No marker file — use the fallback directory as source ---------------
    set "SOURCE=!FALLBACK!"
)

REM --- No SOURCE_PATH in the marker: fall back to the folder it sits in -------
REM     An empty marker file is a valid way to say "back this folder up".
if not defined SOURCE if defined FALLBACK (
    set "SOURCE=!FALLBACK!"
    echo          note: marker has no SOURCE_PATH - backing up the folder it sits in
)

REM --- Validate: skip if still no source, or the path doesn't exist ----------
if not defined SOURCE (
    echo [SKIP]   NOT backed up
    echo          reason: marker "%PARAM%" has no SOURCE_PATH and no folder to fall back to
    goto :eof
)
if not exist "!SOURCE!\" (
    echo [SKIP]   NOT backed up
    echo          reason: SOURCE_PATH points to a folder that does not exist:
    echo                  "!SOURCE!"
    goto :eof
)

REM --- Determine copy mode from TYPE ------------------------------------------
REM     copy     = add/update files only, never delete (default)
REM     sync     = make destination identical to source - DELETES files that
REM                are no longer in the source
REM     sync-dry = sync with --dry-run: report what would change, touch nothing
REM     Anything else is a typo - skip loudly rather than guess.
if not defined MODE set "MODE=copy"
set "RCMD="
set "DRYFLAG="
if /i "!MODE!"=="copy" (
    set "RCMD=copy"
    set "WHYMODE=copy - adds and updates files, never deletes"
)
if /i "!MODE!"=="sync" (
    set "RCMD=sync"
    set "WHYMODE=sync - destination made identical to source, extra files DELETED"
)
if /i "!MODE!"=="sync-dry" (
    set "RCMD=sync"
    set "DRYFLAG=--dry-run"
    set "WHYMODE=sync-dry - dry run of sync, nothing is copied or deleted"
)
if not defined RCMD (
    echo [SKIP]   NOT backed up
    echo          reason: unknown TYPE "!MODE!" in marker - use copy, sync or sync-dry
    goto :eof
)

REM --- Determine destination -------------------------------------------------
REM     If DEST_PATH was set in the marker, use it as the full destination.
REM     Otherwise derive DEST\<folder-name> from the default destination.
if defined DEST_OVERRIDE (
    set "TARGET=!DEST_OVERRIDE!"
    set "WHYDEST=DEST_PATH from the marker"
) else (
    for %%D in ("!SOURCE!") do set "NAME=%%~nxD"
    set "TARGET=!DESTBASE!\!NAME!"
    set "WHYDEST=no DEST_PATH in marker, so !DESTBASE! + folder name"
)

REM --- Build .gitignore filter if the source folder has one ------------------
REM     rclone --exclude-from reads ignore patterns from .gitignore at copy time
set "GITFILTER="
set "GITIGNORE_PATH="
set "WHYFILTER=no .gitignore at the unit root, so only node_modules/ is excluded"
if exist "!SOURCE!\.gitignore" (
    set "GITFILTER=--exclude-from"
    set "GITIGNORE_PATH=!SOURCE!\.gitignore"
    set "WHYFILTER=.gitignore at the unit root is applied, plus node_modules/"
)

REM --- Run the actual backup via rclone --------------------------------------
REM     rclone copy = copy files (no deletes — safe incremental backup)
REM     rclone sync = copy files AND delete destination files not in source
REM     -P          = show progress bar
REM     --exclude "node_modules/"    = never backed up (any depth, not descended into)
REM     !GITFILTER!                   = honor .gitignore if present
REM     Excluded files already in the destination are left alone by sync
REM     (rclone only deletes them with --delete-excluded, which is not used).
set /a COUNT+=1
echo.
echo === Backing up "!SOURCE!"
echo         -^> "!TARGET!"
echo          destination: !WHYDEST!
echo          filters    : !WHYFILTER!
echo          type       : !WHYMODE!
if defined GITFILTER (
    rclone !RCMD! -P !DRYFLAG! "!SOURCE!" "!TARGET!" --exclude "node_modules/" !GITFILTER! "!GITIGNORE_PATH!"
) else (
    rclone !RCMD! -P !DRYFLAG! "!SOURCE!" "!TARGET!" --exclude "node_modules/"
)

goto :eof
