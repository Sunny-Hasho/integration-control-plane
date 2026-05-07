@echo off
REM Copyright (c) 2025, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
REM
REM WSO2 Inc. licenses this file to you under the Apache License,
REM Version 2.0 (the "License"); you may not use this file except
REM in compliance with the License.
REM You may obtain a copy of the License at
REM
REM      http://www.apache.org/licenses/LICENSE-2.0
REM
REM Unless required by applicable law or agreed to in writing,
REM software distributed under the License is distributed on an
REM "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
REM KIND, either express or implied.  See the License for the
REM specific language governing permissions and limitations
REM under the License.

REM ICP Server Launcher Script
REM Usage: icp.bat [start^|stop^|restart^|run^|version]

setlocal EnableDelayedExpansion
set SCRIPT_DIR=%~dp0
set JAR_FILE=!SCRIPT_DIR!icp-server.jar
for %%A in ("!SCRIPT_DIR!..") do set PARENT_DIR=%%~fA
set CONFIG_FILE=!PARENT_DIR!\conf\deployment.toml
set PID_FILE=!PARENT_DIR!\icp.pid
set LOG_DIR=!PARENT_DIR!\logs
set LOG_FILE=!LOG_DIR!\icp.log
set COMMAND=run
if /I "!PROCESSOR_ARCHITECTURE!"=="ARM64" (
    echo ARM Windows detected - disabling native Netty tcnative libraries
    set "JAVA_OPTS=!JAVA_OPTS! -Dio.netty.transport.noNative=true -Dio.netty.handler.ssl.noOpenSsl=true"
) else if /I "!PROCESSOR_ARCHITEW6432!"=="ARM64" (
    echo ARM Windows detected - disabling native Netty tcnative libraries
    set "JAVA_OPTS=!JAVA_OPTS! -Dio.netty.transport.noNative=true -Dio.netty.handler.ssl.noOpenSsl=true"
)
set "ARG=%~1"
set "NORMALIZED_ARG=!ARG!"
set "CANDIDATE="

:normalizeArg
if defined NORMALIZED_ARG (
    if "!NORMALIZED_ARG:~0,2!"=="--" (
        set "CANDIDATE=!NORMALIZED_ARG:~2!"
    ) else if "!NORMALIZED_ARG:~0,1!"=="-" (
        set "CANDIDATE=!NORMALIZED_ARG:~1!"
    )
)

if /I "!CANDIDATE!"=="start" (
    set "ARG=!CANDIDATE!"
) else if /I "!CANDIDATE!"=="stop" (
    set "ARG=!CANDIDATE!"
) else if /I "!CANDIDATE!"=="restart" (
    set "ARG=!CANDIDATE!"
) else if /I "!CANDIDATE!"=="version" (
    set "ARG=!CANDIDATE!"
) else if /I "!CANDIDATE!"=="run" (
    set "ARG=!CANDIDATE!"
)

if /I "!ARG!"=="start" (
    set COMMAND=start
    shift
) else if /I "!ARG!"=="stop" (
    set COMMAND=stop
    shift
) else if /I "!ARG!"=="restart" (
    set COMMAND=restart
    shift
) else if /I "!ARG!"=="version" (
    set COMMAND=version
    shift
) else if /I "!ARG!"=="run" (
    set COMMAND=run
    shift
)

set "FORWARD_ARGS="
:collectForwardArgs
if "%~1"=="" goto dispatchCommand
set "FORWARD_ARGS=!FORWARD_ARGS! %1"
shift
goto collectForwardArgs

:dispatchCommand
if /I "!COMMAND!"=="start" goto startServer
if /I "!COMMAND!"=="stop" goto stopServer
if /I "!COMMAND!"=="restart" goto restartServer
if /I "!COMMAND!"=="version" goto printVersion
goto runServer

:printVersion
set VERSION=
if exist "!PARENT_DIR!\version.txt" (
    set /p VERSION=<"!PARENT_DIR!\version.txt"
)
if defined VERSION (
    echo WSO2 Integration Control Plane !VERSION!
    goto end
)
for %%I in ("!PARENT_DIR!") do set DIST_NAME=%%~nxI
if /I not "!DIST_NAME:wso2-integration-control-plane-=!"=="!DIST_NAME!" (
    set VERSION=!DIST_NAME:wso2-integration-control-plane-=!
)
if not defined VERSION if exist "!JAR_FILE!" if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    for /f "usebackq delims=" %%V in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$jar = $env:JAR_FILE; Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead($jar); try { $entry = $zip.GetEntry('META-INF/MANIFEST.MF'); if ($entry) { $reader = New-Object System.IO.StreamReader($entry.Open()); try { $manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }; $version = [regex]::Match($manifest, '(?m)^Implementation-Version:\s*(.+)$').Groups[1].Value.Trim(); if (-not $version) { $version = [regex]::Match($manifest, '(?m)^Specification-Version:\s*(.+)$').Groups[1].Value.Trim() }; if ($version) { Write-Output $version } } } finally { $zip.Dispose() }"`) do (
        set VERSION=%%V
    )
)
if not defined VERSION set VERSION=unknown
echo WSO2 Integration Control Plane !VERSION!
goto end

:checkJar
if not exist "!JAR_FILE!" (
    echo Error: icp-server.jar not found in !SCRIPT_DIR!
    exit /b 1
)
exit /b 0

:isRunning
set SERVER_PID=
if exist "!PID_FILE!" (
    set /p SERVER_PID=<"!PID_FILE!"
    if defined SERVER_PID (
        tasklist /FI "PID eq !SERVER_PID!" | find "!SERVER_PID!" >nul 2>&1 && exit /b 0
    )
)
exit /b 1

:prepareRun
call :checkJar
if errorlevel 1 goto end
call :buildIcpClasspath
call :resolveMainClass
if errorlevel 1 goto end
if not exist "!LOG_DIR!" mkdir "!LOG_DIR!"
cd /d "!SCRIPT_DIR!"
if exist "!CONFIG_FILE!" (
    echo Starting ICP Server with configuration: !CONFIG_FILE!
    set "BAL_CONFIG_FILES=!CONFIG_FILE!"
) else (
    echo Warning: Configuration file not found at !CONFIG_FILE!
    echo Starting ICP Server without custom configuration...
    set "BAL_CONFIG_FILES="
)
exit /b 0

:buildIcpClasspath
set "ICP_CLASSPATH=!JAR_FILE!"
for %%c in ("!PARENT_DIR!\lib\*.jar") do set "ICP_CLASSPATH=!ICP_CLASSPATH!;%%~c"
exit /b 0

:resolveMainClass
set "ICP_MAIN_CLASS="
set "RESOLVE_JAR=!JAR_FILE!"
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    for /f "usebackq delims=" %%M in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$jar = $env:RESOLVE_JAR; Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead($jar); try { $entry = $zip.GetEntry('META-INF/MANIFEST.MF'); if ($entry) { $r = New-Object System.IO.StreamReader($entry.Open()); try { $m = $r.ReadToEnd() } finally { $r.Dispose() }; ([regex]::Match($m, '(?m)^Main-Class:\s*(.+)$')).Groups[1].Value.Trim() } } finally { $zip.Dispose() }"`) do (
        set "ICP_MAIN_CLASS=%%M"
    )
)
if not defined ICP_MAIN_CLASS (
    echo Error: Cannot determine main class from !JAR_FILE!
    exit /b 1
)
exit /b 0

:buildArgsJson
setlocal EnableDelayedExpansion
set "ARGS_JSON=["
:buildArgsJsonLoop
if "%~1"=="" goto buildArgsJsonDone
set "ARG_VALUE=%~1"
set "ARG_VALUE=!ARG_VALUE:\=\\!"
set "ARG_VALUE=!ARG_VALUE:"=\"!"
if "!ARGS_JSON!"=="[" (
    set "ARGS_JSON=!ARGS_JSON!\"!ARG_VALUE!\""
) else (
    set "ARGS_JSON=!ARGS_JSON!,\"!ARG_VALUE!\""
)
shift
goto buildArgsJsonLoop

:buildArgsJsonDone
set "ARGS_JSON=!ARGS_JSON!]"
endlocal & set "ICP_APP_ARGS_JSON=%ARGS_JSON%"
exit /b 0

:startServer
call :isRunning
if not errorlevel 1 (
    echo Process is already running with PID !SERVER_PID!
    goto end
)
if exist "!PID_FILE!" del /f /q "!PID_FILE!" >nul 2>&1
call :prepareRun
if errorlevel 1 goto end
call :buildArgsJson !FORWARD_ARGS!
set "ICP_LOG_FILE=!LOG_FILE!"
set "ICP_ERR_LOG_FILE=!LOG_FILE!.err"
set "ICP_SCRIPT_DIR=!SCRIPT_DIR!"
set "ICP_JAVA_OPTS=!JAVA_OPTS!"
set "ICP_CLASSPATH_PS=!ICP_CLASSPATH!"
set "ICP_MAIN_CLASS_PS=!ICP_MAIN_CLASS!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$cp = $env:ICP_CLASSPATH_PS; $mc = $env:ICP_MAIN_CLASS_PS; $log = $env:ICP_LOG_FILE; $errLog = $env:ICP_ERR_LOG_FILE; $wd = $env:ICP_SCRIPT_DIR; $appArgs = @(); if ($env:ICP_APP_ARGS_JSON -and $env:ICP_APP_ARGS_JSON -ne '[]') { $appArgs = @(ConvertFrom-Json -InputObject $env:ICP_APP_ARGS_JSON) }; $javaOpts = @(); if ($env:ICP_JAVA_OPTS) { $javaOpts = $env:ICP_JAVA_OPTS -split '\s+' | Where-Object { $_ } }; $javaArgs = $javaOpts + @('-cp', $cp, $mc) + $appArgs; $p = Start-Process -FilePath 'java' -ArgumentList $javaArgs -WorkingDirectory $wd -RedirectStandardOutput $log -RedirectStandardError $errLog -PassThru -WindowStyle Hidden; $p.Id" > "!PID_FILE!"
set /p SERVER_PID=<"!PID_FILE!"
if not defined SERVER_PID (
    echo Failed to start ICP Server
    if exist "!PID_FILE!" del /f /q "!PID_FILE!" >nul 2>&1
    goto end
)
echo ICP Server started with PID !SERVER_PID!
echo Stdout log: !LOG_FILE!
echo Stderr log: !ICP_ERR_LOG_FILE!
goto end

:stopServer
call :isRunning
if errorlevel 1 (
    if exist "!PID_FILE!" del /f /q "!PID_FILE!" >nul 2>&1
    echo ICP Server is not running
    goto end
)
echo Stopping ICP Server ^(PID !SERVER_PID!^)
taskkill /PID !SERVER_PID! /T >nul 2>&1
set /a STOP_WAIT_COUNT=0

:stopWaitLoop
call :isRunning
if errorlevel 1 goto stopCleanup
set /a STOP_WAIT_COUNT+=1
if !STOP_WAIT_COUNT! GEQ 10 goto forceStopServer
ping -n 2 127.0.0.1 >nul
goto stopWaitLoop

:forceStopServer
echo Graceful shutdown timed out; forcing stop
taskkill /PID !SERVER_PID! /T /F >nul 2>&1
set /a FORCE_STOP_WAIT_COUNT=0

:forceStopWaitLoop
call :isRunning
if errorlevel 1 goto stopCleanup
set /a FORCE_STOP_WAIT_COUNT+=1
if !FORCE_STOP_WAIT_COUNT! GEQ 10 goto stopFailed
ping -n 2 127.0.0.1 >nul
goto forceStopWaitLoop

:stopCleanup
if exist "!PID_FILE!" del /f /q "!PID_FILE!" >nul 2>&1
echo ICP Server stopped
goto end

:stopFailed
echo Failed to stop ICP Server within the timeout window
goto end

:restartServer
call :isRunning
if errorlevel 1 goto startServer

echo Stopping ICP Server ^(PID !SERVER_PID!^)
taskkill /PID !SERVER_PID! /T >nul 2>&1
set /a WAIT_COUNT=0

:restartWaitLoop
call :isRunning
if errorlevel 1 goto restartCleanup
set /a WAIT_COUNT+=1
if !WAIT_COUNT! GEQ 10 goto forceRestartStop
ping -n 2 127.0.0.1 >nul
goto restartWaitLoop

:forceRestartStop
echo Graceful restart shutdown timed out; forcing stop
taskkill /PID !SERVER_PID! /T /F >nul 2>&1
set /a RESTART_FORCE_WAIT_COUNT=0

:restartForceWaitLoop
call :isRunning
if errorlevel 1 goto restartCleanup
set /a RESTART_FORCE_WAIT_COUNT+=1
if !RESTART_FORCE_WAIT_COUNT! GEQ 10 goto restartFailed
ping -n 2 127.0.0.1 >nul
goto restartForceWaitLoop

:restartCleanup
if exist "!PID_FILE!" del /f /q "!PID_FILE!" >nul 2>&1
goto startServer

:restartFailed
echo Failed to stop ICP Server for restart within the timeout window
goto end

:runServer
call :prepareRun
if errorlevel 1 goto end
java !JAVA_OPTS! -cp "!ICP_CLASSPATH!" !ICP_MAIN_CLASS! !FORWARD_ARGS!
if exist "!PID_FILE!" del /f /q "!PID_FILE!" >nul 2>&1

:end
endlocal
