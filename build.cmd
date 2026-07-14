@echo off
setlocal enabledelayedexpansion

rem ============================================================
rem  BaKGL Windows build script (MSVC + Ninja)
rem
rem  Downloads/builds the Windows-only dependencies that aren't
rem  fetched by CMake itself (freeglut, GLEW, SDL2, FluidSynth),
rem  then configures and builds the project with Ninja.
rem
rem  Re-run any time; already-fetched dependencies are skipped.
rem ============================================================

set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%
set BUILD=%ROOT%\build
set DEPS=%BUILD%\deps

rem --- Locate Visual Studio and set up the MSVC dev environment ---
if defined VSCMD_VER goto :have_vcvars

set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
set VCVARS=
if exist "%VSWHERE%" (
    "%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find "VC\Auxiliary\Build\vcvars64.bat" > "%TEMP%\bakgl_vcvars_path.txt" 2>nul
    set /p VCVARS=<"%TEMP%\bakgl_vcvars_path.txt"
    del "%TEMP%\bakgl_vcvars_path.txt" >nul 2>nul
)
if not defined VCVARS set VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat
if not exist "%VCVARS%" (
    echo Could not find vcvars64.bat. Install Visual Studio 2022 Build Tools with the "Desktop development with C++" workload, or edit VCVARS in this script.
    exit /b 1
)
call "%VCVARS%"
if errorlevel 1 exit /b 1
:have_vcvars

where ninja >nul 2>nul
if errorlevel 1 (
    echo ninja.exe not found on PATH even after loading vcvars64 - is the "C++ CMake tools for Windows" component installed?
    exit /b 1
)

if not exist "%DEPS%" mkdir "%DEPS%"

rem --- freeglut (built from source; no MSVC binaries are published upstream) ---
if not exist "%DEPS%\freeglut-install\lib\freeglut.lib" (
    echo === Building freeglut ===
    if not exist "%DEPS%\freeglut-src.tar.gz" (
        curl -sL -o "%DEPS%\freeglut-src.tar.gz" "https://github.com/FreeGLUTProject/freeglut/releases/download/v3.6.0/freeglut-3.6.0.tar.gz" || exit /b 1
    )
    if not exist "%DEPS%\freeglut-3.6.0" (
        tar xzf "%DEPS%\freeglut-src.tar.gz" -C "%DEPS%" || exit /b 1
    )
    if not exist "%DEPS%\freeglut-3.6.0\build" mkdir "%DEPS%\freeglut-3.6.0\build"
    pushd "%DEPS%\freeglut-3.6.0\build"
    cmake -GNinja -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=RelWithDebInfo ^
        -DCMAKE_INSTALL_PREFIX="%DEPS%\freeglut-install" ^
        -DFREEGLUT_BUILD_DEMOS=OFF -DFREEGLUT_BUILD_STATIC_LIBS=OFF -DFREEGLUT_BUILD_SHARED_LIBS=ON .. || (popd & exit /b 1)
    ninja install || (popd & exit /b 1)
    popd
    rem freeglut's CMake install doesn't ship the GL/glut.h compatibility header; copy it in.
    copy /y "%DEPS%\freeglut-3.6.0\include\GL\glut.h" "%DEPS%\freeglut-install\include\GL\glut.h" >nul
)

rem --- GLEW (prebuilt MSVC binaries) ---
if not exist "%DEPS%\glew-2.1.0\lib\Release\x64\glew32.lib" (
    echo === Fetching GLEW ===
    if not exist "%DEPS%\glew-2.1.0-win32.zip" (
        curl -sL -o "%DEPS%\glew-2.1.0-win32.zip" "https://github.com/nigels-com/glew/releases/download/glew-2.1.0/glew-2.1.0-win32.zip" || exit /b 1
    )
    powershell -NoProfile -Command "Expand-Archive -Force '%DEPS%\glew-2.1.0-win32.zip' '%DEPS%'" || exit /b 1
)

rem --- SDL2 (prebuilt MSVC binaries; needs a version new enough to ship cmake/sdl2-config.cmake) ---
if not exist "%DEPS%\SDL2-2.30.11\lib\x64\SDL2.lib" (
    echo === Fetching SDL2 ===
    if not exist "%DEPS%\SDL2-devel-2.30.11-VC.zip" (
        curl -sL -o "%DEPS%\SDL2-devel-2.30.11-VC.zip" "https://github.com/libsdl-org/SDL/releases/download/release-2.30.11/SDL2-devel-2.30.11-VC.zip" || exit /b 1
    )
    powershell -NoProfile -Command "Expand-Archive -Force '%DEPS%\SDL2-devel-2.30.11-VC.zip' '%DEPS%'" || exit /b 1
)
if not exist "%DEPS%\SDL2-2.30.11\include\SDL2\SDL.h" (
    rem BaKGL includes headers as <SDL2/SDL_*.h> (the Linux libsdl2-dev layout); the
    rem Windows VC package ships them flat, so mirror them into an SDL2/ subfolder.
    if not exist "%DEPS%\SDL2-2.30.11\include\SDL2" mkdir "%DEPS%\SDL2-2.30.11\include\SDL2"
    copy /y "%DEPS%\SDL2-2.30.11\include\*.h" "%DEPS%\SDL2-2.30.11\include\SDL2\" >nul
)

rem --- FluidSynth, for real soundfont-based MIDI playback (via vcpkg) ---
if not exist "%DEPS%\vcpkg\installed\x64-windows\lib\libfluidsynth-3.lib" (
    echo === Building FluidSynth via vcpkg ===
    if not exist "%DEPS%\vcpkg" (
        git clone --depth 1 https://github.com/microsoft/vcpkg.git "%DEPS%\vcpkg" || exit /b 1
    )
    if not exist "%DEPS%\vcpkg\vcpkg.exe" (
        pushd "%DEPS%\vcpkg"
        call .\bootstrap-vcpkg.bat -disableMetrics || (popd & exit /b 1)
        popd
    )
    pushd "%DEPS%\vcpkg"
    .\vcpkg.exe install fluidsynth:x64-windows || (popd & exit /b 1)
    popd
)

rem --- Configure ---
if not exist "%BUILD%" mkdir "%BUILD%"
pushd "%BUILD%"
cmake -GNinja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ^
    "-DCMAKE_PREFIX_PATH=%DEPS:\=/%/freeglut-install;%DEPS:\=/%/glew-2.1.0;%DEPS:\=/%/SDL2-2.30.11;%DEPS:\=/%/SDL2-2.30.11/lib/x64;%DEPS:\=/%/vcpkg/installed/x64-windows" ^
    "-DFluidSynth_INCLUDE_DIR=%DEPS:\=/%/vcpkg/installed/x64-windows/include" ^
    "-DFluidSynth_LIBRARY=%DEPS:\=/%/vcpkg/installed/x64-windows/lib/libfluidsynth-3.lib" ^
    .. || (popd & exit /b 1)
if exist compile_commands.json copy /y compile_commands.json "%ROOT%\compile_commands.json" >nul

rem --- Build ---
ninja
if errorlevel 1 (popd & exit /b 1)

rem --- Stage runtime DLLs next to the built executables ---
copy /y "%DEPS%\glew-2.1.0\bin\Release\x64\glew32.dll" . >nul
copy /y "%DEPS%\freeglut-install\bin\freeglut.dll" . >nul
copy /y "%DEPS%\SDL2-2.30.11\lib\x64\SDL2.dll" . >nul
copy /y "%DEPS%\vcpkg\installed\x64-windows\bin\libfluidsynth-3.dll" . >nul
popd

echo.
echo Build complete: %BUILD%\main3d.exe
