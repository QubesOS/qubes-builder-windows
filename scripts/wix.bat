:: default installer build
:: called from Makefile.Windows at the end of dist-package
@ECHO OFF

SET DIFXLIB="%WIX%\difxapp_%DDK_ARCH%.wixlib"
SET MSIARCH=%DDK_ARCH%
IF "%WIN_BUILD_TYPE%"=="chk" (SET MSIBUILD=_debug) ELSE (SET MSIBUILD=)
SET MSIOS=%DDK_DIST%

:: msm or msi extension is the script's parameter
if "%1"=="msm" (
    SET MSINAME=%COMPONENT%-%MSIOS%%MSIARCH%%MSIBUILD%.msm
) ELSE (
    SET MSINAME=%COMPONENT%-%MSIOS%%MSIARCH%-%VERSION%%MSIBUILD%.msi
)

"%WIX%\candle" installer.wxs -arch %MSIARCH% -ext "%WIX%\WixUIExtension.dll" -ext "%WIX%\WixDifxAppExtension.dll"
"%WIX%\light.exe" -o %MSINAME% installer.wixobj %DIFXLIB% -ext "%WIX%\WixUIExtension.dll" -ext "%WIX%\WixDifxAppExtension.dll"
exit /b 0
