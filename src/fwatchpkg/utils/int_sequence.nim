## Class for Numeric Sequences in Nim.
##
## siehe:
##   - https://nim-lang.org/
##   - https://nim-lang.org/docs/tut1.html
##   - https://nim-lang.org/docs/unittest.html
##   - https://github.com/nim-lang/Nim/wiki/Tips-and-tricks
##
## author:
##   Raimund Hübel <raimund.huebel@googlemail.com>


import strutils


type IntSequence* = ref object
    ## Class for handling with Int-Sequences. Usefull to generate Unique-Values inside a specific Scope.
    startVal :int
    stepVal  :int
    currVal  :int



proc newIntSequence*(start :int = 0, step :int = 1) :IntSequence =
    ## Creates a new IntSequence.
    ## param:: start - Start of the IntSequence (optional, default: 0)
    ## param:: step  - Stepping of the IntSequence (optional, default: 0, != 0)
    ## returns:: {IntSequence} new IntSequence
    assert step != 0
    return IntSequence(startVal: start, stepVal: step, currVal: start)



proc reset*(seq :IntSequence) :IntSequence {.discardable.} =
    ## Resets the IntSequence to its initial state.
    ## returns:: {:IntSequence} given IntSequence for method chaining.
    seq.currVal = seq.startVal
    return seq



proc next*(seq :IntSequence) :int =
    ## Returns next IntSequence-Value and increases the IntSequence.
    ## returns:: {:int} new IntSequence-Value
    result = seq.currVal
    seq.currVal += seq.stepVal
    return result



proc nextStr*(seq :IntSequence, formatStr :string = "$#") :string =
    ## Returns next IntSequence-Value as String which can be formated and increases the IntSequence.
    ## param:: start - Start of the IntSequence (optional, default: 0)
    ## returns:: {:string} new IntSequence-Value
    #return format("%d", seq.next())
    return formatStr.format(seq.next())



proc start*(seq :IntSequence) :int =
    ## Returns the Start-Value of the IntSequence.
    ## returns:: {:int}
    return seq.startVal



proc step*(seq :IntSequence) :int =
    ## Returns the Step-Value of the IntSequence.
    ## returns:: {:int}
    return seq.stepVal



proc current*(seq :IntSequence) :int =
    ## Returns the current Value of the IntSequence, which would be returned by #next.
    ## returns:: {:int}
    return seq.currVal
