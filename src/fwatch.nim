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



#import fwatchpkg/inotify
import fwatchpkg/file_watcher


proc doRun(self: FsWatcherCommand): OsReturnCode  =
    echo "[INFO] Führe Kommando aus bei Änderungen an Dateien ..."
    echo "[INFO]   Dateien:  " & self.watchFiles.join(" ")
    echo "[INFO]   Kommando: " & self.remainingArgs.join(" ")


    let fileWatcher: FileWatcher = (
        FileWatcher
        .new()
        .setVerbose(false)
        .addFilepaths(self.watchFiles, isRecursive=true)
    )
    defer:
        fileWatcher.dispose()

    onSignal(SIGINT):
        echo "bye from signal: ", sig
        #fileWatcher.stop()
        raise newException(Exception, "Quit the Loop")

    fileWatcher.run do (changeEvent: FileChangeEvent):
        #echo changeEvent.eventType, " (", changeEvent.fileType, ") ", ": ", changeEvent.filepath
        # Execute given command when File has changed ...
        let command: string = (
            self
            .remainingArgs
            .map( proc (arg: string): string =
                arg.replace("{}", changeEvent.filepath)
            )
            .join(" ")
        )
        echo "[EXEC] ".warn, command
        let returnCode: int = os.execShellCmd( command )
        if returnCode == 0:
            echo "[OK  ]".ok   & " the process finished with returncode: " & $returnCode
        else:
            echo "[WARN]".warn & " the process finished with returncode: " & $returnCode

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
