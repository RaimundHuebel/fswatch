# Filesystem-Watcher command executes an program, when an watched file got changed.
#
# license: MIT
# author: Raimund Hübel <raimund.huebel@googlemail.com>
#
# compile and run + tooling:
#
#   ## Separated compile and run steps ...
#   $ nim compile fswatch.nim
#   $ ./fswatch[.exe]
#
#   ## In one step ...
#   $ nim compile [--out:fswatch.exe] --run fswatch.nim
#
#   ## Optimal-Compile ...
#   $ nim compile -d:release --opt:size fswatch.nim
#   $ strip --strip-all fswatch  #OPTIONAL/TOTEST
#   $ upx --best fswatch
#   $ ldd fswatch                # Nur zur Info
#   $ -> sizeof(normal/upx+strip) = 200kB / 50kB
#
#   ## Execute ...
#   $ fswatch --verbose --watch:src/ exec echo nim compile src/fswatch.nim
#   $ fswatch --verbose --watch:src/ init echo nim compile src/fswatch.nim


{.deadCodeElim: on.}

import ./file_watcher
import ./utils/file_stat

import parseopt
import strutils
import sequtils
import tables
import json
import os
from posix import SIGINT, SIGTERM, onSignal



## Helfer um Terminal farbig zu gestallten.
## siehe: http://www.malloc.co/linux/how-to-print-with-color-in-linux-terminal/

proc green*(str: string): string =
    "\x1b[0;32m" & str &  "\x1b[0m"

proc yellow*(str: string): string =
    "\x1b[0;33m" & str &  "\x1b[0m"

proc red*(str: string): string =
    "\x1b[0;31m" & str &  "\x1b[0m"

proc clearConsole*() =
    echo "\x1b[2J\x1b[1;1H"

proc resetConsole*() =
    echo "\x1b[2J\x1b[1;1H"


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


proc appConfigFilename*(self: FsWatcherCommand): string =
    let appName = os.getAppFilename().lastPathPart()
    let configFilename = "." & appName & ".json"
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
    if jsonConf.hasKey("isVerbose"):
        self.isVerbose = jsonConf["isVerbose"].getBool(false)
    if jsonConf.hasKey("isClearConsole"):
        self.isClearConsole = jsonConf["isClearConsole"].getBool(false)
    if jsonConf.hasKey("watchFiles"):
        self.watchFiles = jsonConf["watchFiles"].getElems().map(toString)
    if jsonConf.hasKey("command"):
        self.remainingArgs = jsonConf["command"].getElems().map(toString)
    return self


proc initWithDefaultConfigFiles*(
    self: FsWatcherCommand,
): FsWatcherCommand {.discardable.} =
    ## Initializes the Command with the default config files, if existing, which are evaluated in following order:
    ## 1. $APPDIR/.fswatch.json
    let appConfigFilename = self.appConfigFilename()
    let configFilepaths = @[
        # $APPDIR/.fswatch.json
        os.splitFile(os.getAppFilename()).dir & os.DirSep & appConfigFilename,
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
    # Parse fswatch-Options/Args ...
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
    echo "Example - execute command when watched file / dir changed"
    echo "  $ " & appName & " --watch:src --watch:test exec echo 'File changed: {}'"
    echo ""
    echo "Example - initialize .fswatch.conf with a command for easy execution:"
    echo "  $ " & appName & " --watch:src init echo 'file changed: {}"
    echo "  $ " & appName & " exec"
    echo "  $ " & appName & " exec echo 'override commando {}'"
    return 0



proc doInitProject(self: FsWatcherCommand): OsReturnCode =
    ## Schreibt eine fswatch-Konfigurations-Datei in das aktuelle Verzeichnis, welches dann
    ## bei nachfolgenden Initialisierungen durch newFsWatcherCommand mit importiert wird.
    let configFilename = self.appConfigFilename()
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




proc doRun(self: FsWatcherCommand): OsReturnCode  =
    echo "[INFO] Führe Kommando aus bei Änderungen an Dateien ..."
    echo "[INFO]   Verzeichnisse/Dateien: " & self.watchFiles.join(" ")
    echo "[INFO]   Kommando: " & self.remainingArgs.join(" ")

    if self.remainingArgs.len == 0:
        echo "[FAIL]".red & " Kein Kommando für die Ausführung definiert."
        return 0

    let fileWatcher: FileWatcher = (
        FileWatcher
        .new()
        .setVerbose(self.isVerbose)
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
        if self.isClearConsole:
            resetConsole()
        echo "[EXEC] ".warn, command
        let returnCode: int = os.execShellCmd( command )
        if returnCode == 0:
            echo "[OK  ]".ok   & " the process finished with returncode: " & $returnCode
        else:
            echo "[WARN]".warn & " the process finished with returncode: " & $returnCode

    echo "[OK  ]".green & " Kommando ausgeführt"
    return 0





proc doExecute*(self: FsWatcherCommand): OsReturnCode =
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
        echo "[WARN]".yellow & " unknown command: " & self.commandType
        return 1
