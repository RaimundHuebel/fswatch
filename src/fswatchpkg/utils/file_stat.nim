# Module providing a plattform independent API to get Information about File-System-Entries.
#
# license: MIT
# author:  Raimund Hübel <raimund.huebel@googlemail.com>
#
# ## compile and run + tooling:
#
#   ## Seperated compile and run steps ...
#   $ nim compile [--out:file_stat.exe] file_stat.nim
#   $ ./file_stat[.exe]
#
#   ## In one step ...
#   $ nim compile [--out:file_stat.exe] --run file_stat.nim
#
#   ## Optimal-Compile ...
#   $ nim compile -d:release --opt:size file_stat.nim
#   $ strip --strip-all file_stat  #Funktioniert wirklich
#   $ upx --best file_stat
#
# ## Example
# .. code-block:: Nim
#   import utils/file_stat
#   import utils/result
#   ...
#
# ## See Also:
# @see https://nim-lang.org/docs/docgen.html
# @see https://nim-lang.org/documentation.html
# @see https://ruby-doc.org/core-2.5.3/FileTest.html
# @see https://github.com/nim-lang/Nim/blob/master/lib/posix/posix_other_consts.nim
# @see https://github.com/nim-lang/Nim/blob/master/lib/posix/posix_other.nim
# @see https://github.com/nim-lang/Nim/blob/master/lib/posix/posix.nim
# @see https://github.com/nim-lang/Nim/blob/master/lib/pure/os.nim
# @see https://github.com/nim-lang/Nim/blob/master/lib/system/sysio.nim
# @see file://usr/include/asm-generic/errno-base.h
# @see man 2 stat


import ./result


when defined(Posix):
    import posix

    # for file_stat.isGroupMember(...)
    proc group_member*(gid: cint): cint {.importc, header: "<unistd.h>", noSideEffect.}

else:
    # TODO: Support other Platforms ...
    {.fatal: "The current platform is not supported by utils.file_stat!".}



type FileStat* = ref object
    result:    cint
    errorcode: cint
    stat:      posix.Stat



type FileStatError* = ref object
    ## Error-Object describing an Error which occoured while retrieving the FileStat.
    errorcode: cint
    errormsg:  string


proc errorCode*(self: FileStatError): int {.noSideEffect.} =
    ## Returns the internal ErrorCode of the FileStatError.
    return self.errorcode


proc errorMessage*(self: FileStatError): string {.noSideEffect.} =
    ## Returns the resolved Error-Message of the FileStatError.
    if self.errormsg == "":
        self.errormsg = $strerror(self.errorcode)
    return self.errormsg


proc isError*(self: FileStatError): bool {.noSideEffect.} =
    ## Returns true if the FileStat of the File could be determined because of any error has happened.
    ## Returns always true.
    return true


proc isNotExistingError*(self: FileStatError): bool {.noSideEffect.} =
    ## Returns true if the FileStat of the File could be determined because the File-System-Entry is not existing.
    ## Returns false otherwise.
    return self.errorcode == ENOENT


proc isAccessError*(self: FileStatError): bool {.noSideEffect.} =
    ## Returns true if the FileStat of the File could be determined because the File-System-Entry is not accessible.
    ## Returns false otherwise.
    return self.errorcode == EACCES


proc isLoopError*(self: FileStatError): bool {.noSideEffect.} =
    ## Returns true if the FileStat of the File could be determined because there are where to many Symbolic Links hitten.
    ## Returns false otherwise.
    return self.errorcode == ELOOP


proc isNotDirectoryError*(self: FileStatError): bool {.noSideEffect.} =
    ## Returns true if the FileStat of the File could be determined because an entry in the Path was not a Directory.
    ## Returns false otherwise.
    return self.errorcode == ENOTDIR


proc isNoMemoryError*(self: FileStatError): bool {.noSideEffect.} =
    ## Returns true if the FileStat of the File could be determined because no more kernel-memory is available.
    ## Returns false otherwise.
    return self.errorcode == ENOMEM


proc isBadFileDescriptorError*(self: FileStatError): bool {.noSideEffect.} =
    ## Returns true if the FileStat of the File could be determined because of invalid FileDescriptor.
    ## Returns false otherwise.
    return self.errorcode == EBADF


#proc isOverflowError*(self: FileStatError): bool {.noSideEffect.} =
#    ## Returns true if the FileStat of the File could be determined because of an overflow.
#    ## Returns false otherwise.
#    return self.errorcode == EOVERFLOW


#proc isPathnameToLongError*(self: FileStatError): bool {.noSideEffect.} =
#    ## Returns true if the FileStat of the File could be determined because the given Pathname was to long.
#    ## Returns false otherwise.
#    return self.errorcode == ENAMETOLONG


proc toString*(self: FileStatError): string {.inline,noSideEffect.} =
    ## Returns Error-Message of the FileStatError.
    return self.errorMessage()


proc `$`*(self: FileStatError): string {.inline,noSideEffect.} =
    ## Returns Error-Message of the FileStatError.
    return self.toString()



proc newFileStat*(path: string, followSymlink: bool = false): FileStat =
    ## Constructs a new FileStat for the given File/Directory-Path.
    ## @param path
    ##   The Path of the File-System-Entry which shall be file/Directory stated.
    ## @param followSymlink
    ##   If true then if path points to a Symlink, the stat Symlink-Target will be returned,
    ##   otherwise if false, the stat of the Symlink itself is returned (default).
    ## @returns A FileStat-Instance.
    var fileStat = FileStat()

    # if followSymlink == false than get the State
    # @see https://stackoverflow.com/questions/3984948/how-to-figure-out-if-a-file-is-a-link
    if followSymlink == true:
        fileStat.result = posix.stat(path, fileStat.stat)
    else:
        fileStat.result = posix.lstat(path, fileStat.stat)

    if fileStat.result < 0:
        fileStat.errorcode = errno
        if fileStat.errorcode != ENOENT and fileStat.errorcode != ENOTDIR:
            echo "[INFO] newFileStat() - stat return value ", fileStat.result, " < 0 (errno: ", fileStat.errorcode ,", path: ", path ,")"
    elif fileStat.result > 0:
        echo "[INFO] newFileStat() - stat return value ", fileStat.result, " > 0 -> UNEXPECTED RETURN VALUE"
        fileStat.result = 0
        fileStat.errorcode = 0

    return fileStat



proc newFileStat2*(path: string, followSymlink: bool = false): Result[FileStat, FileStatError] =
    ## Constructs a new FileStat for the given File/Directory-Path.
    ## @param path
    ##   The Path of the File-System-Entry which shall be file/Directory stated.
    ## @param followSymlink
    ##   If true then if path points to a Symlink, the stat Symlink-Target will be returned,
    ##   otherwise if false, the stat of the Symlink itself is returned (default).
    ## @returns A Result containing the FileStat on Success or a FileStatError on Failure.
    let fileStat = newFileStat(path, followSymlink)
    if fileStat.result < 0:
        return ResultError[FileStat, FileStatError](FileStatError(errorcode: fileStat.errorcode))
    else:
        return ResultOk[FileStat, FileStatError](fileStat)



proc isExisting*(self: FileStat): bool {.inline,noSideEffect.} =
    ## Returns true if the stated Path points to an Existing / Accessible File-System-Entry at the time of newFileStat().
    ## Returns false otherwise.
    return self.result == 0


proc isFile*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Regular File at the time of newFileStat().
    ## Returns false otherwise.
    return self.result == 0 and posix.S_ISREG(self.stat.st_mode)


proc isDirectory*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Directory at the time of newFileStat().
    ## Returns false otherwise.
    return self.result == 0 and posix.S_ISDIR(self.stat.st_mode)


proc isSymlink*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Symbolic Link at the time of newFileStat().
    ## Returns false otherwise.
    return self.result == 0 and posix.S_ISLNK(self.stat.st_mode)


proc isSocket*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Socket File at the time of newFileStat().
    ## Returns false otherwise.
    ## TODO: testen
    return self.result == 0 and posix.S_ISSOCK(self.stat.st_mode)


proc isFifo*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Fifo File at the time of newFileStat().
    ## Returns false otherwise.
    ## TODO: testen
    return self.result == 0 and posix.S_ISFIFO(self.stat.st_mode)


proc isPipe*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Fifo File at the time of newFileStat().
    ## Returns false otherwise.
    ## TODO: testen
    return self.result == 0 and posix.S_ISFIFO(self.stat.st_mode)


proc isCharacterDevice*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Character Device File at the time of newFileStat().
    ## Returns false otherwise.
    return self.result == 0 and posix.S_ISCHR(self.stat.st_mode)


proc isBlockDevice*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Block Device File at the time of newFileStat().
    ## Returns false otherwise.
    return self.result == 0 and posix.S_ISBLK(self.stat.st_mode)


proc isDevice*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the stated Path points to a Device File at the time of newFileStat().
    ## Returns false otherwise.
    return self.result == 0 and (posix.S_ISCHR(self.stat.st_mode) or posix.S_ISBLK(self.stat.st_mode))


proc userId*(self: FileStat): uint32 {.noSideEffect.}  =
    ## Returns the User-Id of the stated Path.
    ## Returns 0 if the FileStat is in Error-State.
    if self.result == 0:
        return self.stat.st_uid
    else:
        return 0


proc groupId*(self: FileStat): uint32 {.noSideEffect.}  =
    ## Returns the User-Id of the stated Path.
    ## Returns 0 if the FileStat is in Error-State.
    if self.result == 0:
        return self.stat.st_gid
    else:
        return 0


proc fileSizeInBytes*(self: FileStat): int64 {.noSideEffect.}  =
    ## Returns the size of the stated Path in Bytes (only for regular Files and SymLinks).
    ## Returns -1 if the FileStat is in Error-State or the FileType does not support File-Size.
    if self.result == 0:
        return self.stat.st_size
    else:
        return -1


proc countHardLinks*(self: FileStat): int {.noSideEffect.}  =
    ## Returns the count of Hard-Links of the stated Path.
    ## Returns -1 if the FileStat does not support count of Hard-Links.
    if self.result == 0:
        return self.stat.st_nlink.int
    else:
        return -1


proc preferedIoBlockSizeInBytes*(self: FileStat): int {.noSideEffect.}  =
    ## Returns the prefered block size of the stated Path for efficient IO.
    ## Returns -1 if the FileStat is in Error-State or the FileType does not support Prefered Block-Size.
    if self.result == 0:
        return self.stat.st_blksize
    else:
        return -1


proc lastAccessTime*(self: FileStat): Time {.noSideEffect.}  =
    ## Returns the Time when the stated Path was last accessed.
    ## Returns 0.Time if the FileStat is in Error-State or the FileType does not support Prefered Block-Size.
    if self.result == 0:
        return self.stat.st_atime
    else:
        return 0.Time


proc lastChangeTime*(self: FileStat): Time {.noSideEffect.}  =
    ## Returns the Time when the content of the stated Path was last changed.
    ## Returns 0.Time if the FileStat is in Error-State.
    if self.result == 0:
        return self.stat.st_mtime
    else:
        return 0.Time


proc lastStateChangeTime*(self: FileStat): Time {.noSideEffect.}  =
    ## Returns the Time when the state of stated Path was last changed.
    ## Returns 0.Time if the FileStat is in Error-State.
    if self.result == 0:
        return self.stat.st_ctime
    else:
        return 0.Time


proc isUserOwned*(self: FileStat): bool =
    ## Returns true if the named file exists and the effective used id of the calling process is the owner of the file.
    ## Returns false otherwise.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-owned-3F
    return self.stat.st_uid == posix.geteuid()


proc isGroupOwned*(self: FileStat): bool =
    ## Returns true if the named file exists and the effective group id of the calling process is the owner of the file.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-grpowned-3F
    ## ACHTUNG:
    ##   im Gegensatz zur Ruby-Version wird hier geprüft ob der Datei-System-Eintrag wirklich
    ##   die Gruppen-Id das aktuell effektiven Nutzers hat, und NICHT ob der effektive Nutzer
    ##   zur Gruppe der Datei gehört. Für diesen Zweck ist #isGroupMember gedacht.
    when defined(Posix):
        return self.stat.st_gid == posix.getegid()
        #return 0 != posix.group_member(self.stat.st_gid)
    elif defined(Windows):
        return false
    else:
        echo "[WARN] file_stat.isGroupOwned is not implemented for current Architecture."
        return false


proc isGroupMember*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the named file exists and the effective user is member to the group of the the file.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see file_stat.isUserOwned
    ## @see file_stat.isGroupOwned
    ## @see file_stat.isGroupMember
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-grpowned-3F
    ## ACHTUNG:
    ##   diese Funktion ist äquivalent zu Rubies FileTest.group_owned?
    when defined(Posix):
        return group_member(self.stat.st_gid.cint) != 0
    elif defined(Windows):
        return false
    else:
        echo "[WARN] file_stat.isGroupMember is not implemented for current Architecture."
        return false


proc isReadable*(self: FileStat): bool =
    ## Returns true if the named file exists and the file can be readed by the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    when defined(Posix):
        if self.result != 0:
            return false
        result = false
        result = result or ((self.stat.st_mode.cint and posix.S_IROTH) != 0)
        result = result or ((self.stat.st_mode.cint and posix.S_IRUSR) != 0 and self.stat.st_uid == posix.geteuid())
        result = result or ((self.stat.st_mode.cint and posix.S_IRGRP) != 0 and group_member(self.stat.st_gid.cint) != 0)
        return result
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isReadable is not implemented for current Architecture."
        return false


proc isReadableByUser*(self: FileStat): bool =
    ## Returns true if the named file exists and the file can be,
    ## by the user readable bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IRUSR) != 0 and self.stat.st_uid == posix.geteuid()
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isReadableByUser is not implemented for current Architecture."
        return false


proc isReadableByGroup*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the named file exists and the file can be readed,
    ## by the the group bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IRGRP) != 0 and group_member(self.stat.st_gid.cint) != 0
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isReadableByGroup is not implemented for current Architecture."
        return false


proc isReadableByOther*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the named file exists and the file can be readed,
    ## by the the other bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IROTH) != 0
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isReadableByOther is not implemented for current Architecture."
        return false


proc isWritable*(self: FileStat): bool =
    ## Returns true if the named file exists and the file can be written by the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-writable-3F
    when defined(Posix):
        if self.result != 0:
            return false
        result = false
        result = result or ((self.stat.st_mode.cint and posix.S_IWOTH) != 0)
        result = result or ((self.stat.st_mode.cint and posix.S_IWUSR) != 0 and self.stat.st_uid == posix.geteuid())
        result = result or ((self.stat.st_mode.cint and posix.S_IWGRP) != 0 and group_member(self.stat.st_gid.cint) != 0)
        return result
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isWritable is not implemented for current Architecture."
        return false


proc isWritableByUser*(self: FileStat): bool =
    ## Returns true if the named file exists and the file can be written,
    ## by the user readable bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IWUSR) != 0 and self.stat.st_uid == posix.geteuid()
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isWritableByUser is not implemented for current Architecture."
        return false


proc isWritableByGroup*(self: FileStat): bool =
    ## Returns true if the named file exists and the file can be written,
    ## by the the group bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IWGRP) != 0 and group_member(self.stat.st_gid.cint) != 0
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isWritableByGroup is not implemented for current Architecture."
        return false


proc isWritableByOther*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the named file exists and the file can be written,
    ## by the the other bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IWOTH) != 0
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isWritableByOther is not implemented for current Architecture."
        return false


proc isExecutable*(self: FileStat): bool =
    ## Returns true if the named file exists and the file can be executed by the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-executable-3F
    when defined(Posix):
        if self.result != 0:
            return false
        result = false
        result = result or ((self.stat.st_mode.cint and posix.S_IXOTH) != 0)
        result = result or ((self.stat.st_mode.cint and posix.S_IXUSR) != 0 and self.stat.st_uid == posix.geteuid())
        result = result or ((self.stat.st_mode.cint and posix.S_IXGRP) != 0 and group_member(self.stat.st_gid.cint) != 0)
        return result
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isExecutable is not implemented for current Architecture."
        return false


proc isExecutableByUser*(self: FileStat): bool  =
    ## Returns true if the named file exists and the file can be executed,
    ## by the user readable bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IXUSR) != 0 and self.stat.st_uid == posix.geteuid()
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isExecutableByUser is not implemented for current Architecture."
        return false


proc isExecutableByGroup*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the named file exists and the file can be executed,
    ## by the the group bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IWGRP) != 0 and group_member(self.stat.st_gid.cint) != 0
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isExecutableByGroup is not implemented for current Architecture."
        return false


proc isExecutableByOther*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the named file exists and the file can be executed,
    ## by the the other bit of the effective user.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    ## TODO: testen
    when defined(Posix):
        return self.result == 0 and (self.stat.st_mode.cint and posix.S_IWOTH) != 0
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isExecutableByOther is not implemented for current Architecture."
        return false


proc isEmpty*(self: FileStat): bool {.noSideEffect.}  =
    ## Returns true if the named file exists and the file has zero size.
    ## Returns false otherwise.
    ## Returns always false on Windows.
    ## @see https://ruby-doc.org/core-2.5.3/FileTest.html#method-i-readable-3F
    when defined(Posix):
        return self.result == 0 and self.stat.st_size == 0
    #elif defined(Windows):
    #    return false
    else:
        echo "[WARN] file_stat.isEmpty is not implemented for current Architecture."
        return false
