Machine Language Monitor for the RC2014
=======================================

Inspired by the monitor in an old Intel kit (http://oldcomputers.net/intel-mcs-85.html)
and MSDOS debug program.

In the long run support is planned for the following comands:

* A assembly
* C compare
* D dump
* E enter
* F fill
* G go
* I input
* L load (1)
* M move
* O output
* S search
* U unassemble
* W write (1)

(1) load and write will use the XModem protocol to receive and send files from a PC


Status at 25 march 2017
------------------------

Basic command + load/write working!


C addr1 len addr2

Compare len bytes from addr1 to len bytes from addr2 and prints the differences


D [[start] len]

Display len bytes from start. If len not given, assumes 128, if start not given,
continues from last enter/display.


E [start]

Enter bytes starting at start. If start is not given, continues form last enter/display.
The current value is shown, type in new value and press space for the next byte
or enter to end the command. If you just press space or enter the current value
is not changed.


F start len value

Fills len bytes starting from start with the given value.


G addr

Start executing code at the given address.


I port

Shows the content of an I/O port.


L start

Receives bytes using Xmodem BCC and write to memory starting at start.


M orig len dest

Moves len bytes from orig to dest. Works with overlapping ranges.


O port value

Writes value to an I/O port


W start len

Send len bytes from start using Xmodem BCC. len will be padded to be a
multiple of 128.



