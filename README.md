# Nim FsWatch

[![nimble](https://raw.githubusercontent.com/yglukhov/nimble-tag/master/nimble.png)](https://github.com/yglukhov/nimble-tag)



## Introduction

Tool to execute commands, when something on the watched file system changes.



## Get Started

Install FsWatch

   ```shell
   $ nimble install fswatch
   ```


Using FsWatch as Tool:

   ```shell
   # Show help
   $ fswatch help

   # Watch files and execute echo-command when file changed.
   $ fswatch --watch:src --watch:test exec echo "file changed: {}"

   # Create config-file and execute it ...
   $ fswatch --watch:src --watch:test init echo "file changed: {}"
   $ fswatch exec
   ```


Using FsWatch as library:

   ```nim
   import fswatchpkg/file_watcher

   ```

## Develop

### Running Development-Version

   ```shell
   $ nimble run fswatch ...
   ```


### Build complete project

   ```shell
   $ make build
   ```

### Running Tests

   ```shell
   $ nimble test
   ```



## Links

- [Repository of FsWatch](https://github.com/RaimundHuebel/fswatcher)
