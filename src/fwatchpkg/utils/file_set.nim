## Class for File-Set in Nim.
##
## author:
##   Raimund Hübel <raimund.huebel@googlemail.com>
##
## example-usage:
## ```nim
##    import utils.file_set
##    let fileSet :FileSet =
##          newFileSet()
##
## build & rund
## ```bash
##   # build:
##   $ nim compile [--run] [-d:release] [--opt:size] src/utils/file_set.nim
##
##   # run:
##   $ src/utils/file_set
##
##   # build && run:
##   $ nim compile --run [-d:release] [--opt:size] src/utils/file_set.nim


import os
import utils/file_stat
import utils/result
import posix


type FileSetEntryType = enum
    fseInclude, fseExclude

type FileSetEntry = object
    ## Structure to describe an inclusion or exclusion to the FileSet
    entryType: FileSetEntryType
    fileTestFn: proc (relativePath: string): bool

type FileSet* = ref object
    ## Class for Handling with multiple Files.
    parentFileSet:    FileSet
    baseDirectory:    string      # Basis-Directory which is walked through.
    fileSetEntries:   seq[FileSetEntry]



proc newFileSet*(baseDirectory :string = os.getCurrentDir()) :FileSet =
    ## Creates a new FileSet, based on the given Directory (default: curr. working dir) when this Method is called.
    ## returns:: {FileSet} new FileSet
    if baseDirectory.len == 0:
        raise newException(ValueError, "invalid param: baseDirectory - must not be empty")
    if not baseDirectory.isAbsolute():
        raise newException(ValueError, "invalid param: baseDirectory - must be absolute")
    var baseDirectory = baseDirectory
    if baseDirectory[baseDirectory.high] != os.DirSep:
        baseDirectory = baseDirectory & os.DirSep
    return FileSet(
        parentFileSet:  nil,
        baseDirectory:  baseDirectory,
        fileSetEntries: @[]
    )



proc newFileSetFromCurrentDir*(subDir: string = "") :FileSet =
    ## Creates a new FileSet, based on current Working-Directory when this Method is called.
    ## By default all Files are excluded, and must be added by using the different include-Methods.
    ## returns:: {FileSet} new FileSet
    if subDir.isAbsolute():
        raise newException(ValueError, "invalid param: subDir - must be relative")
    return newFileSet(os.joinPath(os.getCurrentDir(), subDir))



proc newFileSetFromApplicationDir*(subDir: string = "") :FileSet =
    ## Creates a new FileSet, based on directory where the current Executable is.
    ## returns:: {FileSet} new FileSet
    if subDir.isAbsolute():
        raise newException(ValueError, "invalid param: subDir - must be relative")
    return newFileSet(os.joinPath(os.getAppDir(), subDir))



proc newFileSetFromTempDir*(subDir: string = "") :FileSet =
    ## Creates a new FileSet, based on Temp-Directory of the System.
    ## returns:: {FileSet} new FileSet
    if subDir.isAbsolute():
        raise newException(ValueError, "invalid param: subDir - must be relative")
    return newFileSet(os.joinPath(os.getTempDir(), subDir))



proc newFileSetFromUserHomeDir*(subDir: string = "") :FileSet =
    ## Creates a new FileSet, based on Home-Directory of the current User.
    ## returns:: {FileSet} new FileSet
    if subDir.isAbsolute():
        raise newException(ValueError, "invalid param: subDir - must be relative")
    return newFileSet(os.joinPath(os.getHomeDir(), subDir))



proc newFileSetFromUserConfigDir*(subDir: string = "") :FileSet =
    ## Creates a new FileSet, based on the Config-Directory of the current User.
    ## returns:: {FileSet} new FileSet
    if subDir.isAbsolute():
        raise newException(ValueError, "invalid param: subDir - must be relative")
    return newFileSet(os.joinPath(os.getConfigDir(), subDir))



proc newFileSetFromRootDir*(subDir: string = "") :FileSet =
    ## Creates a new FileSet, based on Root-Directory of the System.
    ## returns:: {FileSet} new FileSet
    if subDir.isAbsolute():
        raise newException(ValueError, "invalid param: subDir - must be relative")
    return newFileSet(
        if subDir.len > 0:
            os.joinPath("/", subDir)
        else:
            "/"
    )


proc wrap*(fileSet :FileSet) :FileSet =
    ## Creates a new FileSet, based on the current FileSet.
    ## returns:: {FileSet} new FileSet
    return FileSet(
        parentFileSet:  fileSet,
        baseDirectory:  fileSet.baseDirectory,
        fileSetEntries: @[]
    )


proc getBaseDirectory*(fileSet :FileSet): string =
    ## Returns the Base-Directory of the FileSet.
    ## returns:: {string}
    return fileSet.baseDirectory



proc reset*(fileSet :FileSet) :FileSet {.discardable.} =
    ## Resets the FileSet to its initial state.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.fileSetEntries = @[]
    return fileSet


proc includeFiles*(fileSet: FileSet, fileTestFn: proc (relativePath: string): bool) :FileSet {.discardable.} =
    ## Includes Files using the given FileTest-Function
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.fileSetEntries.add(
        FileSetEntry(entryType: fseInclude, fileTestFn: fileTestFn)
    )
    return fileSet


proc includeFiles*(fileSet :FileSet, pathGlob :string) :FileSet {.discardable.} =
    ## Includes Files to the File-Set using by Globs.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.includeFiles(
        proc (relativePath: string): bool =
            return 0 == posix.fnmatch(pathGlob, relativePath, posix.FNM_NOESCAPE)
    )
    return fileSet


proc includeAll*(fileSet :FileSet) :FileSet {.discardable.} =
    ## Includes all Files/Directories/Links/... to the File-Set.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.fileSetEntries = @[
        FileSetEntry(
            entryType: fseInclude,
            fileTestFn:
                proc (relativePath: string): bool =
                    return true
        )
    ]
    return fileSet


proc includeAllFiles*(fileSet :FileSet) :FileSet {.discardable.} =
    ## Includes all Files to the File-Set.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.includeFiles(
        proc (relativePath: string): bool =
            let fileStatResult = newFileStat2(fileSet.getBaseDirectory() & relativePath)
            if fileStatResult.isError:
                echo "[WARN] Stat failed for '" & relativePath & " (" & fileStatResult.errValue.errorMessage & ")"
                return false
            return fileStatResult.unwrap().isFile
    )
    return fileSet


proc includeAllDirectories*(fileSet :FileSet) :FileSet {.discardable.} =
    ## Includes all Directories to the File-Set.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.includeFiles(
        proc (relativePath: string): bool =
            let fileStatResult = newFileStat2(fileSet.getBaseDirectory() & relativePath)
            if fileStatResult.isError:
                echo "[WARN] Stat failed for '" & relativePath & " (" & fileStatResult.errValue.errorMessage & ")"
                return false
            return fileStatResult.unwrap().isDirectory
    )
    return fileSet


proc excludeFiles*(fileSet :FileSet, fileTestFn: proc (relativePath: string): bool) :FileSet {.discardable.} =
    ## Excludes Files from the File-Set using the given FileTest-Function.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.fileSetEntries.add(
        FileSetEntry(entryType: fseExclude, fileTestFn: fileTestFn)
    )
    return fileSet


proc excludeFiles*(fileSet :FileSet, pathGlob :string) :FileSet {.discardable.} =
    ## Excludes Files from the File-Set using Globs.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.excludeFiles(
        proc (relativePath: string): bool =
            return 0 == fnmatch(pathGlob, relativePath, posix.FNM_NOESCAPE)
    )
    return fileSet


proc excludeAll*(fileSet :FileSet) :FileSet {.discardable.} =
    ## Excludes all Files/Directories/Links/... from the File-Set.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.fileSetEntries = @[] ## By default, all Files are excluded ...
    return fileSet


proc excludeAllFiles*(fileSet :FileSet) :FileSet {.discardable.} =
    ## Excludes all Files from the File-Set.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.excludeFiles(
        proc (relativePath: string): bool =
            let fileStatResult = newFileStat2(fileSet.getBaseDirectory() & relativePath)
            if fileStatResult.isError:
                echo "[WARN] Stat failed for '" & relativePath & " (" & fileStatResult.errValue.errorMessage & ")"
                return false
            return fileStatResult.unwrap().isFile
    )
    return fileSet


proc excludeAllDirectories*(fileSet :FileSet) :FileSet {.discardable.} =
    ## Excludes all Directories from the File-Set.
    ## returns:: {FileSet} given FileSet for method chaining.
    fileSet.excludeFiles(
        proc (relativePath: string): bool =
            let fileStatResult = newFileStat2(fileSet.getBaseDirectory() & relativePath)
            if fileStatResult.isError:
                echo "[WARN] Stat failed for '" & relativePath & " (" & fileStatResult.errValue.errorMessage & ")"
                return false
            return fileStatResult.unwrap().isDirectory
    )
    return fileSet



proc eachFile*(fileSet :FileSet, callbackFn: proc (relativePath: string)) :FileSet {.discardable.} =
    ## Iterates through each matched File, calculated at call-time.
    ## returns:: {FileSet} given FileSet for method chaining.
    ## @see http://man7.org/linux/man-pages/man3/fnmatch.3.html
    ## @see https://nim-by-example.github.io/procvars/
    ## @see https://rosettacode.org/wiki/Higher-order_functions#Nim
    ## @see https://nim-lang.org/docs/os.html#walkDir.i%2Cstring
    ## @see https://www.rosettacode.org/wiki/Walk_a_directory/Non-recursively#Nim
    ## @see https://rosettacode.org/wiki/Walk_a_directory/Recursively#Nim
    ## @see https://rosettacode.org/wiki/Empty_directory#Nim

    if fileSet.parentFileSet != nil:

        # Wenn Parent-FileSet gegeben, dann iteriere durch dieses ...
        if true:
            fileSet.parentFileSet.eachFile do (relativePath: string):
                var currFileEntryType = fseInclude
                for fileSetEntry in fileSet.fileSetEntries:
                    if currFileEntryType == fileSetEntry.entryType:
                        continue
                    if fileSetEntry.fileTestFn(relativePath) == true:
                        currFileEntryType = fileSetEntry.entryType
                if currFileEntryType == fseInclude:
                    callbackFn(relativePath)

    else:

        # Wenn kein Parent-FileSet gegeben, dann iteriere durch das Datei-System ...
        if (fileSet.fileSetEntries.len > 0):
            for relativePath in os.walkDirRec(
                dir = fileSet.baseDirectory,
                relative = true,
                yieldFilter  = { pcFile, pcDir, pcLinkToFile, pcLinkToDir },
                followFilter =  { pcDir, pcLinkToDir }
            ):
                var currFileEntryType = fseExclude
                for fileSetEntry in fileSet.fileSetEntries:
                    if currFileEntryType == fileSetEntry.entryType:
                        continue
                    if fileSetEntry.fileTestFn(relativePath) == true:
                        currFileEntryType = fileSetEntry.entryType
                if currFileEntryType == fseInclude:
                    callbackFn(relativePath)

    return fileSet



proc files*(fileSet :FileSet) :seq[string] =
    ## Gives a list of qualified Filepaths, calculated at call-time.
    ## returns:: {seq[string]} a list of qualified Filepaths (eg. @["/tmp/file1.txt", "/tmp/file2.txt"])
    var files: seq[string] = @[]
    fileSet.eachFile do (relativePath: string):
        files.add( relativePath )
    return files



proc toString*(fileSet :FileSet) :string =
    ## Gives a String-Representation of the FileSet
    return "FileSet('" & fileSet.baseDirectory & "')"



proc `$`*(fileSet :FileSet) :string  {.inline.} =
    ## Gives a String-Representation of the FileSet
    return fileSet.toString()



# Beispiel: Tests
when isMainModule:
    let fileSet =
        newFileSetFromApplicationDir("../..")
          .includeFiles("src/*")
          .includeFiles("test/*")
          .excludeFiles("*.sh")
          .excludeFiles("*.md")
          .excludeFiles("*/.*")
          .excludeFiles("test/utils/*")
          .excludeAllDirectories()
          .wrap()
          .excludeAllFiles()
          .excludeAllDirectories()
          .includeFiles("*.nim")

    echo "FileSet - BaseDir: " & fileSet.getBaseDirectory()
    echo "FileSet - Content:"
    fileSet.eachFile do (relativePath: string):
        echo "- " & relativePath
