@echo off
REM Windows 98 SE Complete Kiosk System Configuration
REM Combines auto-launch and remote broadcasting capabilities
REM Uses external configuration file for easy customization

echo Windows 98 SE Complete Kiosk System Setup
echo ==========================================
echo.

REM === LOAD CONFIGURATION ===
if not exist "kiosk_config.ini" (
    echo ERROR: Configuration file 'kiosk_config.ini' not found!
    echo Creating default configuration file...
    call :create_default_config
    echo.
    echo Please edit 'kiosk_config.ini' with your settings and run this script again.
    pause
    exit /b 1
)

echo Loading configuration from kiosk_config.ini...
call :load_config

echo Configuration loaded:
echo - Application: %APP_PATH%
echo - Remote Host: %REMOTE_HOST%
echo - VNC Port: %VNC_PORT%
echo - HTTP Port: %HTTP_PORT%
echo.

REM === CREATE SYSTEM DIRECTORIES ===
echo [1/12] Creating system directories...
if not exist "C:\KIOSK" mkdir "C:\KIOSK"
if not exist "C:\KIOSK\VNC" mkdir "C:\KIOSK\VNC"
if not exist "C:\KIOSK\LOGS" mkdir "C:\KIOSK\LOGS"
if not exist "C:\KIOSK\SCRIPTS" mkdir "C:\KIOSK\SCRIPTS"
if not exist "C:\KIOSK\BACKUP" mkdir "C:\KIOSK\BACKUP"

REM === BACKUP SYSTEM FILES ===
echo [2/12] Backing up system files...
copy C:\WINDOWS\SYSTEM.INI C:\KIOSK\BACKUP\SYSTEM.INI.backup >nul 2>&1
if exist "C:\WINDOWS\WIN.INI" copy C:\WINDOWS\WIN.INI C:\KIOSK\BACKUP\WIN.INI.backup >nul 2>&1

REM === DISABLE LOGIN AND CONFIGURE AUTO-LOGIN ===
echo [3/12] Configuring automatic login...
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d %USERNAME% /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "" /f >nul

REM === CONFIGURE VNC SERVER SETTINGS ===
echo [4/12] Configuring VNC server...
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3" /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /f >nul

REM VNC Server registry settings
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /v "PortNumber" /t REG_DWORD /d %VNC_PORT% /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /v "HTTPPortNumber" /t REG_DWORD /d %HTTP_PORT% /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /v "EnableHTTPServer" /t REG_DWORD /d 1 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /v "AutoPortSelect" /t REG_DWORD /d 0 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /v "AllowLoopback" /t REG_DWORD /d 0 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /v "LoopbackOnly" /t REG_DWORD /d 0 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /v "EnableJPEGCompression" /t REG_DWORD /d 1 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3\Default" /v "QualityLevel" /t REG_DWORD /d %VNC_QUALITY% /f >nul

REM === DISABLE UI DISTRACTIONS ===
echo [5/12] Disabling UI distractions...

REM Disable taskbar
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoTaskbar /t REG_DWORD /d %DISABLE_TASKBAR% /f >nul

REM Disable desktop icons
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDesktop /t REG_DWORD /d %DISABLE_DESKTOP% /f >nul

REM Disable system tray
if "%DISABLE_SYSTRAY%"=="1" (
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v SystemTray /t REG_SZ /d "" /f >nul
    reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v SystemTray /t REG_SZ /d "" /f >nul
)

REM Disable startup sound
reg add "HKEY_CURRENT_USER\Control Panel\Sounds" /v "WindowsLogon" /t REG_SZ /d "" /f >nul

REM Disable screen saver
reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d 0 /f >nul

REM Set wallpaper
reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "" /f >nul

REM === NETWORK CONFIGURATION ===
echo [6/12] Configuring network settings...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa" /v "RestrictAnonymous" /t REG_DWORD /d 0 /f >nul
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa" /v "EveryoneIncludesAnonymous" /t REG_DWORD /d 1 /f >nul

REM === CREATE VNC STARTUP SCRIPT ===
echo [7/12] Creating VNC startup script...
echo @echo off > C:\KIOSK\SCRIPTS\START_VNC.BAT
echo REM VNC Server Startup Script >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo echo Starting VNC Server on port %VNC_PORT%... >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo. >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo REM Kill existing VNC processes >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo taskkill /f /im winvnc.exe 2^>nul ^>^> C:\KIOSK\LOGS\vnc.log >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo ping localhost -n 2 ^>nul >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo. >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo REM Start VNC Server >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo if exist "C:\KIOSK\VNC\winvnc.exe" ( >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo     echo %%date%% %%time%% - Starting VNC Server ^>^> C:\KIOSK\LOGS\vnc.log >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo     start "" "C:\KIOSK\VNC\winvnc.exe" -service >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo     ping localhost -n 3 ^>nul >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo     netstat -an ^| find ":%VNC_PORT%" ^>nul >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo     if errorlevel 1 ( >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo         echo %%date%% %%time%% - VNC Server startup failed ^>^> C:\KIOSK\LOGS\vnc.log >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo     ^) else ( >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo         echo %%date%% %%time%% - VNC Server running on port %VNC_PORT% ^>^> C:\KIOSK\LOGS\vnc.log >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo     ^) >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo ^) else ( >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo     echo %%date%% %%time%% - VNC Server not found at C:\KIOSK\VNC\winvnc.exe ^>^> C:\KIOSK\LOGS\vnc.log >> C:\KIOSK\SCRIPTS\START_VNC.BAT
echo ^) >> C:\KIOSK\SCRIPTS\START_VNC.BAT

REM === CREATE APPLICATION MONITOR SCRIPT ===
echo [8/12] Creating application monitor script...
echo @echo off > C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo REM Application Monitor and Auto-Restart >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo set APP_EXE=%APP_NAME% >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo set APP_PATH=%APP_PATH% >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo. >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo :monitor_loop >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo ping localhost -n %APP_MONITOR_INTERVAL% ^>nul >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo. >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo REM Check if application is running >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo tasklist /fi "imagename eq %%APP_EXE%%" 2^>nul ^| find /i "%%APP_EXE%%" ^>nul >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo if errorlevel 1 ( >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo     echo %%date%% %%time%% - Application not running, restarting... ^>^> C:\KIOSK\LOGS\app.log >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo     if exist "%%APP_PATH%%" ( >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo         start "" "%%APP_PATH%%" >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo     ^) else ( >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo         echo %%date%% %%time%% - Application not found at %%APP_PATH%% ^>^> C:\KIOSK\LOGS\app.log >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo     ^) >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo ^) >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT
echo goto monitor_loop >> C:\KIOSK\SCRIPTS\MONITOR_APP.BAT

REM === CREATE NETWORK MONITOR SCRIPT ===
echo [9/12] Creating network monitor script...
echo @echo off > C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo REM Network Connection Monitor >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo :network_loop >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo ping %REMOTE_HOST% -n 1 -w 2000 ^>nul >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo if errorlevel 1 ( >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo     echo %%date%% %%time%% - Connection LOST to %REMOTE_HOST% ^>^> C:\KIOSK\LOGS\network.log >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo ^) else ( >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo     echo %%date%% %%time%% - Connection OK to %REMOTE_HOST% ^>^> C:\KIOSK\LOGS\network.log >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo ^) >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo ping localhost -n %NETWORK_CHECK_INTERVAL% ^>nul >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT
echo goto network_loop >> C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT

REM === CREATE MASTER STARTUP SCRIPT ===
echo [10/12] Creating master startup script...
echo @echo off > C:\KIOSK\MASTER_STARTUP.BAT
echo REM Master Kiosk Startup Script >> C:\KIOSK\MASTER_STARTUP.BAT
echo echo Starting Complete Kiosk System... >> C:\KIOSK\MASTER_STARTUP.BAT
echo echo %%date%% %%time%% - System startup initiated ^> C:\KIOSK\LOGS\system.log >> C:\KIOSK\MASTER_STARTUP.BAT
echo. >> C:\KIOSK\MASTER_STARTUP.BAT
echo REM Wait for system to stabilize >> C:\KIOSK\MASTER_STARTUP.BAT
echo ping localhost -n %STARTUP_DELAY% ^>nul >> C:\KIOSK\MASTER_STARTUP.BAT
echo. >> C:\KIOSK\MASTER_STARTUP.BAT
echo REM Start VNC Server first >> C:\KIOSK\MASTER_STARTUP.BAT
echo call C:\KIOSK\SCRIPTS\START_VNC.BAT >> C:\KIOSK\MASTER_STARTUP.BAT
echo. >> C:\KIOSK\MASTER_STARTUP.BAT
echo REM Start monitoring services >> C:\KIOSK\MASTER_STARTUP.BAT
echo start "" C:\KIOSK\SCRIPTS\MONITOR_NETWORK.BAT >> C:\KIOSK\MASTER_STARTUP.BAT
echo. >> C:\KIOSK\MASTER_STARTUP.BAT
echo REM Start application if specified >> C:\KIOSK\MASTER_STARTUP.BAT
echo if "%ENABLE_APP_LAUNCH%"=="1" ( >> C:\KIOSK\MASTER_STARTUP.BAT
echo     echo %%date%% %%time%% - Starting target application ^>^> C:\KIOSK\LOGS\system.log >> C:\KIOSK\MASTER_STARTUP.BAT
echo     if exist "%APP_PATH%" ( >> C:\KIOSK\MASTER_STARTUP.BAT
echo         ping localhost -n 2 ^>nul >> C:\KIOSK\MASTER_STARTUP.BAT
echo         start "" "%APP_PATH%" >> C:\KIOSK\MASTER_STARTUP.BAT
echo         REM Start application monitor >> C:\KIOSK\MASTER_STARTUP.BAT
echo         if "%ENABLE_APP_MONITOR%"=="1" ( >> C:\KIOSK\MASTER_STARTUP.BAT
echo             start "" C:\KIOSK\SCRIPTS\MONITOR_APP.BAT >> C:\KIOSK\MASTER_STARTUP.BAT
echo         ^) >> C:\KIOSK\MASTER_STARTUP.BAT
echo     ^) else ( >> C:\KIOSK\MASTER_STARTUP.BAT
echo         echo %%date%% %%time%% - Application not found: %APP_PATH% ^>^> C:\KIOSK\LOGS\system.log >> C:\KIOSK\MASTER_STARTUP.BAT
echo     ^) >> C:\KIOSK\MASTER_STARTUP.BAT
echo ^) >> C:\KIOSK\MASTER_STARTUP.BAT
echo. >> C:\KIOSK\MASTER_STARTUP.BAT
echo REM Create status file >> C:\KIOSK\MASTER_STARTUP.BAT
echo echo Kiosk System Status - %%date%% %%time%% ^> C:\KIOSK\status.txt >> C:\KIOSK\MASTER_STARTUP.BAT
echo echo VNC Port: %VNC_PORT% ^>^> C:\KIOSK\status.txt >> C:\KIOSK\MASTER_STARTUP.BAT
echo echo HTTP Port: %HTTP_PORT% ^>^> C:\KIOSK\status.txt >> C:\KIOSK\MASTER_STARTUP.BAT
echo echo Remote Host: %REMOTE_HOST% ^>^> C:\KIOSK\status.txt >> C:\KIOSK\MASTER_STARTUP.BAT
echo echo Application: %APP_PATH% ^>^> C:\KIOSK\status.txt >> C:\KIOSK\MASTER_STARTUP.BAT
echo. >> C:\KIOSK\MASTER_STARTUP.BAT
echo echo %%date%% %%time%% - Kiosk system fully operational ^>^> C:\KIOSK\LOGS\system.log >> C:\KIOSK\MASTER_STARTUP.BAT

REM === MODIFY SYSTEM.INI FOR SHELL REPLACEMENT ===
echo [11/12] Modifying system startup configuration...
if "%REPLACE_SHELL%"=="1" (
    echo Configuring shell replacement...
    echo [boot] > C:\TEMP_SYS.INI
    echo shell=C:\KIOSK\MASTER_STARTUP.BAT >> C:\TEMP_SYS.INI
    echo drivers=mmsystem.dll >> C:\TEMP_SYS.INI
    
    REM Append the rest of the original SYSTEM.INI excluding [boot] section
    for /f "skip=1 tokens=*" %%a in (C:\WINDOWS\SYSTEM.INI) do (
        echo %%a >> C:\TEMP_SYS.INI
    )
    
    copy C:\TEMP_SYS.INI C:\WINDOWS\SYSTEM.INI >nul
    del C:\TEMP_SYS.INI >nul
)

REM === INTEGRATE WITH STARTUP ===
echo [12/12] Finalizing system integration...

REM Add to startup folder
copy "C:\KIOSK\MASTER_STARTUP.BAT" "C:\WINDOWS\Start Menu\Programs\StartUp\KioskSystem.bat" >nul

REM Add to registry startup
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "KioskSystem" /t REG_SZ /d "C:\KIOSK\MASTER_STARTUP.BAT" /f >nul

REM === CREATE MANAGEMENT UTILITIES ===
echo Creating management utilities...

REM Restore script
echo @echo off > C:\KIOSK\RESTORE_SYSTEM.BAT
echo REM Restore original system configuration >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo echo Restoring original system configuration... >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo if exist "C:\KIOSK\BACKUP\SYSTEM.INI.backup" ( >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo     copy "C:\KIOSK\BACKUP\SYSTEM.INI.backup" "C:\WINDOWS\SYSTEM.INI" ^>nul >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo     echo SYSTEM.INI restored >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo ^) >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "KioskSystem" /f ^>nul 2^>^&1 >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo del "C:\WINDOWS\Start Menu\Programs\StartUp\KioskSystem.bat" ^>nul 2^>^&1 >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo echo System restoration complete. Reboot required. >> C:\KIOSK\RESTORE_SYSTEM.BAT
echo pause >> C:\KIOSK\RESTORE_SYSTEM.BAT

REM Status checker
echo @echo off > C:\KIOSK\CHECK_STATUS.BAT
echo REM System Status Checker >> C:\KIOSK\CHECK_STATUS.BAT
echo echo Kiosk System Status >> C:\KIOSK\CHECK_STATUS.BAT
echo echo =================== >> C:\KIOSK\CHECK_STATUS.BAT
echo netstat -an ^| find ":%VNC_PORT%" ^>nul >> C:\KIOSK\CHECK_STATUS.BAT
echo if errorlevel 1 ( >> C:\KIOSK\CHECK_STATUS.BAT
echo     echo VNC Server: NOT RUNNING >> C:\KIOSK\CHECK_STATUS.BAT
echo ^) else ( >> C:\KIOSK\CHECK_STATUS.BAT
echo     echo VNC Server: RUNNING on port %VNC_PORT% >> C:\KIOSK\CHECK_STATUS.BAT
echo ^) >> C:\KIOSK\CHECK_STATUS.BAT
echo ping %REMOTE_HOST% -n 1 -w 1000 ^>nul >> C:\KIOSK\CHECK_STATUS.BAT
echo if errorlevel 1 ( >> C:\KIOSK\CHECK_STATUS.BAT
echo     echo Network: DISCONNECTED from %REMOTE_HOST% >> C:\KIOSK\CHECK_STATUS.BAT
echo ^) else ( >> C:\KIOSK\CHECK_STATUS.BAT
echo     echo Network: CONNECTED to %REMOTE_HOST% >> C:\KIOSK\CHECK_STATUS.BAT
echo ^) >> C:\KIOSK\CHECK_STATUS.BAT
echo tasklist /fi "imagename eq %APP_NAME%" 2^>nul ^| find /i "%APP_NAME%" ^>nul >> C:\KIOSK\CHECK_STATUS.BAT
echo if errorlevel 1 ( >> C:\KIOSK\CHECK_STATUS.BAT
echo     echo Application: NOT RUNNING >> C:\KIOSK\CHECK_STATUS.BAT
echo ^) else ( >> C:\KIOSK\CHECK_STATUS.BAT
echo     echo Application: RUNNING >> C:\KIOSK\CHECK_STATUS.BAT
echo ^) >> C:\KIOSK\CHECK_STATUS.BAT
echo pause >> C:\KIOSK\CHECK_STATUS.BAT

REM === FINAL INSTRUCTIONS ===
echo.
echo ================================================================
echo COMPLETE KIOSK SYSTEM SETUP FINISHED!
echo ================================================================
echo.
echo CONFIGURATION SUMMARY:
echo - System Directory: C:\KIOSK\
echo - Application: %APP_PATH%
echo - VNC Port: %VNC_PORT%
echo - HTTP Port: %HTTP_PORT%
echo - Remote Host: %REMOTE_HOST%
echo.
echo REQUIRED MANUAL STEPS:
echo 1. Download VNC Server (RealVNC 3.3.7 or TightVNC 1.3.10)
echo 2. Copy winvnc.exe to C:\KIOSK\VNC\
echo 3. Configure firewall to allow ports %VNC_PORT% and %HTTP_PORT%
echo 4. Verify application path: %APP_PATH%
echo 5. REBOOT THE SYSTEM
echo.
echo MANAGEMENT UTILITIES:
echo - Check Status: C:\KIOSK\CHECK_STATUS.BAT
echo - Restore System: C:\KIOSK\RESTORE_SYSTEM.BAT
echo - View Logs: C:\KIOSK\LOGS\
echo.
echo REMOTE ACCESS:
echo - VNC Client: Connect to [KIOSK_IP]:%VNC_PORT%
echo - Web Browser: http://[KIOSK_IP]:%HTTP_PORT%
echo.
echo The system will automatically start in kiosk mode after reboot.
echo ================================================================
pause
goto :eof

REM === SUBROUTINES ===

:create_default_config
echo Creating default configuration file...
echo # Windows 98 SE Kiosk System Configuration > kiosk_config.ini
echo # Edit these values according to your requirements >> kiosk_config.ini
echo. >> kiosk_config.ini
echo [APPLICATION] >> kiosk_config.ini
echo # Full path to your target application >> kiosk_config.ini
echo APP_PATH=C:\YourApp\YourApplication.exe >> kiosk_config.ini
echo APP_NAME=YourApplication.exe >> kiosk_config.ini
echo ENABLE_APP_LAUNCH=1 >> kiosk_config.ini
echo ENABLE_APP_MONITOR=1 >> kiosk_config.ini
echo APP_MONITOR_INTERVAL=10 >> kiosk_config.ini
echo. >> kiosk_config.ini
echo [REMOTE_ACCESS] >> kiosk_config.ini
echo # IP address of remote controller >> kiosk_config.ini
echo REMOTE_HOST=192.168.1.100 >> kiosk_config.ini
echo VNC_PORT=5900 >> kiosk_config.ini
echo HTTP_PORT=5800 >> kiosk_config.ini
echo VNC_PASSWORD=kiosk123 >> kiosk_config.ini
echo VNC_QUALITY=6 >> kiosk_config.ini
echo. >> kiosk_config.ini
echo [SYSTEM_BEHAVIOR] >> kiosk_config.ini
echo # UI Disabling Options (1=disable, 0=keep) >> kiosk_config.ini
echo DISABLE_TASKBAR=1 >> kiosk_config.ini
echo DISABLE_DESKTOP=1 >> kiosk_config.ini
echo DISABLE_SYSTRAY=1 >> kiosk_config.ini
echo REPLACE_SHELL=0 >> kiosk_config.ini
echo STARTUP_DELAY=5 >> kiosk_config.ini
echo. >> kiosk_config.ini
echo [MONITORING] >> kiosk_config.ini
echo # Network monitoring interval in seconds >> kiosk_config.ini
echo NETWORK_CHECK_INTERVAL=30 >> kiosk_config.ini
goto :eof

:load_config
for /f "tokens=1,2 delims==" %%a in (kiosk_config.ini) do (
    if not "%%a"=="" if not "%%b"=="" (
        set %%a=%%b
    )
)
goto :eof