:: default installer build
:: called from Makefile.Windows at the end of dist-package
@ECHO OFF

SET DIFXLIB="%WIX%\difxapp_%DDK_ARCH%.wixlib"
SET MSIARCH=%DDK_ARCH%
IF "%WIN_BUILD_TYPE%"=="chk" (SET MSIBUILD=_debug) ELSE (SET MSIBUILD=)
SET MSIOS=%DDK_DIST%

:: msm or msi extension is the script's parameter
if "%1"=="msm" (
    SET MSISUFFIX=-%MSIOS%%MSIARCH%%MSIBUILD%.msm
) ELSE (
    SET MSISUFFIX=-%MSIOS%%MSIARCH%-%VERSION%%MSIBUILD%.msi
)

:: Iterate over all installer source files.
for /R %%f in (*.wxs) do call :build %%~nf

:: Return 0 without checking errorlevel because wix warnings can cause it to return nonzero values.
:: If there's an error we catch it below.
exit /b 0

:build
set FILENAME=%1

set MSINAME=%FILENAME%%MSISUFFIX%

"%WIX%\candle" %FILENAME%.wxs -arch %MSIARCH% -ext "%WIX%\WixUIExtension.dll" -ext "%WIX%\WixDifxAppExtension.dll" -ext "%WIX%\WixIIsExtension.dll"
"%WIX%\light.exe" -o %MSINAME% %FILENAME%.wixobj %DIFXLIB% -ext "%WIX%\WixUIExtension.dll" -ext "%WIX%\WixDifxAppExtension.dll" -ext "%WIX%\WixIIsExtension.dll"

:: FIXME: This is not an ideal way to check for errors because the output file may be created
:: even if wix fails to merge something in. We can't rely on wix warnings (errorlevel) because
:: some of them are unavoidable (eg. when merging MSVCRT redistributables).
if not exist %MSINAME% goto :error
:: return
goto :eof

:error
echo [!] Building %MSINAME% FAILED
exit 1
