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
# Build environment is contained in 'msys' directory created in qubes-builder/cache/windows-prereqs. It also contains mingw64.
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
    $arg = "x", "-y", "-o$destinationDir", $filePath
    & $7zip $arg | Out-Null
    
    $tar = Get-ChildItem $filePath
    $arg = "x", "-y", "-o$destinationDir", (Join-Path $tar.DirectoryName $tar.BaseName)
    & $7zip $arg | Out-Null
}

Function PathToUnix($path)
{
    # converts windows path to msys/mingw path
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

if ($builder -and (Test-Path (Join-Path $builderDir "cache\windows-prereqs\msys")))
{
    Write-Host "[=] BE seems already initialized, delete cache\windows-prereqs\msys if you want to rerun this script."
    Exit 0
}

$tmpDir = Join-Path $scriptDir "tmp"
# delete previous tmp is exists
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue | Out-Null
New-Item $tmpDir -ItemType Directory | Out-Null
Write-Host "[*] Tmp dir: $tmpDir"

# verification hashes are embedded here to keep the script self-contained
$pkgName = "7zip"
$url = "http://downloads.sourceforge.net/sevenzip/7za920.zip"
$file = DownloadFile $url
VerifyFile $file "9ce9ce89ebc070fea5d679936f21f9dde25faae0" "SHA1"
UnpackZip $file $tmpDir
$7zip = Join-Path $tmpDir "7za.exe"

$pkgName = "msys"
$url = "http://downloads.sourceforge.net/project/mingwbuilds/external-binary-packages/msys%2B7za%2Bwget%2Bsvn%2Bgit%2Bmercurial%2Bcvs-rev13.7z"
$file = DownloadFile $url
VerifyFile $file "ed6f1ec0131530122d00eed096fbae7eb76f8ec9" "SHA1"
Unpack7z $file $tmpDir
$msysDir = (Join-Path $tmpDir "msys")

# msys2 no longer bundles git, instead we can use MinGit from git-for-windows
$tmpGitDir = Join-Path $tmpDir "git"
New-Item $tmpGitDir -ItemType Directory | Out-Null

$pkgName = "MinGit"
$url = "https://github.com/git-for-windows/git/releases/download/v2.21.0.windows.1/MinGit-2.21.0-64-bit.zip"
$file = DownloadFile $url
VerifyFile $file "bd91db55bd95eaa80687df28877e2df8c8858a0266e9c67331cfddba2735f25c"
UnpackZip $file $tmpGitDir
$gitPath = Join-Path $tmpGitDir "cmd\git.exe"

if (! $builder)
{
    # fetch qubes-builder off the repo
    $repo = "git://github.com/$GIT_SUBDIR/qubes-builder.git"
    $builderDir = Join-Path $scriptDir "qubes-builder"
    Write-Host "[*] Cloning qubes-builder to $builderDir"
    & $gitPath clone $repo $builderDir
}

$prereqsDir = Join-Path $builderDir "cache\windows-prereqs"
Write-Host "[*] Moving msys to $prereqsDir..."
New-Item -ItemType Directory $prereqsDir -ErrorAction SilentlyContinue | Out-Null
# move msys/mingw to qubes-builder/cache/windows-prereqs, this will be the default "clean" environment
# copy instead of move, sometimes windows defender locks executables for a while
Copy-Item -Path $msysDir -Destination $prereqsDir -Recurse
Copy-Item -Path $7zip -Destination $prereqsDir
# update msys path
$msysDir = Join-Path $prereqsDir "msys"

if ($verify)
{
	# install gpg if needed
	$gpgRegistryPath = "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\GnuPG"
	$gpgInstalled = Test-Path $gpgRegistryPath
	if ($gpgInstalled)
	{
		$gpgDir = (Get-ItemProperty $gpgRegistryPath).InstallLocation
		$gpgBinDir = Join-Path $gpgDir "bin"
		$gpg = Join-Path $gpgBinDir "gpg.exe"
		# additional sanity check
		if (!(Test-Path $gpg))
		{
			$gpgInstalled = $false
		}
	}

	if ($gpgInstalled)
	{
		Write-Host "[*] GnuPG is already installed."
	}
	else
	{
		$pkgName = "GnuPG"
		$url = "https://files.gpg4win.org/gpg4win-3.1.7.exe"
		$file = DownloadFile $url
		VerifyFile $file "ba2c4ac4cf9a44e19611f86ece4bafa71a5ef02553a1652a73b9037c74608b69"
		
		Write-Host "[*] Installing GnuPG..."
		$gpgDir = Join-Path $prereqsDir "gpg"
		$gpgBinDir = Join-Path $gpgDir "pub"
		Start-Process -FilePath $file -Wait -PassThru -ArgumentList @("/S", "/D=$gpgDir") | Out-Null
		$gpg = Join-Path $gpgBinDir "gpg.exe"
	}

	Set-Location $builderDir

	Write-Host "[*] Importing Qubes OS signing keys..."
	# import master qubes signing key
	& $gpg --keyserver hkp://keys.gnupg.net --recv-keys 0x36879494

	# import other dev keys
	$file = Join-Path $builderDir "qubes-developers-keys.asc"
	& $gpg --import $file

	# add gpg and msys to PATH
	$env:Path = "$env:Path;$msysDir\usr\bin;$gpgBinDir"

	# verify qubes-builder tags
	$tag = & git tag --points-at=HEAD | head -n 1
	$ret = & git tag -v $tag
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
# set msys to start in qubes-builder directory
$builderUnix = PathToUnix $builderDir
$cmd = "cd $builderUnix"
Add-Content (Join-Path $msysDir "etc\profile") "`n$cmd"
# mingw/bin is in default msys' PATH

# add msys shortcuts to desktop/start menu
Write-Host "[*] Adding shortcuts to msys..."
CreateShortcuts "qubes-msys.lnk" "$msysDir\msys.bat"

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
# start msys shell
Start-Process -FilePath (Join-Path $msysDir "msys.bat")

Stop-Transcript
