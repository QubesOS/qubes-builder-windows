/*
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
 */

using System;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.InteropServices;

// This utility extracts COM type library definition from unmanaged DLL and creates matching managed wrapper assembly.

namespace Qubes.BuildTools
{
    static class TlbConvert
    {
        private enum RegKind
        {
            RegKind_Default = 0,
            RegKind_Register = 1,
            RegKind_None = 2
        }

        [DllImport("oleaut32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void LoadTypeLibEx(String strTypeLibName, RegKind regKind,
            [MarshalAs(UnmanagedType.Interface)] out Object typeLib);

        static int Main(string[] args)
        {
            if (args.Length < 2)
            {
                Console.WriteLine("Usage: tlb-convert <unmanaged COM DLL path> <managed wrapper path> [root namespace]");
                return 2;
            }

            try
            {
                string srcDll = args[0];
                string outDll = args[1];
                string rootNamespace = args.Length == 3 ? args[2] : null;

                Object typeLib;
                LoadTypeLibEx(srcDll, RegKind.RegKind_None, out typeLib);
                TypeLibConverter tlbConv = new TypeLibConverter();
                AssemblyBuilder asm = tlbConv.ConvertTypeLibToAssembly(typeLib, outDll, 0, new ConversionEventHandler(), null, null, rootNamespace, null);
                asm.Save(outDll);
            }
            catch (Exception e)
            {
                Console.WriteLine("Exception: {0}\n{1}", e.Message, e.StackTrace);
                return 1;
            }

            Console.WriteLine("\nConversion successful.");
            return 0;
        }
    }

    public class ConversionEventHandler : ITypeLibImporterNotifySink
    {
        public void ReportEvent(ImporterEventKind eventKind, int eventCode, string eventMsg)
        {
            Console.WriteLine("{0}", eventMsg);
        }

        public Assembly ResolveRef(object typeLib)
        {
            return null;
        }
    }
}
