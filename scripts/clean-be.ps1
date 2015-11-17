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

# This script uninstalls all MSIs that were installed by prepare-be.
# It should be called from 'clean' target during make process, before deleting chroot.

$scriptDir = Split-Path -parent $MyInvocation.MyCommand.Definition
$builderDir = Join-Path $scriptDir ".." -Resolve
$logDir = "$builderDir\build-logs"
$installedMsisFile = "$builderDir\scripts-windows\installed-msis" # guids/names of installed MSIs

Function UninstallMsi($guid, $name)
{
    Write-Host "[*] Uninstalling $name ($guid)..."
    $log = "$logDir\uninstall-$name-$guid.log"
    $arg = @(
        "/qn",
        "/log `"$log`"",
        "/x `"$guid`""
        )

    $ret = (Start-Process -FilePath "msiexec" -ArgumentList $arg -Wait -PassThru).ExitCode
    if ($ret -ne 0)
    {
        Write-Host "[!] Uninstall failed! Check the log at $log"
    }
    else
    {
        Write-Host "[=] $name ($guid) successfully uninstalled."
    }
}

### start

Write-Host "[*] Cleanup: uninstalling dependencies..."

if (Test-Path $installedMsisFile)
{
    $file = Get-Content $installedMsisFile
    foreach ($line in $file)
    {
        if ($line.Trim().StartsWith("#")) { continue }
        $line = $line.Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        $tokens = $line.Split(' ')
        $guid = $tokens[0].Trim()
        $name = $tokens[1].Trim()
        UninstallMsi $guid $name
    }

    Move-Item $installedMsisFile "$installedMsisFile.old" -Force
}
else
{
    Write-Host "[*] Nothing to clean."
}

Write-Host "[=] Done uninstalling."
