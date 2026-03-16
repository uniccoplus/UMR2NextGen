# UMR2: NextGen

## Introduction

***Universal MIDI Retrofit Version 2 (UMR2), created by John Staskevich in 2017,***<br>
***was becoming an "ancient relic" that many had forgotten over time.***<br>
<br>
<br>
<br>
_This project was plagued by several "curses" that deterred modern engineers._<br>
<br>
<br>
1. Isolated and Unsupported: There was no one to carry on the support, and the technical threads were severed.
2. Lost Language: The source code existed, but it was written in "assembler," a language that few people could master.
3. Incomplete Blueprint: While the board data existed, the "circuit diagram" showing the logic was missing.
4. Severe Constraints: Because it was based on the most feature-rich device in the PIC16F series at the time, porting it to other devices was extremely difficult.
<br>
<br>

_Time has passed, and nearly 10 years have gone by._\
_In a world where almost no one pays attention to UMR2, a single elderly Japanese man quietly rose to the challenge._\
_Using his "***ninjutsu***" (deep experience and knowledge), he deciphered its complex assembler code and performed the forbidden technique of rewriting it for a modern device._\
_This is the code resurrected in the modern age through that "***ninja technique.***"_


## Porting Details
Target Device: Microchip PIC16F18877-I/P (DIP-40Pin)<br>
<br>
The soul of the UMR2 has been transferred from a 9-year-old multi-function device to a more readily available DIP package with modern features (CIP/PPS, etc.).<br>
<br>
Porter: _uniccoplus_ [https://bakutalab.blogspot.com/](https://bakutalab.blogspot.com/)<br>
<br>
Status: Operates in a modern environment in 2026.<br>
<br>
## Hardware Details
There are basically ***no changes***.<br>
After considering which MPU to port the code to, I discovered that the PIC16F18877 is compatible with all pins, which prompted me to restart this project. In other words, the information found online can be used with simple modifications.<br>
The lack of a publicly available circuit diagram is a major reason why I don't want to make significant hardware changes.<br>
Should I draw the circuit diagram? That's possible, but I don't want to waste time on it.<br>
I've decided that a complete software port is more important.<br>
Yes, the software is the more difficult part.<br>
My apologies. I forgot. There is some room for improvement in the resistance values. It's not important, so it will work as is.<br>
<br>
## License
Original Work Copyright John Staskevich, 2017<br>
Porting Work by uniccoplus, 2026<br>
<br>
This work is licensed under a Creative Commons Attribution 4.0 International License.<br>
[http://creativecommons.org/licenses/by/4.0/](http://creativecommons.org/licenses/by/4.0/)<br>


Original Hardware/Firmware Information (as of 2017)
PCB: Eagle 6 board layout (pcb/folder).
Original MCU: PIC16F1939.
Toolchain: Microchip MPASM.

