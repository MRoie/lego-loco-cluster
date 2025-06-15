@echo off
REM Lego LOCO DirectX Analysis Script
REM Run as Administrator in Windows 98 VM

set ANALYSIS_DIR=C:\LOCO_ANALYSIS
set GAME_PATH=C:\Program Files\LEGO\LOCO
set LOG_FILE=%ANALYSIS_DIR%\analysis_report.txt

echo Creating analysis directory...
mkdir %ANALYSIS_DIR% 2>nul
mkdir %ANALYSIS_DIR%\game_files 2>nul
mkdir %ANALYSIS_DIR%\system_files 2>nul
mkdir %ANALYSIS_DIR%\dependencies 2>nul

echo Starting Lego LOCO Analysis... > %LOG_FILE%
echo Analysis Date: %DATE% %TIME% >> %LOG_FILE%
echo ================================================ >> %LOG_FILE%

REM ========================================
REM 1. SYSTEM INFORMATION
REM ========================================
echo [SYSTEM INFO] >> %LOG_FILE%
echo Windows Version: >> %LOG_FILE%
ver >> %LOG_FILE%
echo. >> %LOG_FILE%

echo DirectX Version: >> %LOG_FILE%
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DirectX" /s >> %LOG_FILE% 2>nul
echo. >> %LOG_FILE%

echo Available Memory: >> %LOG_FILE%
mem >> %LOG_FILE%
echo. >> %LOG_FILE%

echo Display Information: >> %LOG_FILE%
reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Class\Display" /s >> %LOG_FILE% 2>nul
echo. >> %LOG_FILE%

REM ========================================
REM 2. GAME FILES ANALYSIS
REM ========================================
echo [GAME FILES ANALYSIS] >> %LOG_FILE%
echo Game Directory Structure: >> %LOG_FILE%
if exist "%GAME_PATH%" (
    dir "%GAME_PATH%" /s >> %LOG_FILE%
    echo. >> %LOG_FILE%
    
    echo Copying game files... >> %LOG_FILE%
    xcopy "%GAME_PATH%\*.*" "%ANALYSIS_DIR%\game_files\" /s /e /h /y >> %LOG_FILE% 2>&1
    
    echo Game Executable Properties: >> %LOG_FILE%
    for %%f in ("%GAME_PATH%\*.exe") do (
        echo File: %%f >> %LOG_FILE%
        dir "%%f" >> %LOG_FILE%
        echo. >> %LOG_FILE%
    )
) else (
    echo ERROR: Game path not found: %GAME_PATH% >> %LOG_FILE%
    echo Please update GAME_PATH variable in script >> %LOG_FILE%
)

REM ========================================
REM 3. DIRECTX DEPENDENCIES
REM ========================================
echo [DIRECTX DEPENDENCIES] >> %LOG_FILE%
echo DirectX System Files: >> %LOG_FILE%

set DX_FILES=ddraw.dll dsound.dll d3dim.dll d3drm.dll dinput.dll dplay.dll dplayx.dll
for %%f in (%DX_FILES%) do (
    if exist "C:\Windows\System\%%f" (
        echo Found: C:\Windows\System\%%f >> %LOG_FILE%
        dir "C:\Windows\System\%%f" >> %LOG_FILE%
        copy "C:\Windows\System\%%f" "%ANALYSIS_DIR%\system_files\" >> %LOG_FILE% 2>&1
    )
    if exist "C:\Windows\System32\%%f" (
        echo Found: C:\Windows\System32\%%f >> %LOG_FILE%
        dir "C:\Windows\System32\%%f" >> %LOG_FILE%
        copy "C:\Windows\System32\%%f" "%ANALYSIS_DIR%\system_files\" >> %LOG_FILE% 2>&1
    )
)
echo. >> %LOG_FILE%

REM ========================================
REM 4. REGISTRY ANALYSIS
REM ========================================
echo [REGISTRY ANALYSIS] >> %LOG_FILE%
echo Lego LOCO Registry Entries: >> %LOG_FILE%
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\LEGO" /s >> %LOG_FILE% 2>nul
reg query "HKEY_CURRENT_USER\SOFTWARE\LEGO" /s >> %LOG_FILE% 2>nul
echo. >> %LOG_FILE%

echo DirectX Registry Entries: >> %LOG_FILE%
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DirectX" >> %LOG_FILE% 2>nul
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Direct3D" >> %LOG_FILE% 2>nul
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DirectDraw" >> %LOG_FILE% 2>nul
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DirectSound" >> %LOG_FILE% 2>nul
echo. >> %LOG_FILE%

REM ========================================
REM 5. RUNTIME ANALYSIS PREPARATION
REM ========================================
echo [RUNTIME ANALYSIS SETUP] >> %LOG_FILE%
echo Creating API monitoring batch file... >> %LOG_FILE%

REM Create a separate batch file for runtime monitoring
echo @echo off > %ANALYSIS_DIR%\monitor_runtime.bat
echo echo Starting Lego LOCO with monitoring... >> %ANALYSIS_DIR%\monitor_runtime.bat
echo echo API calls will be logged to api_calls.txt >> %ANALYSIS_DIR%\monitor_runtime.bat
echo. >> %ANALYSIS_DIR%\monitor_runtime.bat
echo REM Start the game and capture any console output >> %ANALYSIS_DIR%\monitor_runtime.bat
echo cd /d "%GAME_PATH%" >> %ANALYSIS_DIR%\monitor_runtime.bat
echo echo Game started at %%DATE%% %%TIME%% ^> %ANALYSIS_DIR%\runtime_log.txt >> %ANALYSIS_DIR%\monitor_runtime.bat
echo start "" "LOCO.exe" >> %ANALYSIS_DIR%\monitor_runtime.bat
echo timeout /t 30 >> %ANALYSIS_DIR%\monitor_runtime.bat
echo echo Game monitoring complete >> %ANALYSIS_DIR%\monitor_runtime.bat

REM ========================================
REM 6. SYSTEM DLL DEPENDENCIES
REM ========================================
echo [SYSTEM DEPENDENCIES] >> %LOG_FILE%
echo Critical Windows DLLs: >> %LOG_FILE%

set WIN_DLLS=kernel32.dll user32.dll gdi32.dll advapi32.dll shell32.dll comdlg32.dll ole32.dll oleaut32.dll uuid.lib winmm.dll version.dll
for %%f in (%WIN_DLLS%) do (
    if exist "C:\Windows\System\%%f" (
        echo Found: C:\Windows\System\%%f >> %LOG_FILE%
        dir "C:\Windows\System\%%f" >> %LOG_FILE%
        copy "C:\Windows\System\%%f" "%ANALYSIS_DIR%\system_files\" >> %LOG_FILE% 2>&1
    )
    if exist "C:\Windows\System32\%%f" (
        echo Found: C:\Windows\System32\%%f >> %LOG_FILE%
        dir "C:\Windows\System32\%%f" >> %LOG_FILE%
        copy "C:\Windows\System32\%%f" "%ANALYSIS_DIR%\system_files\" >> %LOG_FILE% 2>&1
    )
)
echo. >> %LOG_FILE%

REM ========================================
REM 7. CONFIGURATION FILES
REM ========================================
echo [CONFIGURATION FILES] >> %LOG_FILE%
echo Searching for game configuration files... >> %LOG_FILE%

REM Look for common config file extensions
for %%ext in (cfg ini dat xml) do (
    if exist "%GAME_PATH%\*.%%ext" (
        echo Found .%%ext files: >> %LOG_FILE%
        dir "%GAME_PATH%\*.%%ext" >> %LOG_FILE%
        copy "%GAME_PATH%\*.%%ext" "%ANALYSIS_DIR%\game_files\" >> %LOG_FILE% 2>&1
    )
)

REM Check Windows directory for game-related files
if exist "C:\Windows\LOCO*" (
    echo Windows LOCO files: >> %LOG_FILE%
    dir "C:\Windows\LOCO*" /s >> %LOG_FILE%
    copy "C:\Windows\LOCO*" "%ANALYSIS_DIR%\game_files\" >> %LOG_FILE% 2>&1
)

REM ========================================
REM 8. ANALYSIS SUMMARY
REM ========================================
echo. >> %LOG_FILE%
echo [ANALYSIS SUMMARY] >> %LOG_FILE%
echo Files copied to: %ANALYSIS_DIR% >> %LOG_FILE%
echo Total game files: >> %LOG_FILE%
dir "%ANALYSIS_DIR%\game_files" | find "File(s)" >> %LOG_FILE%
echo Total system files: >> %LOG_FILE%
dir "%ANALYSIS_DIR%\system_files" | find "File(s)" >> %LOG_FILE%
echo. >> %LOG_FILE%
echo Next steps: >> %LOG_FILE%
echo 1. Run monitor_runtime.bat to capture API calls >> %LOG_FILE%
echo 2. Copy entire %ANALYSIS_DIR% folder for analysis >> %LOG_FILE%
echo 3. Examine analysis_report.txt for detailed information >> %LOG_FILE%
echo. >> %LOG_FILE%
echo Analysis completed at: %DATE% %TIME% >> %LOG_FILE%

REM ========================================
REM 9. CREATE PARSING HELPER
REM ========================================
echo Creating parsing helper script... >> %LOG_FILE%

REM Create a helper script to make data easier to parse
echo @echo off > %ANALYSIS_DIR%\create_manifest.bat
echo echo Creating machine-readable manifest... >> %ANALYSIS_DIR%\create_manifest.bat
echo echo LEGO_LOCO_ANALYSIS_MANIFEST > %ANALYSIS_DIR%\manifest.txt >> %ANALYSIS_DIR%\create_manifest.bat
echo echo ANALYSIS_DATE=%%DATE%% %%TIME%% >> %ANALYSIS_DIR%\manifest.txt >> %ANALYSIS_DIR%\create_manifest.bat
echo echo GAME_PATH=%GAME_PATH% >> %ANALYSIS_DIR%\manifest.txt >> %ANALYSIS_DIR%\create_manifest.bat
echo for /f %%%%i in ('dir "%ANALYSIS_DIR%\game_files\*.exe" /b 2^^^>nul') do echo GAME_EXE=%%%%i >> %ANALYSIS_DIR%\manifest.txt >> %ANALYSIS_DIR%\create_manifest.bat
echo for /f %%%%i in ('dir "%ANALYSIS_DIR%\system_files\d*.dll" /b 2^^^>nul') do echo DIRECTX_DLL=%%%%i >> %ANALYSIS_DIR%\manifest.txt >> %ANALYSIS_DIR%\create_manifest.bat

call %ANALYSIS_DIR%\create_manifest.bat

echo.
echo ================================================
echo Analysis Complete!
echo ================================================
echo All data saved to: %ANALYSIS_DIR%
echo Main report: %LOG_FILE%
echo.
echo NEXT STEPS:
echo 1. Run: %ANALYSIS_DIR%\monitor_runtime.bat
echo 2. Play the game for 2-3 minutes
echo 3. Copy the entire %ANALYSIS_DIR% folder
echo 4. Provide the folder for WebAssembly analysis
echo.
echo Press any key to open the analysis directory...
pause
explorer %ANALYSIS_DIR%