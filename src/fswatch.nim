# Filesystem-Watcher which executes an program, when an watched file got changed.
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
#   $ -> sizeof(normal/upx+strip) = 49kB / 18kB
#
#   ## Execute ...
#   $ fswatch --verbose --watch:src/ exec echo nim compile src/fswatch.nim
#   $ fswatch --verbose --watch:src/ init echo nim compile src/fswatch.nim


import ./fswatchpkg/fs_watcher_command

proc main() =
    # Einstiegspunkt in die Anwendung: fswatch.
    let fsWatchCommand = (
        newFsWatcherCommand()
        .initWithDefaultConfigFiles()
        .initWithCliArgs()
    )
    let returnCode = fsWatchCommand.doExecute()
    quit(returnCode)

main()
