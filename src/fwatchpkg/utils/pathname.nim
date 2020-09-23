# Learn Nim by Practice.
#
# license: MIT
# author:  Raimund Hübel <raimund.huebel@googlemail.com>
#
# ## compile and run + tooling:
#
#   ## Seperated compile and run steps ...
#   $ nim compile [--out:pathname.exe] pathname.nim
#   $ ./pathname[.exe]
#
#   ## In one step ...
#   $ nim compile [--out:pathname.exe] --run pathname.nim
#
#   ## Optimal-Compile ...
#   $ nim compile -d:release --opt:size pathname.nim
#   $ strip --strip-all pathname  #Funktioniert wirklich
#   $ upx --best pathname
#
# ## See Also:
# - https://nim-lang.org/docs/docgen.html
# - https://nim-lang.org/documentation.html



## Module for Handling with Directories and Pathnames.
##
## ## Example
## .. code-block:: Nim
##   import pathname
##   let pathname = newPathname()
##   echo pathname.toPathStr
##   ...


import os
import ospaths
import strutils



## Import: realpath (@see module posix)
when defined(Posix):

    const PATH_MAX = 4096'u
    proc posixRealpath(name: cstring, resolved: cstring): cstring {. importc: "realpath", header: "<stdlib.h>" .}

else:
    # TODO: Support other Plattforms ...
    {.fatal: "The current plattform is not supported by utils.file_stat!".}


proc canonicalizePathString*(pathstr: string) :string =
    ## Liefert den canonischen Pfad von den gegebenen Pfad.
    ## Dabei muss das Letzte Element des Pfades existieren, sonst schlägt der Befehl fehl.
    if pathstr == "":
        raise newException(Exception, "invalid param: pathstr")
    const maxSize = PATH_MAX
    result = newString(maxSize)
    if nil == posixRealpath(pathstr, result):
        raiseOSError(osLastError())
    result[maxSize.int-1] = 0.char
    let realSize = result.cstring.len
    result.setLen(realSize)
    return result


#DEPRECATED proc normalizePathString*(pathstr: string) :string =
#DEPRECATED     ## Normalisiert ein Pfadnamen auf die kürzeste Darstellung.
#DEPRECATED     ## @see https://nim-lang.org/docs/os.html#normalizedPath
#DEPRECATED     ## @see https://www.linuxjournal.com/content/normalizing-path-names-bash
#DEPRECATED     ## @see https://ruby-doc.org/stdlib/libdoc/pathname/rdoc/Pathname.html#method-i-cleanpath
#DEPRECATED     ## @see https://ruby-doc.org/stdlib/libdoc/pathname/rdoc/Pathname.html#method-i-realpath
#DEPRECATED
#DEPRECATED     # os.normalizePath  is available since Nim v0.19.0
#DEPRECATED     #echo "[WARN] Pathname.normalize - untested os.normalizePath"
#DEPRECATED     return os.normalizedPath(pathstr)

type Pathname* = ref object
    ## Class for presenting Paths to files and directories,
    ## including a rich fluent API to support easy Development.
    path :string





proc newPathname*(): Pathname =
    ## Constructs a new Pathname with the Current Directory as Path.
    ## @returns An Pathname-Instance.
    return Pathname(path: os.getCurrentDir())



proc newPathname*(path: string): Pathname =
    ## Constructs a new Pathname.
    ## @param path The Directory which shall be listed.
    ## @returns An Pathname-Instance.
    return Pathname(path: path)


proc pathnameFromCurrentDir*(): Pathname =
    ## Constructs a new Pathname with the Current Directory as Path.
    ## @returns A Pathname-Instance.
    return newPathname(os.getCurrentDir())


proc pathnameFromAppDir*(): Pathname =
    ## Constructs a new Pathname with the App Directory as Path.
    ## @returns A Pathname-Instance.
    return newPathname(os.getAppDir())


proc pathnameFromAppFile*(): Pathname =
    ## Constructs a new Pathname with the App File as Path.
    ## @returns A Pathname-Instance.
    return newPathname(os.getAppFilename())


proc pathnameFromTempDir*(): Pathname =
    ## Constructs a new Pathname with the Temp Directory as Path.
    ## @returns A Pathname-Instance.
    return newPathname(os.getTempDir())


proc pathnameFromRootDir*(): Pathname =
    ## Constructs a new Pathname with the Temp Directory as Path.
    ## @returns A Pathname-Instance.
    return newPathname("/")


proc pathnameFromUserConfigDir*(): Pathname =
    ## Constructs a new Pathname with the Config Directory as Path.
    ## @returns A Pathname-Instance.
    return newPathname(ospaths.getConfigDir())


proc pathnameFromUserHomeDir*(): Pathname =
    ## Constructs a new Pathname with the Config Directory as Path.
    ## @returns A Pathname-Instance.
    return newPathname(ospaths.getHomeDir())



proc toPathStr*(self :Pathname): string {.inline.} =
    ## Liefert das Verzeichnis des Pathnames als String.
    return self.path



proc isAbsolute*(self: Pathname): bool =
    ## Tells if the Pathname contains an absolute path.
    return os.isAbsolute(self.path)



proc isRelative*(self: Pathname): bool =
    ## Tells if the Pathname contains an relative path.
    return not os.isAbsolute(self.path)



proc parent*(self :Pathname): Pathname =
    ## Returns the Parent-Directory of the Pathname.
    #return newPathname(ospaths.parentDir(self.path))
    #return newPathname(self.path & "/..")
    #return newPathname(normalizePathString(self.path & "/.."))
    return newPathname(os.normalizedPath(ospaths.parentDir(self.path)))



proc normalize*(self: Pathname): Pathname =
    ## Returns clean pathname of self with consecutive slashes and useless dots removed.
    ## The filesystem is not accessed.
    ## @alias #cleanpath()
    ## @alias #normalize()
    ## @see https://ruby-doc.org/stdlib/libdoc/pathname/rdoc/Pathname.html#method-i-cleanpath
    let normalizedPathStr = os.normalizedPath(self.path)

    # Optimierung für weniger Speicherverbrauch (gib self statt new pathname zurück, wenn identisch, für weniger RAM)
    if normalizedPathStr == self.path:
        return self
    return newPathname(normalizedPathStr)



proc cleanpath*(self: Pathname): Pathname {.inline.} =
    ## Returns clean pathname of self with consecutive slashes and useless dots removed.
    ## The filesystem is not accessed.
    ## @alias #cleanpath()
    ## @alias #normalize()
    ## @see https://ruby-doc.org/stdlib/libdoc/pathname/rdoc/Pathname.html#method-i-cleanpath
    self.normalize()



proc dirname*(self: Pathname): Pathname =
    ## Returns the Directory-Part of the Pathname as Pathname.
    var endPos: int = self.path.len
    # '/' die am Ende stehen ignorieren.
    while endPos > 0 and self.path[endPos-1] == '/':
        endPos -= 1
    # Basename ignorieren.
    while endPos > 0 and self.path[endPos-1] != '/':
        endPos -= 1
    # '/' die vor Basenamen stehen ignorieren.
    while endPos > 0 and self.path[endPos-1] == '/':
        endPos -= 1
    assert( endPos >= 0 )
    assert( endPos <= self.path.len )
    var resultDirnameStr: string
    if endPos > 0:
        resultDirnameStr = substr(self.path, 0, endPos - 1)
    elif endPos == 0:
        # Kein Dirname vorhanden ...
        if self.path.len > 0 and self.path[0] == '/':
            # Bei absoluten Pfad die '/' am Anfang wieder herstellen.
            #DEPRECATED resultDirnameStr = "/"
            endPos += 1
            while endPos < self.path.len and self.path[endPos] == '/':
                endPos += 1
            resultDirnameStr = substr(self.path, 0, endPos - 1)
        else:
            resultDirnameStr = "."
    else:
        echo "Pathname.dirname - wtf - endPos < 0"; quit(1)
    return newPathname(resultDirnameStr)



proc basename*(self: Pathname): Pathname =
    if self.path.len == 0:
        return self
    ## Returns the Filepart-Part of the Pathname as Pathname.
    var endPos: int = self.path.len
    # '/' die am Ende stehen ignorieren.
    while endPos > 0 and self.path[endPos-1] == '/':
        endPos -= 1
    # Denn Anfang des Basenamen ermitteln.
    var startPos: int = endPos
    while startPos > 0 and self.path[startPos-1] != '/':
        startPos -= 1
    assert( startPos >= 0 )
    assert( endPos   >= 0 )
    assert( startPos <= self.path.len )
    assert( endPos   <= self.path.len )
    assert( startPos <= endPos )
    var resultBasenameStr: string
    if startPos < endPos:
        resultBasenameStr = substr(self.path, startPos, endPos-1)
    elif startPos == endPos:
        if self.path[startPos] == '/':
            resultBasenameStr = "/"
        else:
            resultBasenameStr = ""
    else:
        echo "Pathname.basename - wtf - startPos >= endPos"; quit(1)
    return newPathname(resultBasenameStr)



proc extname*(self: Pathname): string =
    ## Returns the File-Extension-Part of the Pathname as string.
    var endPos: int = self.path.len
    # '/' die am Ende stehen ignorieren.
    while endPos > 0 and self.path[endPos-1] == '/':
        endPos -= 1
    # Wenn nichts vorhanden, oder am Ende ein '.' ist, dann fast exit.
    if endPos == 0 or self.path[endPos-1] == '.':
        return ""
    # Denn Anfang der Extension ermitteln.
    var startPos: int = endPos
    while startPos > 0 and self.path[startPos-1] != '/' and self.path[startPos-1] != '.':
        startPos -= 1
    # '.' die evtl. mehrfach vor der Extension stehen konsumieren.
    while startPos > 0 and self.path[startPos-1] == '.':
        startPos -= 1
    ## auf ersten Punkt navigieren ...
    #while startPos < endPos and self.path[startPos] == '.':
    #    startPos += 1
    assert( startPos >= 0 )
    assert( endPos   >= 0 )
    assert( startPos <= self.path.len )
    assert( endPos   <= self.path.len )
    assert( startPos <= endPos )
    var resultExtnameStr: string
    if startPos < endPos:
        if startPos > 0 and self.path[startPos-1] != '/':
            # Alle '.' am Anfang eines Pfad-Items konsumieren (startPos zeigt auf ersten Punkt).
            while startPos < endPos and self.path[startPos+1] == '.':
                startPos += 1
            resultExtnameStr = substr(self.path, startPos, endPos-1)
        else:
            resultExtnameStr = ""
    elif startPos == endPos:
        resultExtnameStr = ""
    else:
        echo "Pathname.extname - wtf - startPos >= endPos"; quit(1)
    return resultExtnameStr



proc isExisting*(self: Pathname): bool =
    ## Returns true if the path directs to an existing file-system-entity like a file, directory, device, symlink, ...
    ## Returns false otherwise.
    result = false
    result = result or os.existsFile(self.path)
    result = result or os.existsDir(self.path)
    result = result or os.symlinkExists(self.path)
    return result



proc isFile*(self: Pathname): bool =
    ## Returns true if the path directs to a file, or a symlink that points at a file,
    ## Returns false otherwise.
    return os.existsFile(self.path)



proc isDirectory*(self: Pathname): bool =
    ## Returns true if the path directs to a directory, or a symlink that points at a directory,
    ## Returns false otherwise.
    return os.existsDir(self.path)



proc isSymlink*(self: Pathname): bool =
    ## Returns true if the path directs to a symlink.
    ## Returns false otherwise.
    return os.symlinkExists(self.path)



proc listDir*(self: Pathname): seq[Pathname] =
    ## Lists the files of the addressed directory as Pathnames.
    var files: seq[Pathname] = @[]
    for file in walkDir(self.path):
        files.add(newPathname(file.path))
    return files



proc listDirStrings*(self: Pathname): seq[string] =
    ## Lists the files of the addressed directory as plain Strings.
    var files: seq[string] = @[]
    for file in walkDir(self.path):
        files.add(file.path)
    return files



proc toString*(self: Pathname): string  {.inline.} =
    ## Converts a Pathname to a String for User-Presentation-Purposes (for End-User).
    return self.path



proc `$`*(self :Pathname): string {.inline.} =
    ## Converts a Pathname to a String for User-Presentation-Purposes (for End-User).
    return self.toString()



proc inspect*(self :Pathname) :string =
    ## Converts a Pathname to a String for Diagnostic-Purposes (for Developer).
    return "Pathname(\"" & self.path & "\")"





proc newPathnames*(paths :varargs[string]) :seq[Pathname] =
    var pathnames: seq[Pathname] = newSeq[Pathname](paths.len)
    for i in 0..<paths.len:
        pathnames[i] = newPathname(paths[i])
    return @pathnames



proc pathnamesFromRoot*() :seq[Pathname] =
    ## Constructs a List of Pathnames containing all Filesystem-Roots per Entry
    ## @returns A list of Pathnames
    when defined(Windows):
        # WIndows-Version ist noch in Arbeit (siehe unten)
        return newPathnames( ospaths.parentDirs("test/a/b", inclusive=false) )
    else:
        return newPathnames("/")



proc toString*(pathnames :seq[Pathname]) :string =
    ## Converts a List of Pathnames to a String for User-Presentation-Purposes (for End-User).
    result = ""
    for pathname in pathnames:
        if not result.isNilOrEmpty():
            result = result & ", "
        result = result & "\"" & pathname.path & "\""
    result = "[" & result & "]"



proc `$`*(pathnames :seq[Pathname]) :string {.inline.} =
    ## Converts a List of Pathnames to a String.
    return pathnames.toString()



proc inspect*(pathnames :seq[Pathname]) :string =
    ## Converts a List of Pathnames to a String for Diagnostic-Purposes (for Developer).
    return "Pathnames(" & pathnames.toString() & ")"




## Noch mitten in der Entwicklung ...
when defined(Windows):
    proc winGetWindowsDirectory(lpBuffer: cstring, uSize :cuint): cuint {. importc: "GetWindowsDirectory", header: "<winbase.h>" .}
    proc pathnameFromWindowsInstallDir*() :Pathname =
        ## Constructs a new Pathname pointing to the Windows-Installation Directory.
        const PATH_MAX = 4096'u
        const maxSize = PATH_MAX
        var pathStr :string = newString(maxSize)
        let realSize :cuint = winGetWindowsDirectory(pathStr, maxSize.cuint)
        if realSize <= 0:
            raiseOSError(osLastError())
        pathStr[maxSize.int-1] = 0.char
        pathStr[realSize.int-1] = 0.char
        pathStr.setLen(realSize)
        return result


## Noch mitten in der Entwicklung ...
when defined(Windows):
    proc winGetSystemWindowsDirectory(lpBuffer: cstring, uSize :cuint): cuint {. importc: "GetSystemWindowsDirectory", header: "<winbase.h>" .}
    proc pathnameFromWindowsSystemDir*() :Pathname =
        ## Constructs a new Pathname pointing to the Windows-System Directory.
        const PATH_MAX = 4096'u
        const maxSize = PATH_MAX
        var pathStr :string = newString(maxSize)
        let realSize :cuint = winGetSystemWindowsDirectory(pathStr, maxSize.cuint)
        if realSize <= 0:
            raiseOSError(osLastError())
        pathStr[maxSize.int-1] = 0.char
        pathStr[realSize.int-1] = 0.char
        pathStr.setLen(realSize)
        return result


## Noch mitten in der Entwicklung ...
when defined(Windows):
    # @see https://msdn.microsoft.com/en-us/library/windows/desktop/aa364975(v=vs.85).aspx
    proc winGetLogicalDriveStrings(nBufferLength :uint32, lpBuffer: cstring): uint32 {. importc: "GetLogicalDriveStrings", header: "<winbase.h.h>" .}
    proc pathnamesFromWindowsDrives*() :string =
        ## Constructs a new Pathname pointing to the Windows-System Directory.
        const PATH_MAX = 4096'u
        const maxSize = PATH_MAX
        var pathStr :string = newString(maxSize)
        let realSize = winGetLogicalDriveStrings(maxSize.uint32, pathStr)
        if realSize <= 0:
            raiseOSError(osLastError())
        if realSize > maxSize:
            raiseOSError(osLastError())  #TODO
        pathStr[maxSize.int-1] = 0.char
        pathStr[realSize.int-1] = 0.char
        pathStr.setLen(realSize)
        return result



when isMainModule:

    echo "Current Directory    : ", pathnameFromCurrentDir()
    echo "Application File     : ", pathnameFromAppFile()
    echo "Application Directory: ", pathnameFromAppDir()
    echo "Temp Directory       : ", pathnameFromTempDir()
    echo "User Directory       : ", pathnameFromUserHomeDir()
    echo "User Config-Directory: ", pathnameFromUserConfigDir()

    echo "Root Directory       : ", pathnameFromRootDir()
    echo "Root Directories     : ", pathnamesFromRoot()

    echo "Current Directory (inspect): ", pathnameFromCurrentDir().inspect()
    echo "Root Directories (inspect) : ", pathnamesFromRoot().inspect()


    echo "Current Dir-Content  : ", pathnameFromCurrentDir().listDir()

    when defined(Windows):
        echo "Windows-Install Directory: ", pathnameFromWindowsInstallDir()
        echo "Windows-System Directory : ", pathnameFromWindowsSystemDir()
        echo "Windows-Drives           : ", pathnamesFromWindowsDrives()

#    proc main() =
#        echo normalizePathString("./../..")   #Fail -> ../..
#        echo normalizePathString("./../../")  #Fail -> ../..
#        echo normalizePathString("/../..")    #     -> /
#        echo normalizePathString("/../../")   #     -> /
#        echo normalizePathString("/home")
#        echo normalizePathString(".")
#        echo normalizePathString("./home")
#        echo normalizePathString("/./home")
#        echo normalizePathString("./././.")
#        echo normalizePathString("/./././.")
#        echo normalizePathString("./././home")
#        echo normalizePathString("/./././home")
#        echo normalizePathString("/./home")
#        echo normalizePathString("////home/test/.././../hello/././world////./what/..")
#        echo normalizePathString("////home/test/.././../hello/././world////./what/..///")
#        echo normalizePathString("////home/test/.././../hello/././world////./what/..///.")
#
#
#        let pathname = pathnameFromTempDir()
#        echo pathname.toPathStr & ":"
#        for filepath in pathname.parent.listDir():
#            echo "- ", filepath.toPathStr()
#
#        #echo realpath("..")
#
#    main()