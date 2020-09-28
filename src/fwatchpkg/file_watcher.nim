# API to watch changes on the Filesystem.
#
# see: https://github.com/zah/grip-lang/blob/master/lib/posix/inotify.nim
# see: /usr/include/x86_64-linux-gnu/sys/inotify.h


import ./inotify
import ./utils/file_stat
import ./utils/result
import strutils
import tables
import times
import os


type FileWatcher* = ref object of RootObj
    ## Class for watching changes on the Filesystem.
    inotifyFd:              InotifyFileDescriptor
    inotifyWd2WatchFileMap: OrderedTableRef[InotifyWatchDescriptor, string]
    isVerbose:              bool


type FileChangeEvent* = ref object of RootObj
    ## Class providing informations about the change of the Filesystem-Entry.
    timestamp:  Time
    eventType*: string
    fileType*:  string
    filepath*:  string




proc new*(class: typedesc[FileWatcher]): FileWatcher =
    ## Erstellt eine neue FileWatcher-Instanz.
    let fileWatcher = FileWatcher()

    # Inotify-Instanz erstellen ...
    fileWatcher.inotifyFd = InotifyInit1()
    if fileWatcher.inotifyFd < 0:
        raise newException(Exception, "Inotify-Instanz konnte nicht erstellt werden (fd: " & $fileWatcher.inotifyFd & ")")

    # Container für InotifyWatches erstellen ...
    fileWatcher.inotifyWd2WatchFileMap = newOrderedTable[InotifyWatchDescriptor, string]()

    return fileWatcher




proc dispose*(self: FileWatcher) =
    ## Gibt den FileWatcher und seine Ressourcen frei.
    if self.isVerbose:
        echo "[INFO] Dispose FileWatcher ..."

    # Inotify-Watches schliessen ...
    for watchDescriptor, watchFile in self.inotifyWd2WatchFileMap:
        discard self.inotifyFd.InotifyRmWatch(watchDescriptor)
    self.inotifyWd2WatchFileMap.clear()

    # Inotify-Instanz schliessen ...
    if self.inotifyFd != 0:
        discard InotifyClose(self.inotifyFd)
        self.inotifyFd = 0



proc setVerbose*(self: FileWatcher, isVerbose: bool): FileWatcher {.discardable.} =
    ## Setzt den FileWatcher auf Verbose, womit genauere Log-Ausgaben generiert werden.
    self.isVerbose = isVerbose
    return self


proc stop*(self: FileWatcher) =
    raise newException(Exception, "Quit the Loop")





proc removeFilepath*(self: FileWatcher, watchFile: string): FileWatcher {.discardable.} =
    ## Entfernt eine Datei oder ein Verzeichnis aus der Überwachung.
    var watchFdsToRemove = newSeq[InotifyWatchDescriptor]()

    # Ermitteln welche Elemente entfernt werden sollen ...
    for watchFd, fileName in self.inotifyWd2WatchFileMap.pairs():
        # Datei / Verzeichnis direkt oder Unterelemente von Verzeichnissen entfernen ...
        if fileName == watchFile or fileName.startsWith(watchFile / ""):
            watchFdsToRemove.add(watchFd)

    # WatchDescriptor-Liste aufräumen und WatchDescriptoren entfernen ...
    for watchFd in watchFdsToRemove:
        let fileName = self.inotifyWd2WatchFileMap[watchFd]
        if self.isVerbose:
            echo "[INFO] Unwatch: " & fileName
        discard self.inotifyFd.InotifyRmWatch(watchFd)
        self.inotifyWd2WatchFileMap.del(watchFd)

    return self



proc addFilepath*(
    self: FileWatcher,
    watchFile: string,
    isRecursive: bool = false
): FileWatcher {.discardable.} =
    ## Fügt eine Datei oder ein Verzeichnis zur Überwachung hinzu.
    ## Wenn ein Verzeichnis hinzugefügt wird und isRecursive = true ist, dann werden
    ## auch alle Unterverzeichnisse überwacht.

    # FileStat zur watchFile erstellen ...
    let statResult = file_stat.newFileStat2(watchFile)
    if statResult.isError:
        raise newException(Exception, "Konnte FileStat für '" & watchFile & "' nicht ermitteln (error: '" & $statResult.errValue & "')")
    let watchFileStat: FileStat = statResult.unwrap()

    # Erstmal nur Dateien und Verzeichnisse unterstützen ...
    if not (watchFileStat.isFile or watchFileStat.isDirectory):
        raise newException(Exception, "Dateityp nicht unterstützt für '" & watchFile & " -> ignorieren")

    # Abbruch, wenn Verzeichnis der regulären Datei bereits überwacht ...
    if watchFileStat.isFile():
        for watchFd, fileName in self.inotifyWd2WatchFileMap.pairs():
            if os.splitFile(watchFile).dir == os.splitFile(fileName).dir:
                return

    # Überwachung entfernen, wenn watchFile bereits überwacht, wird dann später neu eingerichtet (auch Unterverzeichnisse)...
    self.removeFilepath(watchFile)

    # Überwachungsereignisse festlegen ...
    var watchMask: uint32 = 0
    watchMask = IN_MODIFY or IN_ATTRIB or IN_MOVE or IN_CREATE or IN_DELETE
    watchMask = watchMask or IN_DELETE_SELF or IN_MOVE_SELF   # Self Move/Delete verfolgen
    watchMask = watchMask or IN_DONT_FOLLOW                   # Symlinks nicht verfolgen
    #watchMask = watchMask or IN_ACCESS                       # Allgemeiner Zugriff kommt zu häufig vor

    # InotifyWatch für Datei/Verzeichnis erstellen ...
    let watchDescriptor = self.inotifyFd.InotifyAddWatch(
        name = watchFile,
        mask = watchMask
    )
    if watchDescriptor < 0:
        raise newException(Exception, "InotifyWatch konnte nicht für '" & watchFile & "' erstellt werden (errno: " & $osLastError() & ")")

    # in Überwachungsliste aufnehmen ...
    self.inotifyWd2WatchFileMap[watchDescriptor] = watchFile

    # Wenn nicht Recursiv, dann ist hier Schluss ...
    if isRecursive == false:
        return self

    # Wenn es sich um eine normale Datei handelt, dann ist hier Schluss ...
    if watchFileStat.isFile():
        return self

    assert( watchFileStat.isDirectory() )

    # Wenn es sich um ein Verzeichnis handelt, und die rekursive Aufnahme erwünscht ist, dann alle
    # Unterverzeichnisse mit aufnehmen ...
    var subdirs = newSeq[string]()
    for subKind, subPath in os.walkDir( dir = watchFile, relative = true ):
        if subKind != os.PathComponent.pcDir:
            continue
        subdirs.add( os.joinPath(watchFile, subPath) )

    for subdir in subdirs:
        self.addFilepath( subdir, isRecursive = true)

    return self



proc addFilepaths*(
    self: FileWatcher,
    watchFiles: openArray[string],
    isRecursive: bool = false
): FileWatcher {.discardable.} =
    ## Fügt eine Reihe von Files zur FileWatch hinzu.
    for watchFile in watchFiles:
        self.addFilepath(watchFile, isRecursive=isRecursive)
    return self




proc run*(
    self: FileWatcher,
    changeHandler: proc(changeEvent: FileChangeEvent)
) =
    ## Lässt den FileWatcher laufen, und ruft changeHandler mit den entsprechenden FileChangeEvent auf.

    if changeHandler == nil:
        raise newException(Exception, "param changeHandler must not be null")

    # InotifyEventptr erstellen, und später aufräumen ...
    let inotifyEventSize: int = InotifyEvent.sizeof() + 1000 + 1
    let inotifyEventPtr: ptr InotifyEvent = cast[ptr InotifyEvent](alloc(inotifyEventSize))
    defer:
        if self.isVerbose:
            echo "[INFO] Release inotifyEventPtr ..."
        dealloc( inotifyEventPtr )

    # Wird fürs Event-Debouncing benötigt.
    var lastChangeEvent: FileChangeEvent = nil

    # Inotify events pollen und entsprechende Events generieren ...
    while true:
        try:
            if self.isVerbose:
                echo ""
                echo "[INFO] Warte auf Inotify-Event ..."

            # Warte auf Inotify-Event
            zeroMem(inotifyEventPtr, inotifyEventSize)
            let inotifyEventReadSize: cssize = self.inotifyFd.InotifyRead(buf = inotifyEventPtr, count = inotifyEventSize)
            if inotifyEventReadSize < 0:
                echo "[WARN]" & "    Inotify-Event konnte nicht gelesen werden (errno: " & $osLastError() & ")"
                break
            if self.isVerbose:
                echo "[OK  ]" & "  Inotify-Event gelesen ..."
                echo "        readed: " & $inotifyEventReadSize & " bytes"
                echo "        wd:     " & $inotifyEventPtr.wd
                echo "        mask:   0x" & $inotifyEventPtr.mask.toHex()
                echo "        cookie: 0x" & $inotifyEventPtr.cookie.toHex()
                echo "        len:    " & $inotifyEventPtr.len & " chars"
                echo "        name:   '" & $inotifyEventPtr.name & "'"

            if not self.inotifyWd2WatchFileMap.contains(inotifyEventPtr.wd):
                echo "[WARN]" & "    WatchDescriptor -> Filename eintrag nicht gefunden für wd: " & $inotifyEventPtr.wd
                continue

            # Event zusammenstellen ...
            let changeEvent = FileChangeEvent()

            changeEvent.timestamp = times.getTime()

            changeEvent.filepath =
                if inotifyEventPtr.len > 0'u32:
                    self.inotifyWd2WatchFileMap[ inotifyEventPtr.wd ].joinPath( $inotifyEventPtr.name )
                else:
                    self.inotifyWd2WatchFileMap[ inotifyEventPtr.wd ]

            if (inotifyEventPtr.mask and IN_ISDIR) != 0:
                changeEvent.fileType = "dir"
            else:
                changeEvent.fileType = "file"

            if (inotifyEventPtr.mask and IN_CREATE) != 0:
                changeEvent.eventType = "created"
            elif (inotifyEventPtr.mask and IN_DELETE) != 0:
                changeEvent.eventType = "deleted"
            elif (inotifyEventPtr.mask and IN_MODIFY) != 0:
                changeEvent.eventType = "changed"
            elif (inotifyEventPtr.mask and IN_ATTRIB) != 0:
                changeEvent.eventType = "changed:attribs"

            # Wenn ein Verzeichnis erstellt wurde, dieses hinzufügen ...
            if changeEvent.fileType == "dir" and changeEvent.eventType == "created":
                self.addFilepath(changeEvent.filepath)

            # Wenn ein Verzeichnis gelöscht wurde, dieses entfernen (inkl. Unterelemente) ...
            if changeEvent.fileType == "dir" and changeEvent.eventType == "deleted":
                self.removeFilepath(changeEvent.filepath)

            # Ermitteln ob das changeEvent nach außen getriggert werden soll (debounce check) ...
            var isOmitEvent = true
            isOmitEvent = isOmitEvent and lastChangeEvent != nil
            isOmitEvent = isOmitEvent and changeEvent.filepath  == lastChangeEvent.filepath
            isOmitEvent = isOmitEvent and changeEvent.fileType  == lastChangeEvent.fileType
            isOmitEvent = isOmitEvent and changeEvent.eventType == lastChangeEvent.eventType
            isOmitEvent = isOmitEvent and (changeEvent.timestamp - lastChangeEvent.timestamp) <= initDuration(milliseconds=100)

            # Eventhandler aufrufen ...
            if not isOmitEvent:
                lastChangeEvent = changeEvent
                changeHandler(changeEvent)

        except:
            echo "[WARN]" & "    An Error happened during reading the InotifyEvent"
            echo "[WARN]" & "    -> " & system.getCurrentExceptionMsg()
            break

    return
