# Package

version       = "0.1.0"
author        = "Raimund Hübel"
description   = "Tool for watching the Filesystem and executing some commands when files has been changed."
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["fswatch"]



# Dependencies

requires "nim >= 1.2.0"
#requires "pathname >= 0.1.0"
