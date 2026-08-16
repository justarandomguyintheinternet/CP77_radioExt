@echo off
setlocal EnableExtensions EnableDelayedExpansion

title RadioExt Packaging

set "TEMP_DIR=_temp"
set "ARCHIVE=RadioExt.zip"

echo.
echo ========================================
echo   RadioExt Packaging
echo ========================================
echo.

:: ============================================================
:: STEP 1 - Clean temp directory
:: ============================================================

echo [1/5] Cleaning temp directory...

if exist "%TEMP_DIR%" (
    rmdir /S /Q "%TEMP_DIR%"
)

mkdir "%TEMP_DIR%\red4ext\plugins\RadioExt"
mkdir "%TEMP_DIR%\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt\modules"
mkdir "%TEMP_DIR%\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt\radios"

if errorlevel 1 (
    echo.
    echo ERROR: Failed to create temporary directory structure.
    goto :error
)

echo       OK
echo.


:: ============================================================
:: STEP 2 - Copy Red4Ext files
:: ============================================================

echo [2/5] Copying Red4Ext files...

if not exist "red4ext\RadioExt.dll" (
    echo ERROR: red4ext\RadioExt.dll does not exist.
    goto :error
)

if not exist "red4ext\fmod.dll" (
    echo ERROR: red4ext\fmod.dll does not exist.
    goto :error
)

copy /Y "red4ext\RadioExt.dll" "%TEMP_DIR%\red4ext\plugins\RadioExt\radioext.dll"

if errorlevel 1 (
    echo ERROR: Failed to copy RadioExt.dll.
    goto :error
)

copy /Y "red4ext\fmod.dll" "%TEMP_DIR%\red4ext\plugins\RadioExt\fmod.dll"

if errorlevel 1 (
    echo ERROR: Failed to copy fmod.dll.
    goto :error
)

echo       OK
echo.


:: ============================================================
:: STEP 3 - Copy CET files
:: ============================================================

echo [3/5] Copying CET files...

if not exist "init.lua" (
    echo ERROR: init.lua does not exist.
    goto :error
)

if not exist "metadata.json" (
    echo ERROR: metadata.json does not exist.
    goto :error
)

if not exist "modules" (
    echo ERROR: modules directory does not exist.
    goto :error
)

if not exist "radios" (
    echo ERROR: radios directory does not exist.
    goto :error
)

copy /Y "init.lua" "%TEMP_DIR%\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt\init.lua"

if errorlevel 1 (
    echo ERROR: Failed to copy init.lua.
    goto :error
)

copy /Y "metadata.json" "%TEMP_DIR%\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt\metadata.json"

if errorlevel 1 (
    echo ERROR: Failed to copy metadata.json.
    goto :error
)

robocopy "modules" "%TEMP_DIR%\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt\modules" /E /NFL /NDL /NJH /NJS

if errorlevel 8 (
    echo ERROR: Failed to copy modules.
    goto :error
)

robocopy "radios" "%TEMP_DIR%\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt\radios" /E /NFL /NDL /NJH /NJS

if errorlevel 8 (
    echo ERROR: Failed to copy radios.
    goto :error
)

echo       OK
echo.


:: ============================================================
:: STEP 4 - Determine version
:: ============================================================

echo [4/5] Determining archive name...

set "VERSION="

if exist "src\main.cpp" (
    for /f "delims=" %%V in ('powershell -NoProfile -Command "$x=Get-Content 'src\main.cpp' -Raw; if($x -match 'RadioExtVersion[^0-9]*([0-9]+\.[0-9]+\.[0-9]+)'){Write-Output $matches[1]}"') do (
        set "VERSION=%%V"
    )
)

if defined VERSION (
    set "ARCHIVE=RadioExt_!VERSION!.zip"
    echo       Version found: !VERSION!
) else (
    echo       No version found.
    echo       Using: RadioExt.zip
)

echo       Archive: !ARCHIVE!
echo.


:: ============================================================
:: STEP 5 - Create ZIP
:: ============================================================

echo [5/5] Creating ZIP...

if exist "!ARCHIVE!" (
    echo       Removing existing !ARCHIVE!...
    del /F /Q "!ARCHIVE!"
)

echo       Compressing:
echo         %TEMP_DIR%\bin
echo         %TEMP_DIR%\red4ext
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "Compress-Archive -Path '%TEMP_DIR%\bin','%TEMP_DIR%\red4ext' -DestinationPath '%ARCHIVE%' -Force;"

if errorlevel 1 (
    echo.
    echo ERROR: PowerShell failed to create the ZIP.
    goto :error
)

if not exist "!ARCHIVE!" (
    echo.
    echo ERROR: ZIP command completed but !ARCHIVE! does not exist.
    goto :error
)

echo.
echo       ZIP CREATED SUCCESSFULLY.
echo.


:: ============================================================
:: Verify ZIP contents
:: ============================================================

echo Verifying ZIP contents...

powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.IO.Compression.FileSystem; " ^
    "$z=[IO.Compression.ZipFile]::OpenRead('%ARCHIVE%'); " ^
    "$z.Entries | ForEach-Object { Write-Host ('  ' + $_.FullName) }; " ^
    "$z.Dispose()"

if errorlevel 1 (
    echo.
    echo WARNING: Could not verify ZIP contents.
) else (
    echo.
    echo ZIP verification complete.
)

:: ============================================================
:: Cleanup
:: ============================================================

echo.
echo Cleaning temporary directory...

rmdir /S /Q "%TEMP_DIR%" 2>nul

echo.
echo ========================================
echo   BUILD SUCCESSFUL
echo ========================================
echo.
echo   Created:
echo     !ARCHIVE!
echo.
echo ========================================
echo.

pause
endlocal
exit /b 0


:error

echo.
echo ========================================
echo   PACKAGING FAILED
echo ========================================
echo.
echo Temporary files have been kept in:
echo   %TEMP_DIR%
echo.
echo Check the error above.
echo.
pause

endlocal
exit /b 1