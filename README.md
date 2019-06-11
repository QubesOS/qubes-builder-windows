Preparing the Windows build environment
=======================================

Currently (Qubes R3) all Windows Tools code is built using Visual Studio 2013 and WDK 8.1. Builder machine should run Windows 7 64-bit (other OS versions weren't tested). Prerequisites take a lot of space so 30-40 GB for HDD is recommended.
Builder scripts take care of getting/installing almost all needed prerequisites but some things need to be done by hand:

1. Install Service Pack 1 for Windows 7. Without it Visual Studio won't install.
2. Install Visual Studio 2017 Community [1]. Choose "Desktop development with C++" workload. Deselect all optional components. VS requires .NET Framework 4.5 but I think the setup includes that.
3. Install Windows Driver Kit 10 [2].
4. If you **previously** installed GPG4Win, please update to the latest version before continuing [3].

If you're starting in a clean OS without Qubes Builder, the get-be powershell script initializes the build environment. Download it from here:

https://raw.githubusercontent.com/QubesOS/qubes-builder-windows/master/scripts/get-be.ps1

...and run:
`powershell -ExecutionPolicy bypass -f get-be.ps1`

The script:

* Prepares msys2 environment
* Clones qubes-builder
* Installs GPG4Win and verifies code signatures
* Adds a qubes-msys2 shell shortcut to the start menu and desktop
* Generates a code signing certificate for Windows binaries (necessary for drivers). Use no password for testing.

The first time qubes-msy2 runs, it will perform some initial setup and requires a restart. After restarting msys2, install the following required packages:

`pacman -S diffutils git make patchutils`

Building Qubes Windows Tools
============================

Before building, prepare the appropriate `builder.conf` in the root of qubes-builder. Example config is provided as `windows-tools.conf`. Note particularly the following settings:

* **DIST_DOM0, DISTS_VM**: win7x64, win10x64, etc.
* **VS_PATH**: this path should be free of spaces, but there is a trick. You can convert the full path to a "short" DOS-style path using a Windows command prompt or batch file like this:

    ```
    for %A in ("C:\Program Files (x86)\Microsoft Visual Studio\2017\Community") do @echo %~sA

    Result: C:\PROGRA~2\MIB055~1\2017\COMMUN~1
    ```
        
* **WIN_CERT_FILENAME, WIN_CERT_PUBLIC_FILENAME**: full paths to `qubes-builder\qwt.pfx` and `qubes-builder\qwt.cer` created earlier by `get-be.ps1`.


From the newly launched msys2 shell run:

* `make get-sources`

This will download remaining dependencies and required QubesOS repos, verifying their signatures. However, it's necessary to download some additional submodules for vmm-xen-windows-pvdrivers:

```
cd qubes-src/vmm-xen-windows-pvdrivers
make get-sources
cd ../../
```

Finally, build the QWT installer:

`make qubes`

The finished installer will be in `qubes-src\installer-qubes-os-windows-tools`.

[1] https://www.visualstudio.com/en-us/products/visual-studio-community-vs.aspx

[2] https://www.microsoft.com/en-us/download/details.aspx?id=42273

[3] https://www.gpg4win.org/
