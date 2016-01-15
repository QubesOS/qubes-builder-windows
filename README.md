Preparing Windows build environment
===================================

Currently (Qubes R3) all Windows Tools code is built using Visual Studio 2013 and WDK 8.1. Builder machine should run Windows 7 64-bit (other OS versions weren't tested). Prerequisites take a lot of space so 30-40 GB for HDD is recommended.
Builder scripts take care of getting/installing almost all needed prerequisites but some things need to be done by hand:

1. Install Service Pack 1 for Windows 7. Without it Visual Studio won't install.
2. Install Visual Studio 2013 Community [1]. Deselect all optional components. Install in a path without spaces or suffer frustration with makefiles. VS requires .NET Framework 4.5 but I think the setup includes that.
3. Install Windows Driver Kit 8.1 [2].

And that's it. The builder will prepare the rest of the environment during the first build.

See windows-tools.conf for an example builder config.

[1] https://www.visualstudio.com/en-us/products/visual-studio-community-vs.aspx

[2] https://www.microsoft.com/en-us/download/details.aspx?id=42273
