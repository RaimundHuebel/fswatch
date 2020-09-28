# Module providing a Result-Monad to provide effective error-handling without using exceptions.
#
# license: MIT
# author:  Raimund Hübel <raimund.huebel@googlemail.com>
#
# ## Example
# .. code-block:: Nim
#   import utils.result
#
#   let theAnswer: int =
#       ResultOk[int, string](42)
#       .expect("You should really know the answer")
#       .unwrap()
#   ...
#
# ## compile and run + tooling:
#
#   ## Separated compile and run steps ...
#   $ nim compile [--out:result.exe] result.nim
#   $ ./result[.exe]
#
#   ## In one step ...
#   $ nim compile [--out:result.exe] --run result.nim
#
#   ## Optimal-Compile ...
#   $ nim compile -d:release --opt:size result.nim
#   $ strip --strip-all result  #Funktioniert wirklich
#   $ upx --best result




type ResultKind = enum
    rkOk,
    rkError


type Result*[TOk, TErr] = ref object
    case kind: ResultKind
    of rkOk:
        okValue: TOk
    of rkError:
        errValue: TErr


type ResultAccessError* = ref object of ValueError


# Concept um per `when ... is Stringifyable` der gegebene Generische Typ in ein String konvertiert werden kann.
# Wird benötigt um unwrap und okValue implementieren zu können
type Stringifyable = concept x
    $x is string



proc ResultOk*[TOk, TErr](okValue: TOk): Result[TOk, TErr] {.noSideEffect.} =
    ## Constructs an Ok-Result.
    return Result[TOk, TErr](kind: rkOk, okValue: okValue)


proc ResultError*[TOk, TErr](errValue: TErr): Result[TOk, TErr] {.noSideEffect.} =
    ## Constructs an Error-Result.
    return Result[TOk, TErr](kind: rkError, errValue: errValue)



proc isOk*(self: Result): bool {.noSideEffect.} =
    return self.kind == rkOk


proc isError*(self: Result): bool {.noSideEffect.} =
    return self.kind != rkOk




#proc then*[TOk1, TErr, TOk2](
#    self: Result[TOk1, TErr],
#    mapFn: proc ( value: TOk1 ): Result[TOk2, TErr]
#): Result[TOk2, TErr] {.noSideEffect.} =
#    ## Maps the current Result to a new Result.
#    if self.kind != rkOk:
#        return self;
#    return mapFn(self.okValue)



proc expect*[TOk, TErr](self: Result[TOk, TErr], msg: string): Result[TOk, TErr] {.noSideEffect.} =
    ## Checks if the Result is OK, otherwise raises an ResultAccessError.
    ## Returns the self (Result) for Method-Chaining.
    if self.kind != rkOk:
        raise ResultAccessError(msg: msg)
    return self



proc unwrap*[TOk, TErr](self: Result[TOk, TErr]): TOk {.noSideEffect.} =
    ## Returns the containing value if result is ok,
    ## otherwise raises an ResultAccessError (if error).
    if self.kind != rkOk:
        when TErr is Stringifyable:
            raise ResultAccessError(msg: "ResultAccessError: " & $self.errValue)
        else:
            raise ResultAccessError(msg: "ResultAccessError: Can't provide Value because it is an Error-Result.")
    return self.okValue


proc unwrapOrDefault*[TOk, TErr](self: Result[TOk, TErr], defaultVal: TOk): TOk {.noSideEffect.} =
    ## Unwraps the Result giving the containing value if result is ok,
    ## otherwise returns the given default value.
    if self.kind != rkOk:
        return defaultVal
    return self.okValue


proc unwrapOrRaise*[TOk, TErr](self: Result[TOk, TErr], raiseMsg: string): TOk {.noSideEffect.} =
    ## Unwraps the Result giving the containing value if result is ok,
    ## otherwise raises an Error with the given error message (if error).
    if self.kind != rkOk:
        raise ResultAccessError(msg: raiseMsg)
    return self.okValue



proc value*[TOk, TErr](self: Result[TOk, TErr]): TOk {.noSideEffect,inline.} =
    ## Returns the containing value if result is ok,
    ## otherwise raises an ResultAccessError (if error).
    return self.unwrap()


proc okValue*[TOk, TErr](self: Result[TOk, TErr]): TOk {.noSideEffect,inline.} =
    ## Returns the containing value if result is ok,
    ## otherwise raises an ResultAccessError (if error).
    return self.unwrap()


proc errValue*[TOk, TErr](self: Result[TOk, TErr]): TErr {.noSideEffect.} =
    ## Returns the containing value if result is an error,
    ## otherwise raises an ResultAccessError (if ok).
    if self.kind == rkOk:
        raise ResultAccessError(msg: "Can't provide Error-Value because it is an Ok-Result.")
    return self.errValue
