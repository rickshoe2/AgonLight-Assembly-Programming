
My primary interest is in bare-metal programming for the Olimex AgonLight2. To do this efficiently, I needed to have an edit-assemble-download-run toolchain for PCs running Microsoft Windows that is very fast and needs few keystrokes to operate. I now have what I believe is exactly that.
The toolchain consists of four (free to download and use) programs:

    eZapple
    Tera Term
    Notepad++
    Zilog Developer Studio II

eZapple is my machine language monitor program that runs in 24-bit ADL mode on the AgonLight. Old-timers (like me) will recognize the name “eZapple” and many of it's single-letter commands as deriving from Technical Design Labs famous Zapple monitor. In fact, eZapple is an enhanced 24-bit version of my own extensively modified Zapple monitor that I run on an original Imsai 8080 system. Look at the "eZapple Machine Language Monitor" and "eZapple Command Synopsis and Usage" documents in this repository to get an idea of its capabilities.

The primary purpose of eZapple is to provide a way to debug programs while they are running on the Agon. This is done with the GOTO ('G') command. When you enter 'G<program start address>,<breakpoint address>' the program will execute up to the breakpoint, halt, display the contents of all registers, and return to the eZapple prompt. When the program stops at the breakpoint, you can examine and modify memory using the DISPLAY and CHANGE commands, or even change the program's code or the register contents (this is dangerous but doable!). Then you can resume execution again from that breakpoint to another breakpoint where the eZ80 will again halt and display the registers. By doing this repeatedly, you can single step through your program if you wish.

In addition, eZapple's HEXLOAD command will load a Hex file from the PC into the Agon's memory (converting it into a binary file as it runs), and the XMODEM command will load any type of file from the PC into the Agon's memory using the Xmodem protocol. The SAVE and LOAD commands then allow files to be saved or loaded to/from the Agon's SD card.

I use the (free) Tera Term program as my serial terminal because it works quickly and seamlessly with the HEXLOAD and XMODEM commands to get files onto the Agon.

To use eZapple, you need to connect your PC to the AgonLight using a USB to TTL Serial 3.3V UART Converter Cable. These are readily available from Amazon for about $15.  I use a DSD TECH SH-U09G USB to TTL Serial Cable, which works well. Make sure the cable uses 3.3V TTL, NOT 5V TTL, contains a genuine FTDI chip, and has little 2.45mm pin headers on each wire. You only need to hook up 3 wires to the pins of the AgonLight's GPIO header. The connections are:

    Adapter TxD --- Agon GPIO_PC1 (pin 18) This is the receive data (RxD) pin for UART1
    Adapter RxD --- Agon GPIO_PC0 (pin 17) This is the transmit data (TxD) pin for UART1
    Adapter GND --- Agon GPIO Ground (GND) Either pin 3 or pin 5 can be used.
NOTE: Agon versions other than the AgonLight2 may have a different pinout on the header. See  https://agonconsole8.github.io/agon-docs/GPIO/

For programming, the (free) Notepad++ programmer’s editor is unsurpassed. If you open a .asm file in Notepad++, it will properly color code the eZ80’s assembly language, making it much easier to read. It also has extremely powerful search and replace functions that work even when the source code is contained in multiple files. If you double-click on a word, it can show every occurrence of that word (or partial word) in all the files contained in a specified directory. Many programs for the AgonLight have the source code available, but the code is spread out over many files (for example, the MOS source code). The Find in Files search function of Notepad++ is essential if you want to see how these programs work, and perhaps reuse some bits of that code in your own programs. In addition, you can compare two pieces of source code side-by-side in a split window and cut-and-paste code snippets between them. If you select a word or a section of text and right-click on it you can cut, copy, paste or delete it; convert uppercase text to lowercase and vice-versa; or comment/uncomment a block of code.
Notepad++ works seamlessly with Zilog Developer Studio II. If you have a file open in ZDS II and in Notepad++, any changes made to the file in either of the programs will be reflected in the other (provided you type a Ctrl-s to save the newly changed file).

For assembly I now use the (free) Zilog Developer Studio II 5.35 exclusively. It initially looks very daunting to use, but I eventually found how to use it very efficiently. It takes less than 2 minutes to create a new assembly project, and assembling the code to produce an Intel32 hex file only requires a single keystroke:  press F7. I've written a step-by-step how-to document for creating a new project using ZDS II (see “Creating a New Project for Zilog Developer Studio II” in this repository).



Notepad++ and ZDS II work seamlessly together to provide a very powerful duo for finding and correcting errors in your assembly code. You can edit and correct your code in either Notepad++ or ZDS II, and any changes you make in Notepad++ appear in ZDS II and vice-versa. When you assemble your code, any errors are flagged in ZDS II's output window, and clicking on an error message jumps you instantly to the line in your source code where the error occurred.


