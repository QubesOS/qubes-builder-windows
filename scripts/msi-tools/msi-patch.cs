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
using System.IO;
using System.Runtime.InteropServices;
using WindowsInstaller;

// This utility patches a MSI installer package to use new product GUID.
// Reference msi.dll COM wrapper DLL when compiling.

namespace Qubes.BuildTools
{
    static class MsiPatch
    {
        static int Main(string[] args)
        {
            if (args.Length < 2)
            {
                Console.WriteLine("Usage: msi-patch <msi path> <new GUID (braced form)> [product name]");
                return 2;
            }

            string path = Path.GetFullPath(args[0]);
            string guid = args[1];

            // check if the guid is valid
            try
            {
                Guid g = new Guid(guid);
            }
            catch (FormatException)
            {
                Console.WriteLine("Invalid GUID: {0}", guid);
                return 1;
            }

            // check if it's braced
            if (guid[0] != '{' || guid[guid.Length - 1] != '}')
            {
                Console.WriteLine("GUID must be in braced form (ex. {17201106-ae02-44f1-8d2d-d075a6e5c039})!");
                return 1;
            }

            try
            {
                Type t = Type.GetTypeFromProgID("WindowsInstaller.Installer");
                Installer msi = (Installer)Activator.CreateInstance(t); // instantiate WI COM object
                Database db = msi.OpenDatabase(path, MsiOpenDatabaseMode.msiOpenDatabaseModeTransact); // transact mode, we're making changes

                // update summary info
                SummaryInfo summary = db.get_SummaryInformation(1);
                summary.set_Property(9, guid); // 9 is the product GUID
                summary.Persist();

                // update properties
                string sql = string.Format("UPDATE Property SET Value='{0}' WHERE Property='ProductCode'", guid);
                View view = db.OpenView(sql);
                view.Execute(null);
                view.Close();

                sql = string.Format("UPDATE Property SET Value='{0}' WHERE Property='UpgradeCode'", guid);
                view = db.OpenView(sql);
                view.Execute(null);
                view.Close();

                if (args.Length == 3) // product name
                {
                    sql = string.Format("UPDATE Property SET Value='{0}' WHERE Property='ProductName'", args[2]);
                    view = db.OpenView(sql);
                    view.Execute(null);
                    view.Close();
                }

                db.Commit();
                Marshal.ReleaseComObject(msi);
            }
            catch (Exception e)
            {
                Console.WriteLine("Exception: {0}\n{1}", e.Message, e.StackTrace);
                return 1;
            }
            return 0;
        }
    }
}
