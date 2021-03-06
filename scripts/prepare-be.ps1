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

# Qubes builder - preparing Windows build environment

# This script is called from Makefile.windows dist-prepare-chroot target.
# Administrator rights shouldn't be required as long as installed MSIs support that (python msi does).

# TODO: Most of this is only needed for libvirt. This script should be modularized and be component-specific.

$chrootDir = $env:CHROOT_DIR
$component = $env:COMPONENT
Write-Host "`n[*] >>> Preparing windows build environment for $component..."

# check if it's already done
$markerPath = "$chrootDir\.be-prepared"
if (Test-Path $markerPath)
{
    Write-Host "[*] BE already prepared"
    Exit 0
}

$verbose = $env:VERBOSE -ne 0

$builderDir = Join-Path "$chrootDir" ".." -Resolve # normalize path
$builderPluginDir = $env:WINDOWS_PLUGIN_DIR
$depsDir = [System.IO.Path]::GetFullPath("$chrootDir\build-deps")

$scriptDir = "$builderPluginDir\scripts"
$prereqsDir = "$builderDir\cache\windows-prereqs"  # place for downloaded installers/packages, they'll get copied/installed to proper chroots during the build process
$logDir = "$builderDir\build-logs"
$msiToolsDir = "$scriptDir\msi-tools"
$installedMsisFile = "$scriptDir\installed-msis" # guids/names of installed MSIs so we can easily uninstall them later (clean-be.ps1)

$global:pkgConf = @{}

# log everything from this script
$Host.UI.RawUI.BufferSize.Width = 500
Start-Transcript -Path "$logDir\win-prepare-be.log"

# create dirs
if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory | Out-Null }
if (-not (Test-Path $prereqsDir)) { New-Item $prereqsDir -ItemType Directory | Out-Null }
if (-not (Test-Path $depsDir)) { New-Item $depsDir -ItemType Directory | Out-Null }

Write-Host "[*] Downloaded prerequisites dir: $prereqsDir"
Write-Host "[*] Prerequisites dir in chroot: $depsDir"
Write-Host "[*] Log dir: $logDir"

Function FatalExit()
{
    Exit 1
}

Filter OutVerbose()
{
    if ($verbose) { $_ | Out-Host }
}

# downloads to $prereqsDir (installers, zipped packages etc)
Function DownloadFile($url, $fileName)
{
    $uri = [System.Uri] $url
    if ($fileName -eq $null)  { $fileName = $uri.Segments[$uri.Segments.Count-1] } # get file name from URL 
    $fullPath = "$prereqsDir\$fileName"
    Write-Host "[*] Downloading $pkgName..."

    if (Test-Path $fullPath)
    {
        Write-Host "[=] Already downloaded"
        return $fullPath
    }
    
    try
    {
	    $client = New-Object System.Net.WebClient
	    $client.DownloadFile($url, $fullPath)
        $client.Dispose()
    }
    catch [Exception]
    {
        Write-Host "[!] Failed to download ${url}:" $_.Exception.Message
        FatalExit
    }
    
    Write-Host "[=] Downloaded: $fullPath"
    return $fullPath
}

function GetHash($filePath)
{
    $fs = New-Object System.IO.FileStream $filePath, "Open"
	$sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = [BitConverter]::ToString($sha1.ComputeHash($fs)).Replace("-", "")
    $fs.Close()
    return $hash.ToLowerInvariant()
}

function VerifyFile($filePath, $hash)
{
    $fileHash = GetHash $filePath
    if ($fileHash -ne $hash)
    {
        Write-Host "[!] Failed to verify SHA-1 checksum of $filePath!"
        Write-Host "[!] Expected: $hash, actual: $fileHash"
        Exit 1
    }
    else
    {
        Write-Host "[=] File '$(Split-Path -Leaf $filePath)' successfully verified."
    }
}

Function InstallMsi($msiPath, $targetDirProperty, $targetDir)
{
    # copy msi to chroot
    $fileName = Split-Path -Leaf $msiPath
    $tmpMsiPath = Join-Path $chrootDir $fileName
    Copy-Item -Force $msiPath $tmpMsiPath

    Write-Host "[*] Installing $pkgName from $tmpMsiPath to $targetDir..."

    # patch the .msi with a temporary product/package GUID so it can be installed even if there is another copy in the system
    $tmpMsiGuid = "{$([guid]::NewGuid().Guid)}"

    # change product name (so it's easier to see in 'add/remove programs' what was installed by us)
    #$productName = "qubes-dep " + $pkgName + "/" + $component + " " + (Get-Date)

    & $msiToolsDir\msi-patch.exe "$tmpMsiPath" "$tmpMsiGuid" #"$productName"

    $log = "$logDir\install-$pkgName-$tmpMsiGuid.log"
    #Write-Host "[*] Install log: $log"

    # install patched msi
    $arg = @(
        "/qn",
        "/log `"$log`"",
        "/i `"$tmpMsiPath`"",
        "$targetDirProperty=`"$targetDir`""
        )

    $ret = (Start-Process -FilePath "msiexec" -ArgumentList $arg -Wait -PassThru).ExitCode
    
    if ($ret -ne 0)
    {
        Write-Host "[!] Install failed! Check the log at $log"
        FatalExit
    }
    else # success - store info for later uninstallation on cleanup
    {
        Add-Content $installedMsisFile "$tmpMsiGuid $pkgName"
        Write-Host "[=] Install successful."
    }
}

Function Unpack7z($archivePath, $log, $targetDir)
{
    $arg = "x", "-y", "-o$targetDir", $archivePath
    & $7zip $arg | Out-File $log
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

Function UnpackZip($archivePath, $targetDir)
{
    Write-Host "[*] Extracting $archivePath to $targetDir..."
    $shell = New-Object -com Shell.Application
    $zip = $shell.Namespace($archivePath)
    foreach($item in $zip.Items())
    {
        $shell.Namespace($targetDir).CopyHere($item)
    }
}

Function Unpack($archivePath, $targetDir)
{
    $log = "$logDir\extract-$pkgName.log"
    Write-Host "[*] Extracting $pkgName to $targetDir"

    switch -wildcard ((Get-Item $archivePath).Name)
    {
        "*.tar.*" 
        {
            UnpackTar7z $archivePath $log $targetDir
        }
        default { Unpack7z $archivePath $log $targetDir } # .7z or .zip are fine
    }
}

Function PathToUnix($path)
{
    # converts windows path to msys2 path
    $path = $path.Replace('\', '/')
    $path = $path -replace '^([a-zA-Z]):', '/$1'
    return $path
}

Function ReadPackages($confPath)
{
    $conf = Get-Content $confPath
    Write-Host "[*] Reading dependency list from $confPath..."
    foreach ($line in $conf)
    {
        if ($line.Trim().StartsWith("#")) { continue }
        $line = $line.Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        $tokens = $line.Split(',')
        $key = $tokens[0].Trim()
        $hash = $tokens[1].Trim()
        $url = $tokens[2].Trim()
        $fileName = $null
        if ($tokens.Count -eq 4) # there is a file name
        {
            $fileName = $tokens[3].Trim()
        }
        # store entry in the dictionary
        $global:pkgConf[$key] = @($url, $hash, $fileName) # third field is local file name, set when downloading
    }
    $count = $global:pkgConf.Count
    Write-Host "[*] $count entries"
}

Function DownloadAll()
{
    Write-Host "[*] Downloading windows dependencies to $prereqsDir..."
    $keys = $global:pkgConf.Clone().Keys # making a copy because we're changing the collection inside the loop
    foreach ($pkgName in $keys)
    {
        $val = $global:pkgConf[$pkgName] # array
        $url = $val[0]
        $hash = $val[1]
        $path = $val[2] # may be null
        $path = DownloadFile $url $path
        $val[2] = $path
        $global:pkgConf[$pkgName] = $val # update entry with local file path
        VerifyFile $path $hash
    }
}

# compile msi tools
if (!(Test-Path "$msiToolsDir\msi-patch.exe") -or !(Test-Path "$msiToolsDir\msi-interop.dll"))
{
    Write-Host "[*] Compiling msi tools..."
    $netDir = "$env:SystemRoot\Microsoft.NET\Framework\v2.0.50727"

    if (!(Test-Path $netDir))
    {
        Write-Host "[!] .NET Framework v2 not found!"
        Exit 1
    }

    $csc = "$netDir\csc.exe"

    Push-Location
    Set-Location $msiToolsDir
    & $csc /t:exe /out:tlb-convert.exe tlb-convert.cs | Out-Null
    & $msiToolsDir\tlb-convert.exe msi.dll msi-interop.dll WindowsInstaller | Out-Null
    & $csc /t:exe /out:msi-patch.exe /r:msi-interop.dll msi-patch.cs | Out-Null
    Pop-Location
    
    Write-Host "[=] Done."
}

# download all dependencies
ReadPackages "$scriptDir\win-be-deps.conf"
DownloadAll

# delete existing stuff
Write-Host "[*] Clearing $depsDir..."
Remove-Item $depsDir\* -Recurse -Force -Exclude ("include", "libs")

Write-Host "`n[*] Processing dependencies..."

# 7zip should be prepared by get-be script
$7zip = "$prereqsDir\7za.exe"

# if not, get it
if (!(Test-Path $7zip))
{
    $pkgName = "7zip"
    $file = $global:pkgConf[$pkgName][2]
    UnpackZip $file $prereqsDir
}

$pkgName = "msys2"
$file = $global:pkgConf[$pkgName][2]
Unpack $file $depsDir
$msysBin = "$depsDir\msys64\usr\bin"

$pkgName = "python27"
$file = $global:pkgConf[$pkgName][2]
$pythonDir = "$depsDir\python27"
InstallMsi $file "TARGETDIR" "$pythonDir"
$python = "$pythonDir\python.exe"

# add binaries to PATH
$env:Path = "$msysBin;$pythonDir;$depsDir\wix\bin;$env:Path"

$pkgName = "wix"
$file = $global:pkgConf[$pkgName][2]
Unpack $file "$depsDir\wix"

$pkgName = "python34"
$file = $global:pkgConf[$pkgName][2]
$python3Dir = "$depsDir\python34"
InstallMsi $file "TARGETDIR" "$python3Dir"
$python3 = "$python3Dir\python.exe"

# write PATH to be passed back to make
# convert to unix form
$pathDirs = $env:Path.Split(';')
$unixPath = ""
foreach ($dir in $pathDirs)
{
    $dir = $dir.Replace("%SystemRoot%", $env:windir)
    if ($unixPath -eq "") { $unixPath = (PathToUnix $dir) }
    else { $unixPath = $unixPath + ":" + (PathToUnix $dir) }
}

# mark chroot as prepared to not repeat everything on next build
# save python path and modified search path
$pythonUnix = PathToUnix $pythonDir
Set-Content -Path $markerPath "`n$pythonUnix`n$unixPath`n$depsDir\wix`n$python3"

Write-Host "[=] Windows build environment prepared`n"
