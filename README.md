# UMR2: NextGen

## Introduction

***Universal MIDI Retrofit Version 2 (UMR2), created by John Staskevich in 2017,***<br>
***was becoming an "ancient relic" that many had forgotten over time.***<br>



_This project was plagued by several "curses" that deterred modern engineers._


1. Isolated and Unsupported: There was no one to carry on the support, and the technical threads were severed.
2. Lost Language: The source code existed, but it was written in "assembler," a language that few people could master.
3. Incomplete Blueprint: While the board data existed, the "circuit diagram" showing the logic was missing.
4. Severe Constraints: Because it was based on the most feature-rich device in the PIC16F series at the time, porting it to other devices was extremely difficult.



_Time has passed, and nearly 10 years have gone by._<br>
_In a world where almost no one pays attention to UMR2, a single elderly Japanese man quietly rose to the challenge._<br>
_Using his "***ninjutsu***" (deep experience and knowledge), he deciphered its complex assembler code and performed the forbidden technique of rewriting it for a modern device._<br>
_This is the code resurrected in the modern age through that "***ninja technique.***"_<br>

## Porting Details
Target Device: Microchip PIC16F18877-I/P (DIP-40Pin)

The soul of the UMR2 has been transferred from a 9-year-old multi-function device to a more readily available DIP package with modern features (CIP/PPS, etc.).

Porter: _uniccoplus_ [https://bakutalab.blogspot.com/](https://bakutalab.blogspot.com/)

Status: Operates in a modern environment in 2026.

## License
Original Work Copyright John Staskevich, 2017
Porting Work by uniccoplus, 2026

This work is licensed under a Creative Commons Attribution 4.0 International License.
[http://creativecommons.org/licenses/by/4.0/](http://creativecommons.org/licenses/by/4.0/)


Original Hardware/Firmware Information (as of 2017)
PCB: Eagle 6 board layout (pcb/folder).
Original MCU: PIC16F1939.
Toolchain: Microchip MPASM.

