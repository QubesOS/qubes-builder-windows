:: default installer build
:: called from Makefile.Windows at the end of dist-package
@ECHO OFF

SET DIFXLIB="%WIX%\difxapp_%DDK_ARCH%.wixlib"
SET MSIARCH=%DDK_ARCH%
IF "%WIN_BUILD_TYPE%"=="chk" (SET MSIBUILD=_debug) ELSE (SET MSIBUILD=)
SET MSIOS=%DDK_DIST%

:: msm or msi extension is the script's parameter
if "%1"=="msm" (
    SET MSISUFFIX=-%MSIOS%%MSIARCH%%MSIBUILD%
    SET MSIEXT=.msm
) ELSE (
    SET MSISUFFIX=-%MSIOS%%MSIARCH%-%VERSION%%MSIBUILD%
    SET MSIEXT=.msi
)

:: Iterate over all installer source files.
for /R %%f in (*.wxs) do call :build %%~nf

:: Build bundles if present.
for /R %%f in (*.wxb) do call :bundle %%~nf

:: Return 0 without checking errorlevel because wix warnings can cause it to return nonzero values.
:: If there's an error we catch it below.
exit /b 0

:build
set FILENAME=%1
set MSINAME=%FILENAME%%MSISUFFIX%
set MSIOUT=%MSINAME%%MSIEXT%

"%WIX%\candle" %FILENAME%.wxs -arch %MSIARCH% -ext "%WIX%\WixUIExtension.dll" -ext "%WIX%\WixDifxAppExtension.dll" -ext "%WIX%\WixIIsExtension.dll"
"%WIX%\light" -o %MSIOUT% %FILENAME%.wixobj %DIFXLIB% -ext "%WIX%\WixUIExtension.dll" -ext "%WIX%\WixDifxAppExtension.dll" -ext "%WIX%\WixIIsExtension.dll"

:: FIXME: This is not an ideal way to check for errors because the output file may be created
:: even if wix fails to merge something in. We can't rely on wix warnings (errorlevel) because
:: some of them are unavoidable (eg. when merging MSVCRT redistributables).
if not exist %MSIOUT% goto :error
:: return
goto :eof

:bundle
set FILENAME=%1
set MSINAME=%FILENAME%%MSISUFFIX%
set MSIOUT=%MSINAME%.exe

"%WIX%\candle" %FILENAME%.wxb -arch %MSIARCH% -ext "%WIX%\WixUIExtension.dll" -ext "%WIX%\WixBalExtension.dll"
"%WIX%\light" -o %MSIOUT% %FILENAME%.wixobj -ext "%WIX%\WixUIExtension.dll" -ext "%WIX%\WixBalExtension.dll"

if not "%CERT_FILENAME%"="" (
    :: Sign the bundle engine if we're signing stuff, otherwise installation will fail during payload extraction.
    "%WIX%\insignia" -ib %MSIOUT% -o engine.exe
    %SIGNTOOL% sign /v %CERT_CROSS_CERT_FLAG% /f "%CERT_FILENAME%" %CERT_PASSWORD_FLAG% /t http://timestamp.verisign.com/scripts/timestamp.dll engine.exe
    "%WIX%\insignia" -ab engine.exe %MSIOUT% -o %MSIOUT%
)

:: FIXME: This is not an ideal way to check for errors because the output file may be created
:: even if wix fails to merge something in. We can't rely on wix warnings (errorlevel) because
:: some of them are unavoidable (eg. when merging MSVCRT redistributables).
if not exist %MSIOUT% goto :error
:: return
goto :eof

:error
echo [!] Building %MSIOUT% FAILED
exit 1
