My interest is in bare-metal programming for the Olimex AgonLight2. To do this efficiently, I want to have an edit-assemble-download-run toolchain that is very fast and needs few keystrokes to operate. I now have what I believe is exactly that.

For programming, the (free) Notepad++ source code editor for Microsoft Windows is unsurpassed. It does proper highlighting for Z80 assembly code, and has extremely powerful search and replace functions that work even when the source code is contained in multiple files. If you double-click on a word, it will show every occrrence of that the word (or partial word) in your source file (or files). You can also compare two pieces of source code side-by-side in a split window.

For assembly I now use the (free) Zilog Developer Studio II 5.35 exclusively. It initially looks very daunting to use, with a steep learning curve, but I eventually found how to use it very efficiently. It takes less than 2 minutes to create a new assembly project, and assembling the code to produce an Intel32 hex file only requires a single keystroke: just press F7. I've written up a step-by-step how-to document for using ZDS II. It's posted in this repository.

Notepad++ and ZDS II work together to provide a very powerful duo for finding and correcting errors in your assembly code. You can edit and correct your code in either Notepad++ or ZDS II, and any changes you make in Notepad appear in ZDS II and vice-versa. When you assemble your code, any errors are flagged in ZDS II's output window, and clicking on an error message jumps you instantly to the line in your source code where the error occurred.

When you're writing code, you will likely want a convenient reference to the eZ80 instruction set. The most convenient source I've found is Zilog's eZ80 CPU User Manual (readily available on-line). Go to the index of that document, click on an instruction, and it immediately jumps to the full description for that instruction.

Everything except the hex file donwnload is done on a laptop. The best way way to get the hex file onto the AgonLight2 is via UART1. Get a USB to TTL Serial 3.3V UART Converter Cable that uses an FTDI chip and has 2.45mm Dupont Headers on each wire.  These are readily available from Amazon for about $15. Make sure it uses 3.3V TTL, NOT 5V TTL. You only need to hoop up 3 wires to the pins of the Agon's GPIO header. The connections are:
	Adapter TxD --- Agon GPIO_PC1 (pin 18)  This is the receive data (RxD) pin for UART1
	Adapter RxD --- Agon GPIO_PC0 (pin 17)  This is thetransmit data (TxD) pin for UART
  Adapter GND --- Agon GPIO Ground (GND)  Either pin 3 or pin 5 can be used.
NOTE: I beleive the non-Olimex version of the Agon has a different pinout on the header.

With this cable in place, you can use Jeroen Venema's HEXLOAD utility to download the hex file to the AgonLight2 and convert it to a binary executable file. I have found that the best way to use HEXLOAD is to run the (free) TeraTerm program on your PC. Bring it up and select "File-->Send file..."  This brings up a dialog box where you can select any file you want and send it out the serial port that your USB adapter is connected to. By default, HEXLOAD uses 57600 baud for the data rate.
