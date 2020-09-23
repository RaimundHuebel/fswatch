# Filesystem-Watcher which executes an program, when an watched file got changed.
#
# license: MIT
# author: Raimund Hübel <raimund.huebel@googlemail.com>
#
# compile and run + tooling:
#
#   ## Separated compile and run steps ...
#   $ nim compile fwatch.nim
#   $ ./fwatch[.exe]
#
#   ## In one step ...
#   $ nim compile [--out:fwatch.exe] --run fwatch.nim
#
#   ## Optimal-Compile ...
#   $ nim compile -d:release --opt:size fwatch.nim
#   $ strip --strip-all fwatch  #OPTIONAL/TOTEST
#   $ upx --best fwatch
#   $ ldd fwatch                # Nur zur Info
#   $ -> sizeof(normal/upx+strip) = 49kB / 18kB
#
#   ## Execute ...
#   $ fwatch --verbose --watch:src/ exec echo nim compile src/fwatch.nim
#   $ fwatch --verbose --watch:src/ init echo nim compile src/fwatch.nim


{.deadCodeElim: on.}


import os
import parseopt
import strutils
import sequtils
import tables
import json
from posix import SIGINT, SIGTERM, onSignal

import fwatchpkg/utils/file_stat
import fwatchpkg/utils/result


## Helfer um Terminal farbig zu gestallten.
## siehe: http://www.malloc.co/linux/how-to-print-with-color-in-linux-terminal/

proc green*(str: string): string =
    "\x1b[0;32m" & str &  "\x1b[0m"

proc yellow*(str: string): string =
    "\x1b[0;33m" & str &  "\x1b[0m"

proc red*(str: string): string =
    "\x1b[0;31m" & str &  "\x1b[0m"

proc ok*(str: string):    string {.inline.} = str.green
proc warn*(str: string):  string {.inline.} = str.yellow
proc error*(str: string): string {.inline.} = str.red



type OsReturnCode = int




type FsWatcherCommand* = ref object
    version:        string
    baseDirectory:  string
    commandType:    string       #init|exec|...
    remainingArgs:  seq[string]
    watchFiles:     seq[string]
    isVerbose:      bool
    isShowVersion:  bool
    isShowHelp:     bool
    isClearConsole: bool
    configErrors:   seq[string]


proc configFilename*(self: FsWatcherCommand): string =
    let appName = os.getAppFilename().lastPathPart()
    let configFilename = "." & appName & ".conf"
    return configFileName



proc verboseInfo(self: FsWatcherCommand, msg: string) =
    if self.isVerbose:
        echo "[INFO] " & msg


proc newFsWatcherCommand*(): FsWatcherCommand =
    ## Erstellt ein FsWatcherCommand mit den wichtigsten Konfigurationen.
    let fsWatcherCommand = FsWatcherCommand()
    fsWatcherCommand.version       = "0.0.1"
    fsWatcherCommand.baseDirectory = os.getCurrentDir()

    return fsWatcherCommand


proc initWithConfigFile*(
    self: FsWatcherCommand,
    configFilepath: string
  ): FsWatcherCommand {.discardable.} =
    ## Initializes the Command with the given Config-File.
    if not os.existsFile(configFilepath):
        self.configErrors.add("config-file: '" & configFilepath & "' does not exist")
        return self
    let jsonConf = json.parseFile(configFilepath)
    proc toString(x: JsonNode): string = x.getStr()
    self.isVerbose      = jsonConf["isVerbose"     ].getBool(false)
    self.isClearConsole = jsonConf["isClearConsole"].getBool(false)
    self.watchFiles     = jsonConf["watchFiles"    ].getElems().map(toString)
    self.remainingArgs  = jsonConf["command"       ].getElems().map(toString)
    return self


proc initWithDefaultConfigFiles*(
    self: FsWatcherCommand,
): FsWatcherCommand {.discardable.} =
    ## Initializes the Command with the default config files, if existing, which are evaluated in following order:
    ## 1. $APPDIR/.highlight.json
    let appFilename = os.getAppFilename().lastPathPart()
    let configFilepaths = @[
        # $APPDIR/.fwatch.json
        os.splitFile(os.getAppFilename()).dir & os.DirSep & "." & appFilename & ".json",
      ].deduplicate()
    for configFilepath in configFilepaths:
        if os.existsFile(configFilepath):
            self.initWithConfigFile(configFilepath)
    return self



proc initWithCliArgs*(
    self: FsWatcherCommand,
    args: seq[TaintedString],
  ): FsWatcherCommand {.discardable.} =
    ## Initializes the Command from the given CLI-Args.
    var optParser = initOptParser(args)
    # Parse fwatch-Options/Args ...
    while true:
        optParser.next()
        case optParser.kind:
        of cmdLongOption, cmdShortOption:
            self.verboseInfo " ParseOpt-Option: " & optParser.key
            case optParser.key:
            of "verbose":
                self.verboseInfo "   Would be verbose"
                self.isVerbose = true
            of "v", "version":
                self.verboseInfo "   Would show Version"
                self.isShowVersion = true
            of "h", "help":
                self.verboseInfo "   Would show Help"
                self.isShowHelp = true
            of "c", "clear":
                self.verboseInfo "   Would clear console before executing programm"
                self.isClearConsole = true
            of "w", "watch":
                self.verboseInfo "   Watch Files/Directories: " & optParser.val
                for watchFile in strutils.split(optParser.val, ":"):
                    if watchFile == "": continue
                    self.verboseInfo "     Watch Files/Directory: " & watchFile
                    self.watchFiles.add( watchFile )
            else:
                self.configErrors.add "unknown option --" & optParser.key

        # Parse Arguments ...
        of parseopt.cmdArgument:
            # Sobald ein Argument gekommen ist, gehören die restlichen Parameter zum aufgerufenen Programm.
            self.verboseInfo " ParseOpt-Command-Type: " & optParser.key
            case optParser.key:
            of "exec", "init", "help", "version":
                self.commandType = optParser.key
                break
            else:
                self.configErrors.add "unknown command type: " & optParser.key
                break

        # End of Opt-Parsing (sollte niemals eintreten)
        of parseopt.cmdEnd:
            self.configErrors.add("wtf? cmdEnd should not happen")
            break

    # Parse remaining args for the sub programm ...
    self.verboseInfo " ParseOpt-Remaining Args: " & optParser.key
    if optParser.remainingArgs.len > 0:
        self.verboseInfo " ParseOpt-Remaining given -> clear initial remaining args"
        self.remainingArgs.setLen(0)
    for remainingArg in optParser.remainingArgs:
        self.verboseInfo "   CLI-Arg: " & remainingArg
        self.remainingArgs.add( remainingArg )

    return self



proc initWithCliArgs*(
    self: FsWatcherCommand
  ): FsWatcherCommand {.discardable.} =
    ## Initializes the Command with the CLI-Args when the program was executed.
    self.initWithCliArgs( os.commandLineParams() )
    return self



proc doShowVersion(self: FsWatcherCommand): OsReturnCode =
    ## Gibt die Version der Anwendung auf der Console aus.
    echo "[INFO] do show app version"
    echo self.version
    return 0



proc doShowHelp(self: FsWatcherCommand): OsReturnCode =
    ## Gibt die Hilfe zu der Anwendung auf der Console aus.
    echo "[INFO] do show app help"
    let appName = os.getAppFilename().lastPathPart()
    echo "USAGE:"
    echo "  $ " & appName & " [OPTIONS] [COMMAND_TYPE] [COMMAND_ARGS]"
    echo ""
    echo "COMMAND_TYPE"
    echo "  version              -   Show version of " & appName
    echo "  help                 -   Show help of " & appName
    echo "  init [CLI-COMMAND]   -   Initializes a config-file which is read by before processing"
    echo "  exec [CLI-COMMAND]   -   Executes the given command if any of the watched files changed"
    echo ""
    echo "Example - Get Help:"
    echo "  $ " & appName
    echo "  $ " & appName & " help"
    echo "  $ " & appName & " --help"
    echo ""
    echo "Example - Get Version:"
    echo "  $ " & appName & " version"
    echo ""
    echo "Example - initialize .fwatch.conf:"
    echo "  $ " & appName & " init"
    echo "  $ " & appName & " --watch:my_file.txt init echo 'file changed: {}"
    echo ""
    echo "Example - execute command when watched file / dir changed"
    echo "  $ " & appName & " --watch:my_file.txt exec echo 'File changed: {}'"
    echo ""
    echo "Example - initialize .fwatch.conf with a command for easy execution:"
    echo "  $ " & appName & " --watch:my_file.txt init echo 'File changed: {}'"
    echo "  $ " & appName & " exec"
    return 0



proc doInitProject(self: FsWatcherCommand): OsReturnCode =
    ## Schreibt eine fwatch-Konfigurations-Datei in das aktuelle Verzeichnis, welches dann
    ## bei nachfolgenden Initialisierungen durch newFsWatcherCommand mit importiert wird.
    let configFilename = self.configFilename
    echo "[INFO] erstelle " & configFilename
    let jsonObj: JsonNode = %* {
        "isVerbose": self.isVerbose,
        "isClearConsole" : self.isClearConsole,
        "watchFiles": self.watchFiles,
    }
    if self.remainingArgs.len > 0:
        jsonObj["command"] = %* self.remainingArgs
    let jsonIo: File = configFilename.open(fmWrite)
    jsonIo.write(jsonObj.pretty)
    jsonIo.flushFile
    jsonIo.close
    echo "[OK  ] ".green & configFilename & " erstellt"
    return 0




###
# Inotify-API
# siehe: https://github.com/zah/grip-lang/blob/master/lib/posix/inotify.nim
# siehe: /usr/include/x86_64-linux-gnu/sys/inotify.h
###

type InotifyFileDescriptor  = cint
type InotifyWatchDescriptor = cint
type ErrorCode              = cint

type InotifyEvent* {.
  pure, final, importc: "struct inotify_event", header: "<sys/inotify.h>"
.} = object
    wd*:     InotifyWatchDescriptor  # Watch descriptor.
    mask*:   uint32                  # Watch mask.
    cookie*: uint32                  # Cookie to synchronize two events.
    len*:    uint32                  # Length (including NULs) of name.
    name*:   cstring                 # Name.

#const IN_ACCESS*:     uint32 = 0x00000001  # File was accessed.
const IN_MODIFY*:      uint32 = 0x00000002  # File was modified.
const IN_ATTRIB*:      uint32 = 0x00000004  # Metadata changed.
#const IN_CLOSE*:      uint32 = 0x00000018  # File got closed.
#const IN_OPEN*:       uint32 = 0x00000020  # File got opened.
const IN_MOVE*:        uint32 = 0x000000C0  # File was moved.
const IN_CREATE*:      uint32 = 0x00000100  # Subfile was created.
const IN_DELETE*:      uint32 = 0x00000200  # Subfile was deleted.
const IN_DELETE_SELF*: uint32 = 0x00000400  # Self was deleted.
const IN_MOVE_SELF*:   uint32 = 0x00000800  # Self was moved.

const IN_UMOUNT*:      uint32 = 0x00002000  # Backing fs was unmounted
const IN_ONLYDIR*:     uint32 = 0x01000000  # Only watch the path if it is a directory.
const IN_DONT_FOLLOW*: uint32 = 0x02000000  # Do not follow a sym link.
const IN_ISDIR*:       uint32 = 0x40000000  # Event occurred against dir.


## Create an Inotify instance and returns an InotifyFileDescriptor
proc InotifyInit1*(
  ): InotifyFileDescriptor {. cdecl, importc: "inotify_init", header: "<sys/inotify.h>" .}

## Closes the InotifyFileDescriptor
proc InotifyClose*(
    fd: InotifyFileDescriptor
  ): ErrorCode {. cdecl, importc: "close", header: "<unistd.h>" .}

## Reads from an InotifyFileDescriptor
type cssize* {. importc: "ssize_t", header: "<unistd.h>" .} = uint
proc InotifyRead*(
    fd: InotifyFileDescriptor,
    buf: pointer,
    count: csize
  ): cssize {. cdecl, importc: "read", header: "<unistd.h>" .}


## Add watch of object NAME to inotify instance FD.
## Notify about events specified by MASK.
proc InotifyAddWatch*(
    fd: InotifyFileDescriptor, name: cstring, mask: uint32
  ): InotifyWatchDescriptor {. cdecl, importc: "inotify_add_watch", header: "<sys/inotify.h>" .}

## Remove the watch specified by WD from the inotify instance FD.
proc InotifyRmWatch*(
    fd: InotifyFileDescriptor,
    wd: InotifyWatchDescriptor
  ): ErrorCode {. cdecl, importc: "inotify_rm_watch", header: "<sys/inotify.h>".}




proc doRun(self: FsWatcherCommand): OsReturnCode  =
    echo "[INFO] Führe Kommando aus bei Änderungen an Dateien ..."
    echo "[INFO]   Dateien:  " & self.watchFiles.join(" ")
    echo "[INFO]   Kommando: " & self.remainingArgs.join(" ")

    block:
        echo "[INFO] Prüfe ob Dateien für die Überwachung vorhanden sind ..."
        if self.watchFiles.len == 0:
            echo "[FAIL] ".error & "    Keine Dateien für die Überwachung vorhanden"
            return 1
        echo "[OK  ]".green & "    Dateien sind vorhanden"

        echo "[INFO] Erstelle Inotify-Instanz ..."
        let inotifyFd = InotifyInit1()
        if inotifyFd < 0:
            echo "[FAIL]".error & "    Inotify-Instanz konnte nicht erstellt werden (fd: " & $inotifyFd & ")"
            return 1
        echo "[OK  ]".green & "    Inotify-Instanz erstellt (fd: " & $inotifyFd & ")"

        defer:
            echo "[INFO] Schließe Inotify-Instanz ..."
            if InotifyClose(inotifyFd) == 0:
                echo "[OK  ]".green & "    Inotify-Instanz wurde erfolgreich geschlossen"
            else:
                echo "[FAIL]".error & "    Inotify-Instanz konnte nicht geschlossen werden"

        echo "[INFO] Erstelle InotifyWatches für Dateien (errno: " & $osLastError() & ") ..."
        #var inotifyWds = newSeq[InotifyWatchDescriptor]()
        var inotifyWd2WatchFileMap = initOrderedTable[InotifyWatchDescriptor, string]()
        var watchFiles: seq[string] = self.watchFiles.deduplicate()
        var watchFileIdx: int = 0

        var watchMask: uint32 = 0
        watchMask = IN_MODIFY or IN_ATTRIB or IN_MOVE or IN_CREATE or IN_DELETE
        watchMask = watchMask or IN_DELETE_SELF or IN_MOVE_SELF   # Self Move/Delete verfolgen
        watchMask = watchMask or IN_DONT_FOLLOW                   # Symlinks nicht verfolgen
        #watchMask = watchMask or IN_ACCESS                       # Allgemeiner Zugriff kommt zu häufig vor

        #for watchFile in watchFiles:
        #for watchFileIdx in 0..watchFiles.high:
        while watchFileIdx < watchFiles.len:
            let watchFile: string = watchFiles[watchFileIdx]
            watchFileIdx += 1
            echo "[INFO]    Ermittle FileStat für '" & watchFile & "."
            let statResult = file_stat.newFileStat2(watchFile)
            if statResult.isError:
                echo "[WARN]".warn & "    Konnte FileStat für '" & watchFile & "' nicht ermitteln (error: '" & $statResult.errValue & "')"
                continue
            let watchFileStat: FileStat = statResult.unwrap()

            # Erstmal nur Dateien und Verzeichnisse unterstützen ...
            if not (watchFileStat.isFile or watchFileStat.isDirectory):
                echo "[WARN]".warn & "    Dateityp nicht unterstützt für '" & watchFile & " -> ignorieren"
                continue

            echo "[INFO]    Erstelle InotifyWatch für: " & watchFile
            let watchDescriptor = inotifyFd.InotifyAddWatch(
                name = watchFile,
                mask = watchMask
            )
            if watchDescriptor < 0:
                echo "[WARN]".warn & "    InotifyWatch konnte nicht für '" & watchFile & "' erstellt werden (errno: " & $osLastError() & ")"
                continue
            echo "[OK  ]".ok & "    InotifyWatch für '" & watchFile & "' erstellt (wd: " & $watchDescriptor & ")"
            inotifyWd2WatchFileMap[watchDescriptor] = watchFile

            # Unterverzeichnisse hinzufügen wenn es sich um ein Verzeichnis handelt ...
            if watchFileStat.isDirectory:
                echo "[INFO]    '" & watchFile & "' ist ein Verzeichnis -> installiere überwachung"

                for subKind, subPath in os.walkDir( dir = watchFile, relative = true ):
                    if subKind != os.PathComponent.pcDir:
                        continue
                    let additionalWatchDir = os.joinPath(watchFile, subPath)
                    echo "[INFO]    - " & additionalWatchDir & " : " & $subKind
                    watchFiles.add( additionalWatchDir )

        defer:
            echo "[INFO] Schließe alle offenen InotifyWatches ..."
            for watchDescriptor, watchFile in inotifyWd2WatchFileMap:
                echo "[INFO]    schließe WatchDescriptor für '" & watchFile & "' (wd: " & $watchDescriptor & ")"
                if inotifyFd.InotifyRmWatch(watchDescriptor) < 0:
                    echo "[WARN]".warn & "    WatchDescriptor konnte nicht geschlossen werden (errno: " & $osLastError() & ")"
                else:
                    echo "[OK  ]".ok & "    WatchDescriptor geschlossen"
            inotifyWd2WatchFileMap.clear()

        echo "[INFO] Initialisiere InotifyEvent-Pointer ..."
        let inotifyEventSize: int = InotifyEvent.sizeof() + 1000 + 1
        echo "[INFO]    sizeof(inotifyEvent): " & $inotifyEventSize & " bytes"
        let inotifyEventPtr: ptr InotifyEvent = cast[ptr InotifyEvent](alloc(inotifyEventSize))
        defer:
            echo "[INFO] Gebe InotifyEvent-Pointer frei ..."
            dealloc( inotifyEventPtr )
        echo "[INFO]    inotifyEventPtr.Addr: 0x" & $cast[uint](inotifyEventPtr).toHex()

        echo "[INFO] Verarbeite File-Change-Events ..."
        onSignal(SIGINT):
            echo "bye from signal: ", sig
            raise newException(Exception, "Quit the Loop")
        while true:
            try:
                echo ""
                echo "[INFO] Warte auf Inotify-Event ..."

                zeroMem(inotifyEventPtr, inotifyEventSize)
                let inotifyEventReadSize: cssize = inotifyFd.InotifyRead(buf = inotifyEventPtr, count = inotifyEventSize)
                if inotifyEventReadSize < 0:
                    echo "[WARN]".warn & "    Inotify-Event konnte nicht gelesen werden (errno: " & $osLastError() & ")"
                    break
                echo "[OK  ]".ok & "  Inotify-Event gelesen ..."
                echo "        readed: " & $inotifyEventReadSize & " bytes"
                echo "        wd:     " & $inotifyEventPtr.wd
                echo "        mask:   0x" & $inotifyEventPtr.mask.toHex()
                echo "        cookie: 0x" & $inotifyEventPtr.cookie.toHex()
                echo "        len:    " & $inotifyEventPtr.len & " chars"
                echo "        name:   '" & $inotifyEventPtr.name & "'"

                if not inotifyWd2WatchFileMap.contains(inotifyEventPtr.wd):
                    echo "[WARN]".warn & "    WatchDescriptor -> Filename eintrag nicht gefunden für wd: " & $inotifyEventPtr.wd
                    continue

                let changedFilename: string =
                    if inotifyEventPtr.len > 0'u32:
                        inotifyWd2WatchFileMap[ inotifyEventPtr.wd ].joinPath( $inotifyEventPtr.name )
                    else:
                        inotifyWd2WatchFileMap[ inotifyEventPtr.wd ]

                var handled = false
                # Kommt zu häufig vor ...
                #if (inotifyEventPtr.mask and IN_ACCESS) != 0:
                #    echo "[INFO]".green, " file '" & changedFilename & "' was accessed"
                #    handled = true
                if (inotifyEventPtr.mask and IN_ISDIR) == 0:
                    echo "[INFO]".green, " fs entry '" & changedFilename & "' is a file"


                if (inotifyEventPtr.mask and IN_ISDIR) != 0:
                    echo "[INFO]".green, " fs entry '" & changedFilename & "' is a directory"


                if (inotifyEventPtr.mask and IN_MODIFY) != 0:
                    echo "[INFO]".green, " file '" & changedFilename & "' was modified"
                    handled = true


                if (inotifyEventPtr.mask and IN_ATTRIB) != 0:
                    echo "[INFO]".green, " file '" & changedFilename & "' attribs changed"
                    handled = true


                if (inotifyEventPtr.mask and (IN_MODIFY or IN_ATTRIB)) != 0:
                    echo "[INFO]".green, " file '" & changedFilename & "' was modified -> Execute"
                    handled = true
                    # Execute given command when File has changed ...
                    let command: string = (
                        self
                        .remainingArgs
                        .map( proc (arg: string): string =
                            arg.replace("{}", changedFilename)
                        )
                        .join(" ")
                    )
                    echo "[EXEC] ".warn, command
                    let returnCode: int = os.execShellCmd( command )
                    if returnCode == 0:
                        echo "[OK  ]".ok   & " the process finished with returncode: " & $returnCode
                    else:
                        echo "[WARN]".warn & " the process finished with returncode: " & $returnCode



                if (inotifyEventPtr.mask and IN_CREATE) != 0:
                    echo "[INFO]".green, " file '" & changedFilename & "' was created"
                    handled = true
                    # Add InotifyWatch if a Directory was created ...
                    if (inotifyEventPtr.mask and IN_ISDIR) != 0:
                        echo "[INFO]    Erstelle InotifyWatch für: " & changedFilename
                        let watchDescriptor = inotifyFd.InotifyAddWatch(
                            name = changedFilename,
                            mask = watchMask
                        )
                        if watchDescriptor >= 0:
                            echo "[OK  ]".ok & "    InotifyWatch für '" & changedFilename & "' erstellt (wd: " & $watchDescriptor & ")"
                            inotifyWd2WatchFileMap[watchDescriptor] = changedFilename
                        else:
                            echo "[WARN]".warn & "    InotifyWatch konnte nicht für '" & changedFilename & "' erstellt werden (errno: " & $osLastError() & ")"


                if (inotifyEventPtr.mask and IN_DELETE) != 0:
                    echo "[INFO]".green, " file '" & changedFilename & "' was deleted"
                    handled = true
                    # Remove InotifyWatch if a Directory was deleted or a direct delete has occurred ...
                    var isRemoveWatch = false
                    isRemoveWatch = isRemoveWatch or (inotifyEventPtr.mask and IN_ISDIR) != 0
                    isRemoveWatch = isRemoveWatch or (inotifyEventPtr.len  == 0)
                    isRemoveWatch = isRemoveWatch or (inotifyEventPtr.name == "")
                    isRemoveWatch = isRemoveWatch and (inotifyEventPtr.wd > 0)
                    isRemoveWatch = isRemoveWatch and (inotifyWd2WatchFileMap.contains(inotifyEventPtr.wd))
                    if isRemoveWatch:
                        echo "[INFO] Schließe offenen InotifyWatch für '" & changedFilename & "'..."
                        if inotifyFd.InotifyRmWatch(inotifyEventPtr.wd) < 0:
                            echo "[WARN]".warn & "    WatchDescriptor konnte nicht geschlossen werden (errno: " & $osLastError() & ")"
                        else:
                            echo "[OK  ]".ok & "    WatchDescriptor geschlossen"
                        inotifyWd2WatchFileMap.del(inotifyEventPtr.wd)

                if (inotifyEventPtr.mask and IN_UMOUNT) != 0:
                    echo "[INFO]".green, " file '" & changedFilename & "' was unmounted"
                    handled = true
                    # TODO Remove InotifyWatch if a Directory was unmounted
                    # TODO siehe oben: Remove InotifyWatch if a Directory was deleted or a direct delete has occurred

                if not handled:
                    echo "[INFO]".green, " something happened with '" & changedFilename & "'"

            except:
                echo "[WARN]".warn & "    An Error happened during reading the InotifyEvent"
                echo "[WARN]".warn & "    -> " & system.getCurrentExceptionMsg()
                break

    echo "[OK  ]".green & " Kommando ausgeführt"
    return 0





proc doExecute(self: FsWatcherCommand): OsReturnCode =
    ## Führt das FsWatcherCommand entsprechend seiner Konfiguration aus.
    echo "[INFO] Execute FsWatcher"

    if self.isShowHelp or self.commandType == "help" or self.commandType == "":
        return self.doShowHelp()

    if self.isShowVersion or self.commandType == "version":
        return self.doShowVersion()

    if self.commandType == "init":
        return self.doInitProject()

    if self.commandType == "exec":
        return self.doRun()

    else:
        echo "[WARN]".yellow & " TODO: " & self.commandType
        return 1


proc main() =
    let fwatchCommand = (
        newFsWatcherCommand()
        .initWithDefaultConfigFiles()
        .initWithCliArgs()
    )
    let returnCode = fwatchCommand.doExecute()
    quit(returnCode)

main()
