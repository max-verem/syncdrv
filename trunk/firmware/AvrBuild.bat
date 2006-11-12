@ECHO OFF
del "c:\projects\syncdrv\firmware\syncdrv.map"
del "c:\projects\syncdrv\firmware\labels.tmp"
"C:\Program Files\Atmel\AVR Tools\AvrAssembler2\avrasm2.exe" -S "c:\projects\syncdrv\firmware\labels.tmp" -fI  -o "c:\projects\syncdrv\firmware\syncdrv.hex" -d "c:\projects\syncdrv\firmware\syncdrv.obj" -e "c:\projects\syncdrv\firmware\syncdrv.eep" -m "c:\projects\syncdrv\firmware\syncdrv.map" -W+ie   "C:\projects\syncdrv\firmware\syncdrv.asm"
