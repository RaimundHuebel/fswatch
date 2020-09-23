# Modul fürs Auflisten von System-Informationen über den aktuellen Rechner.
#
# see_also:
#   - https://nim-lang.org/docs/os.html
#
# compile and run + tooling:
#
#   ## Seperated compile and run steps ...
#   $ nim compile [--out:system_info.exe] system_info.nim
#   $ ./system_info[.exe]
#
#   ## In one step ...
#   $ nim compile [--out:system_info.exe] --run system_info.nim
#
#   ## Optimal-Compile ...
#   $ nim compile -d:release --opt:size system_info.nim
#   $ strip --strip-all system_info  #Funktioniert wirklich
#   $ upx --best system_info
#   $ ldd system_info               # Nur zur Info
#   $ -> sizeof(normal/upx+strip) = 65kB / 21kB
#
# author:
#   Raimund Hübel <raimund.huebel@googlemail.com>


## Modul fürs Auflisten von Informationen über den aktuellen Rechner.
##
## # Example
## .. code-block:: Nim
##   import system_info
##   ...



import os
import times
import strutils
import system
import cpuinfo
import oids
import posix



## Typ für System-Info.
type SystemInfo* = ref object



## Internes SystemInfo-Object
let sysInfo = SystemInfo()



proc systemInfo*() :SystemInfo =
    ## Liefert das SystemInfo-Objekt als Singleton.
    return sysInfo



proc hostname*(sysInfo :SystemInfo) :string =
    ## Liefert den Hostnamen des Systems
    ## @example "my-machine"
    const maxSize = 256
    result = newString(maxSize)
    if 0.cint != posix.gethostname(result, maxSize-1):
        raiseOSError(osLastError())
    result[maxSize-1] = 0.char
    let realSize = result.cstring.len
    result.setLen(realSize)
    return result


proc applicationFilePath*(sysInfo :SystemInfo) :string =
    ## Liefert den qualifizierten Pfad der aktuell ausgeführten Applikation.
    ## @example "/home/user/test.exe"
    return os.getAppFilename()


proc applicationDirectoryPath*(sysInfo :SystemInfo) :string =
    ## Liefert den qualifizierten Pfad zum Verzeichnis der aktuell ausgeführten Applikation.
    ## @example "/home/user"
    return os.getAppDir()


proc currentDirectoryPath*(sysInfo :SystemInfo) :string =
    ## Liefert den qualifizierten Pfad zum aktuellen Arbeits Verzeichnis
    ## @example "/home/user"
    return os.getCurrentDir()


proc userName*(sysInfo :SystemInfo) :string =
    ## Liefert den Namen des Nutzers, der die Applikation ausführt.
    ## @example "user"
    #return os.getEnv("USERNAME")
    return $posix.getlogin()


proc userHomeDirectoryPath*(sysInfo :SystemInfo) :string =
    ## Liefert den qualifizierten Pfad zum Home-Verzeichnis des akt. Users.
    ## @example "/home/user/"
    return os.getHomeDir()


proc userConfigDirectoryPath*(sysInfo :SystemInfo) :string =
    ## Liefert den qualifizierten Pfad zum Config-Verzeichnis des akt. Users.
    ## @example "/home/user/.config/"
    return os.getConfigDir()


proc systemTempDirectoryPath*(sysInfo :SystemInfo) :string =
    ## Liefert den qualifizierten Pfad zum Config-Verzeichnis des akt. Users.
    ## @example "/tmp/"
    return os.getTempDir()


proc systemHostOS*(sysInfo :SystemInfo) :string =
    ## Liefert den Namen des Host-OS, des akt. Systems.
    ## @example "linux"
    return system.hostOS


proc systemHostCPU*(sysInfo :SystemInfo) :string =
    ## Liefert den Namen der Host-CPU, des akt. Systems.
    ## @example "amd64"
    return system.hostCPU


proc systemCountProcessors*(sysInfo :SystemInfo) :int =
    ## Liefert die Anzahl der Prozessoren, des akt. Systems.
    ## @example 4
    return cpuinfo.countProcessors()



proc toString*(sysInfo :SystemInfo) :string =
    ## Liefert die System-Informationen als yml-String.
    var resultStr =
            "System:" &
            "\n  - OID: " & ($oids.genOid()).escape()

    resultStr =
            resultStr &
            "\n  - Info:" &
            "\n    - CurrTime:    " & (times.getDateStr() & " " & times.getClockStr()).escape &
            "\n    - AppFile:     " & sysInfo.applicationFilePath().escape &
            "\n    - AppDir:      " & sysInfo.applicationDirectoryPath().escape &
            "\n    - WorkingDir:  " & sysInfo.currentDirectoryPath().escape &
            "\n    - HomeDir:     " & sysInfo.userHomeDirectoryPath().escape &
            "\n    - ConfigDir:   " & sysInfo.userConfigDirectoryPath().escape &
            "\n    - TempDir:     " & sysInfo.systemTempDirectoryPath().escape &
            "\n    - HostOS:      " & sysInfo.systemHostOS().escape &
            "\n    - HostCPU:     " & sysInfo.systemHostCPU().escape &
            "\n    - CountCPUs:   " & sysInfo.systemCountProcessors().intToStr() &
            "\n    - MemTotal:    " & system.getTotalMem().intToStr() & " byte" &
            "\n    - MemOccupied: " & system.getOccupiedMem().intToStr() & " byte" &
            "\n    - MemFree:     " & system.getFreeMem().intToStr() & " byte" &
            "\n    - Hostname:    " & sysInfo.hostname().escape &
            "\n    - Login/User:  " & sysInfo.userName().escape &
            "\n    - uid:         " & int(posix.getuid()).intToStr() &
            "\n    - euid:        " & int(posix.geteuid()).intToStr() &
            "\n    - egid:        " & int(posix.getegid()).intToStr() &
            "\n    - gid:         " & int(posix.getgid()).intToStr() &
            "\n    - hostid:      " & int(posix.gethostid()).intToStr() &
            "\n    - pid:         " & int(posix.getpid()).intToStr() &
            "\n    - ppid:        " & int(posix.getppid()).intToStr() &
            "\n    - pgid:        " & int(posix.getpid()).intToStr() &
            "\n    - pgrp:        " & int(posix.getpgrp()).intToStr() &
            ""
    resultStr = resultStr & "\n  - EnvVars:"
    for key, value in envPairs():
        resultStr =
            resultStr &
            "\n    - " & key & ": " & value.escape

    return resultStr & "\n"


# Beispiel: Tests
when isMainModule:
    # Display the System-Info as String
    echo systemInfo().toString()
