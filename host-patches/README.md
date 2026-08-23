# OpenComputers Remote Terminal touch fix

GTNH OpenComputers 1.12.44 through 1.12.55 reject Remote Terminal mouse packets
when the player is more than eight blocks from the Terminal Server rack. Keyboard
packets already use the held terminal's pairing key and remain usable at range.
The server rejects the mouse packet before any Lua signal exists, so an operating
system cannot repair this behavior.

This directory contains the auditable source patch and tested 1.12.48 replacement
JAR:

`OpenComputers-1.12.48-GTNH-terminal-touch-fix.jar`

Its SHA-256 is
`1D69AF472EDD42F7BCC4067CBD130415EEAC4BF045FECB8C6A450FF7FB762CD5`.

## Install in the local GTNH 2.9.b2 instance

1. Fully close GTNH.
2. Back up `OpenComputers-1.12.48-GTNH.jar` from the instance's `mods` folder.
3. Replace it with the patched JAR and name the replacement
   `OpenComputers-1.12.48-GTNH.jar`.
4. Restart Minecraft, open the paired Remote Terminal, and click a PlasmaOS
   window. In PlasmaOS, `remote` should now show an increasing touch count.

For a dedicated server, install the patched JAR on the server. Installing the
same JAR on clients is recommended so the pack stays byte-for-byte consistent.

The patch only bypasses rack distance for a player holding a Remote Terminal
whose key is paired to that Terminal Server. Physical screens and unpaired
terminals retain the normal reach check.
