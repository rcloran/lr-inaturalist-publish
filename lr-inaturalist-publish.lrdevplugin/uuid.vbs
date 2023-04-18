for i = 1 to 10
  set obj = CreateObject("Scriptlet.TypeLib")
  WScript.StdOut.WriteLine Mid(obj.GUID, 2, 36)
next
