@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: build.cmd -- Gifsicle Windows build wrapper
::
:: Detects an existing MSVC compiler (via vswhere), loads the
:: x64 developer environment, and builds gifsicle.exe and
:: gifdiff.exe with nmake. Nothing is downloaded or installed.
::
:: Usage:
::   build                 Build x64 (default)
::   build x86             Build 32-bit
::   build clean           Clean, then build x64
::   build ungif           Build with unpatented compression
::   build x86 clean       Combine options freely
::   build --help          Show usage
:: ============================================================

set "ARCH=x64"
set "CLEAN="
set "UNGIF="

:parse_args
if "%~1"=="" goto :run
set "ARG=%~1"
call :to_upper ARG
if "!ARG!"=="X64"    ( set "ARCH=x64" & shift & goto :parse_args )
if "!ARG!"=="X86"    ( set "ARCH=x86" & shift & goto :parse_args )
if "!ARG!"=="CLEAN"  ( set "CLEAN=-Clean" & shift & goto :parse_args )
if "!ARG!"=="UNGIF"  ( set "UNGIF=-Ungif" & shift & goto :parse_args )
if "!ARG!"=="/?"     goto :usage
if "!ARG!"=="-H"     goto :usage
if "!ARG!"=="--HELP" goto :usage

echo.
echo  ERROR: Unknown argument '%~1'
call :print_usage
exit /b 1

:run
set "LOG=%~dp0build_win.log"
echo.
echo  Gifsicle Windows Build
echo  Arch: %ARCH%   Clean: %CLEAN%   Ungif: %UNGIF%
echo  Log:  %LOG%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Arch %ARCH% %CLEAN% %UNGIF% -LogFile "%LOG%"
set "EC=%ERRORLEVEL%"

if %EC% neq 0 (
    echo.
    echo  BUILD FAILED [exit code %EC%] -- see %LOG%
    echo.
) else (
    echo.
    echo  BUILD SUCCEEDED -- output in dist\%ARCH%\
    echo.
)
exit /b %EC%

:usage
call :print_usage
exit /b 0

:print_usage
echo.
echo  Usage: build [arch] [options]
echo.
echo  Architecture:
echo    x64         64-bit build (default)
echo    x86         32-bit build
echo.
echo  Options:
echo    clean       Remove build artifacts first
echo    ungif       Use unpatented run-length compression
echo.
echo  Examples:
echo    build                 x64 release
echo    build x86 clean       clean 32-bit build
echo.
goto :eof

:to_upper
for %%a in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    set "%1=!%1:%%a=%%a!"
)
goto :eof
