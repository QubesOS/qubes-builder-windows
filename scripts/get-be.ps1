<#
 * The Qubes OS Project, http://www.qubes-os.org
 *
 * Copyright (c) Invisible Things Lab
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 #>

# Qubes builder - preparing Windows build environment for Qubes
#
# If launched outside of existing qubes-builder, clones it to current directory.
# Existing qubes-builder location may be specified via `-builder <path>' option.
# Build environment is contained in 'msys64' directory created in qubes-builder/cache/windows-prereqs.
# This is intended as a base/clean environment. Component-specific scripts may copy it and modify according to their requirements.

Param(
    [string] $builder,      # [optional] If specified, path to existing qubes-builder.
    $GIT_SUBDIR = "QubesOS" # [optional] Same as in builder.conf
)

$verify = $true

Function IsAdministrator()
{
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

Function CheckTLSVersion()
{
    Write-Host "[*] Checking .NET runtime security protocols..."
    $oldSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
    if ([Net.SecurityProtocolType]::Tls12)
    {
        if ($oldSecurityProtocol -eq 0)
        {
            # default starting with .NET 4.7
            Write-Host "[=] Using OS default security protocols."
        }
        elseif ($oldSecurityProtocol -ge [Net.SecurityProtocolType]::Tls12)
        {
            Write-Host "[=] Found TLS 1.2 or later security protocol."
        }
        else
        {
            # add TLS 1.1 and 1.2 to list of enabled protocols
            [Net.ServicePointManager]::SecurityProtocol = $oldSecurityProtocol -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
            Write-Host "[=] Enabled TLS 1.1 and 1.2 security protocols."
        }
    }
    else
    {
        Write-Host "[*] Checking for security protocol extensions (hotfix kb3154518)..."
        # add extensions for .NET 3.5 with hotfix kb3154518 applied
        # https://docs.microsoft.com/en-us/dotnet/api/system.net.securityprotocoltype
        $extensions=@'
namespace System.Net
{
    public static class SecurityProtocolTypeExt
    {
        public const SecurityProtocolType Tls12 = (SecurityProtocolType)3072;
        public const SecurityProtocolType Tls11 = (SecurityProtocolType)768;
        public const SecurityProtocolType SystemDefault = (SecurityProtocolType)0;
    }
}
'@
        Add-Type -TypeDefinition $extensions
        try
        {
            # only accepts single enum values
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolTypeExt]::Tls12
        }
        catch [Exception]
        {
            Write-Host "[!] Required security protocols not supported! Please ensure all Windows updates have been installed, or install PowerShell 3.0 or later for TLS 1.2 support."
            Exit 1
        }
        Write-Host "[=] Enabled TLS 1.2 security protocol extension."
    }
}

Function DownloadFile($url, $fileName)
{
    $uri = [System.Uri] $url
    if ($fileName -eq $null)  { $fileName = $uri.Segments[$uri.Segments.Count-1] } # get file name from URL 
    $fullPath = Join-Path $tmpDir $fileName
    Write-Host "[*] Downloading $pkgName from $url..."
    
    try
    {
	    $client = New-Object System.Net.WebClient
	    $client.DownloadFile($url, $fullPath)
        $client.Dispose()
    }
    catch [Exception]
    {
        Write-Host "[!] Failed to download ${url}:" $_.Exception.Message
        Exit 1
    }
    
    Write-Host "[=] Downloaded: $fullPath"
    return $fullPath
}

Function UnpackZip($filePath, $destination)
{
    Write-Host "[*] Unpacking $filePath..."
    $shell = New-Object -com Shell.Application
    $zip = $shell.Namespace($filePath)
    foreach($item in $zip.Items())
    {
        $shell.Namespace($destination).CopyHere($item, 4+16) # flags: 4=no ui, 16=yes to all
    }
}

Function UnpackTar7z($filePath, $destinationDir)
{
    Write-Host "[*] Unpacking $filePath..."
    # 7za doesn't support extracting from stdin
    $tarDir = (Get-ChildItem $filePath).DirectoryName
    $tar = (Get-ChildItem $filePath).BaseName
    $arg = "x", "-y", "-o$tarDir", $filePath
    & $7zip $arg | Out-Null
    
    $arg = "x", "-y", "-o$destinationDir", (Join-Path $tarDir $tar)
    & $7zip $arg | Out-Null
}

Function PathToUnix($path)
{
    # converts windows path to msys2 path
    $path = $path.Replace('\', '/')
    $path = $path -replace '^([a-zA-Z]):', '/$1'
    return $path
}

Function GetHash($filePath, $hasher)
{
    $fs = New-Object System.IO.FileStream $filePath, "Open"
    $hash = [BitConverter]::ToString($hasher.ComputeHash($fs)).Replace("-", "")
    $fs.Close()
    return $hash.ToLowerInvariant()
}

Function VerifyFile($filePath, $hash, $algorithm)
{
    if ($algorithm)
    {
        $algorithm = $algorithm.Replace("-", "").ToUpper()
    }
    switch ($algorithm)
    {
        "SHA1" { $hasher, $hasherName = [System.Security.Cryptography.SHA1]::Create(), "SHA-1" }
        "SHA512" { $hasher, $hasherName = [System.Security.Cryptography.SHA512]::Create(), "SHA-512" }
        default { $hasher, $hasherName = [System.Security.Cryptography.SHA256]::Create(), "SHA-256" }
    }
    $fileHash = GetHash $filePath $hasher
    if ($fileHash -ne $hash)
    {
        Write-Host "[!] Failed to verify $hasherName checksum of $filePath!"
        Write-Host "[!] Expected: $hash, actual: $fileHash"
        Exit 1
    }
    else
    {
        Write-Host "[=] File successfully verified."
    }
}

Function CreateShortcuts($linkName, $targetPath)
{
    $desktop = [Environment]::GetFolderPath("Desktop")
    $startMenu = [Environment]::GetFolderPath("StartMenu")
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut("$desktop\$linkName")
    $shortcut.TargetPath = $targetPath
    $shortcut.Save()
    $shortcut = $wsh.CreateShortcut("$startMenu\Programs\$linkName")
    $shortcut.TargetPath = $targetPath
    $shortcut.Save()
}

### start

# relaunch elevated if not running as administrator
if (! (IsAdministrator))
{
    [string[]]$argList = @("-ExecutionPolicy", "bypass", "-NoProfile", "-NoExit", "-File", $MyInvocation.MyCommand.Path)
    if ($builder) { $argList += "-builder $builder" }
    if ($verify) { $argList += "-verify" }
    if ($GIT_SUBDIR) { $argList += "-GIT_SUBDIR $GIT_SUBDIR" }
    Start-Process PowerShell.exe -Verb RunAs -WorkingDirectory $pwd -ArgumentList $argList
    return
}

$scriptDir = Split-Path -parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

# log everything from this script
$Host.UI.RawUI.BufferSize.Width = 500

if ($builder)
{
    # use passed value for already existing qubes-builder directory
    $builderDir = $builder

    $logFilePath = Join-Path (Join-Path $builderDir "build-logs") "win-initialize-be.log"
    Start-Transcript -Path $logFilePath

    Write-Host "[*] Using '$builderDir' as qubes-builder directory."
}
else # check if we're invoked from existing qubes-builder
{
    $curDir = Split-Path $scriptDir -Leaf
    $makefilePath = Join-Path (Join-Path $scriptDir "..") "Makefile.windows" -Resolve -ErrorAction SilentlyContinue
    if (($curDir -eq "scripts") -and (Test-Path -Path $makefilePath))
    {
        $builder = $true # don't clone builder later
        $builderDir = Join-Path $scriptDir "..\..\.." -Resolve

        $logFilePath = Join-Path (Join-Path $builderDir "build-logs") "win-initialize-be.log"
        Start-Transcript -Path $logFilePath

        Write-Host "[*] Running from existing qubes-builder ($builderDir)."
    }
    else
    {
        Start-Transcript -Path "win-initialize-be.log"
        Write-Host "[*] Running from clean state, need to clone qubes-builder."
    }
}

if ($builder -and (Test-Path (Join-Path $builderDir "cache\windows-prereqs\msys64")))
{
    Write-Host "[=] BE seems already initialized, delete cache\windows-prereqs\msys64 if you want to rerun this script."
    Exit 0
}

CheckTLSVersion

$tmpDir = Join-Path $scriptDir "tmp"
# delete previous tmp is exists
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue | Out-Null
New-Item $tmpDir -ItemType Directory | Out-Null
Write-Host "[*] Tmp dir: $tmpDir"

# msys2 no longer bundles git, instead we can use MinGit from git-for-windows
$gitDir = Join-Path $tmpDir "git"
New-Item $gitDir -ItemType Directory | Out-Null

# verification hashes are embedded here to keep the script self-contained
$pkgName = "MinGit"
$url = "https://github.com/git-for-windows/git/releases/download/v2.22.0.windows.1/MinGit-2.22.0-64-bit.zip"
$file = DownloadFile $url
VerifyFile $file "308ce95b7de5792bed9d56e1af5d2053052ea6347ea0021f74070056684ce3ee"
UnpackZip $file $gitDir
$gitPath = Join-Path $gitDir "cmd\git.exe"

if (! $builder)
{
    # fetch qubes-builder off the repo
    $repo = "git://github.com/$GIT_SUBDIR/qubes-builder.git"
    $builderDir = Join-Path $scriptDir "qubes-builder"
    Write-Host "[*] Cloning qubes-builder to $builderDir"
    & $gitPath clone $repo $builderDir
}

if ($verify)
{
    # install gpg if needed
    $gpgRegistryPath = "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\GnuPG"
    $gpgInstalled = Test-Path $gpgRegistryPath

    if ($gpgInstalled)
    {
        Write-Host "[*] GnuPG is already installed."
    }
    else
    {
        $pkgName = "GnuPG"
        $url = "https://files.gpg4win.org/gpg4win-3.1.9.exe"
        $file = DownloadFile $url
        VerifyFile $file "20f1d709f95d59f101744ad9e5ee5f1b6abea0d0e083102985b2385035117c59"

        Write-Host "[*] Installing GnuPG..."
        Start-Process -FilePath $file -Wait -PassThru -ArgumentList @("/S") | Out-Null
    }

    $gpgDir = (Get-ItemProperty $gpgRegistryPath).InstallLocation
    $gpgBinDir = Join-Path $gpgDir "bin"
    $gpg = Join-Path $gpgBinDir "gpg.exe"
    # additional sanity check
    if (!(Test-Path $gpg))
    {
        Write-Host "[!] GPG not found: '$gpg'!"
        Exit 1
    }

    Set-Location $builderDir

    Write-Host "[*] Importing Qubes OS signing keys..."
    # import master qubes signing key
    & $gpg --keyserver hkp://keys.gnupg.net --recv-keys 0xDDFA1A3E36879494

    # import other dev keys
    DownloadFile "https://keys.qubes-os.org/keys/qubes-developers-keys.asc"
    $file = Join-Path $tmpDir "qubes-developers-keys.asc"
    & $gpg --import $file

    # add gpg to PATH
    $env:Path = "$env:Path;$gpgBinDir"

    # verify qubes-builder tags
    $tag = & $gitPath tag --points-at=HEAD | Select -First 1
    $ret = & $gitPath tag -v $tag
    if ($?)
    {
        Write-Host "[*] qubes-builder successfully verified."
    }
    else
    {
        Write-Host "[!] Failed to verify qubes-builder! Output:`n$ret"
        Exit 1
    }
}

$prereqsDir = Join-Path $builderDir "cache\windows-prereqs"
New-Item -ItemType Directory $prereqsDir -ErrorAction SilentlyContinue | Out-Null

$pkgName = "7zip"
$url = "https://downloads.sourceforge.net/sevenzip/7za920.zip"
$file = DownloadFile $url
VerifyFile $file "9ce9ce89ebc070fea5d679936f21f9dde25faae0" "SHA1"
UnpackZip $file $prereqsDir
$7zip = Join-Path $prereqsDir "7za.exe"

$pkgName = "msys2"
$url = "https://downloads.sourceforge.net/msys2/Base/x86_64/msys2-base-x86_64-20190524.tar.xz"
$file = DownloadFile $url
VerifyFile $file "cfe5035b1b81b43469d16bfc23be8006b9a44455" "SHA1"
UnpackTar7z $file $prereqsDir
$msysDir = Join-Path $prereqsDir "msys64"
$msysExe = (Join-Path $msysDir "msys2.exe")

# set msys2 to start in qubes-builder directory
$builderUnix = PathToUnix $builderDir
$cmd = "cd $builderUnix"
Add-Content (Join-Path $msysDir "etc\profile") "`n$cmd"

# add msys2 shortcuts to desktop/start menu
Write-Host "[*] Adding shortcuts to msys2..."
CreateShortcuts "qubes-msys2.lnk" $msysExe

# generate code signing certificate
Write-Host "[*] Generating code-signing certificate (use no password)..."
$wdkKey = "HKLM:SOFTWARE\Microsoft\Windows Kits\Installed Roots"
$wdkPath = (Get-ItemProperty -Path $wdkKey).KitsRoot81
$makecertPath = $(GetChildItem -Path $wdkPath -Filter makecert.exe -Recurse)
$pvk2pfxPath = $(GetChildItem -Path $wdkPath -Filter pvk2pfx.exe -Recurse)
$wdkPath = Join-Path $wdkPath "bin\x64\"
echo $wdkPath
& $makecertPath -sv $builderDir\qwt.pvk -n "CN=Qubes Test Cert" $builderDir\qwt.cer -r
& $pvk2pfxPath -pvk $builderDir\qwt.pvk -spc $builderDir\qwt.cer -pfx $builderDir\qwt.pfx

# cleanup
Write-Host "[*] Cleanup"
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "[=] Done"
# start msys2 shell
Start-Process -FilePath $msysExe

Stop-Transcript
