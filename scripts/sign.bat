:: default executable signing
:: called from Makefile.Windows at the end of dist-package
@ECHO OFF

IF NOT EXIST SIGN_CONFIG.BAT GOTO END

for /R %%f in (*.dll;*.exe;*.msi;*.sys;*.cat) do call :sign "%%f"

goto :END

:sign

:: don't sign again if already properly signed
%SIGNTOOL% verify /pa %1
if not errorlevel 1 goto :eof

%SIGNTOOL% sign /v %CERT_CROSS_CERT_FLAG% /f "%CERT_FILENAME%" %CERT_PASSWORD_FLAG% /tr http://timestamp.digicert.com /td sha256 /fd sha256 %1
:: return
goto :eof

:END
