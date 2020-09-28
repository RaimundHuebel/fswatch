# Minimal Wrapper for Inotify-API
#
# see: https://github.com/zah/grip-lang/blob/master/lib/posix/inotify.nim
# see: /usr/include/x86_64-linux-gnu/sys/inotify.h

type InotifyFileDescriptor*  = cint
type InotifyWatchDescriptor* = cint
type ErrorCode*              = cint

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
