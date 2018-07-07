Preparing the Windows build environment
=======================================

Currently (Qubes R3) all Windows Tools code is built using Visual Studio 2013 and WDK 8.1. Builder machine should run Windows 7 64-bit (other OS versions weren't tested). Prerequisites take a lot of space so 30-40 GB for HDD is recommended.
Builder scripts take care of getting/installing almost all needed prerequisites but some things need to be done by hand:

1. Install Service Pack 1 for Windows 7. Without it Visual Studio won't install.
2. Install Visual Studio 2017 Community [1]. Deselect all optional components. Install in a path without spaces or suffer frustration with makefiles. VS requires .NET Framework 4.5 but I think the setup includes that.
3. Install Windows Driver Kit 10 [2].

Manual environment setup
------------------------

You need to manually install:

 * Python3 (select to add it to system path)
 * Wix toolset
 * msys2
 * additional packages in msys2 environment, call: pacman -S git make p7zip diffutils tar
 * create `qubes-builder/chroot-win7x64/.be-prepared` file with 4th line being a path to wix installation and 5th line being a path to python3. Both paths needs to be msys2-encoded. First 3 lines are ignored. For example:

```
dummy1-mingw
dummy2-python-dir
dummy3-win-path
/e/qubes-builder/chroot-win7x64/build-deps/wix
/c/windows/py
```

Then proceed with standard way of obtaining qubes builder: https://www.qubes-os.org/doc/qubes-builder

Automated environment setup
---------------------------

*Note*: the get-be.ps1 script is currently broken (not updated for msys2).

If you're starting in a clean OS without Qubes Builder, the get-be powershell script initializes the build environment. Download it from here:

https://raw.githubusercontent.com/QubesOS/qubes-builder-windows/master/scripts/get-be.ps1

...and run:
`powershell -ExecutionPolicy bypass -f get-be.ps1`

The script:

* Prepares msys/mingw environment
* Clones qubes-builder
* Installs GPG and verifies code signatures
* Adds a msys shell shortcut to the start menu
* Generates a code signing certificate for Windows binaries (necessary for drivers). Use no password for testing.

Building Qubes Windows Tools
============================

Before building, prepare the appropriate `builder.conf` in the root of qubes-builder. Example config is provided as `windows-tools.conf`.
From the newly launched msys shell run:

* `make get-sources`
* `make qubes`

The finished installer will be in `qubes-src\installer-qubes-os-windows-tools`.

[1] https://www.visualstudio.com/en-us/products/visual-studio-community-vs.aspx

[2] https://www.microsoft.com/en-us/download/details.aspx?id=42273
