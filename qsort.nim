from math import randomize, random
from sequtils import mapIt
from times import epochTime
import strutils

proc qsort*[T](s: seq[T]): seq[T] =
    if s.len <= 1:
        return s
    let pivot = s[0]
    var less = newSeq[int]()
    var greater = newSeq[int]()
    for i in s[1..s.high]:
        if i <= pivot:
            less.add(i)
        else:
            greater.add(i)
    return qsort(less) & @[pivot] & qsort(greater)

proc swap[T](s: var seq[T], a: int, b: int) =
    let temp = s[a]
    s[a] = s[b]
    s[b] = temp


proc qsort_inline*[T](s: var seq[T]) =
    var stack = newSeq[tuple[low: int, high: int]]()
    stack.add((0, s.high))
    while stack.len > 0:
        let st = stack.pop()
        var pivot_idx = (st.low + st.high) div 2
#        var mid = pivot_idx
        var low = st.low
        var high = st.high
        while low <= high:
            while s[low] < s[pivot_idx]:
                inc low
            while s[pivot_idx] < s[high]:
                dec high
            if low < high:
                swap(s, low, high)
                if pivot_idx == low:
                    pivot_idx = high
                elif pivot_idx == high:
                    pivot_idx = low
                inc low
                dec high
            elif low == high:
                inc low
                dec high
                break

        var nlow = low
        var nhigh = high
        if low > high:
            nlow = low - 1
            nhigh = high + 1
        if nlow - st.low > 1:
            stack.add((st.low, nlow))
        if st.high - nhigh > 1:
            stack.add((nhigh, st.high))

type
  myObj = object
    id* : int
    str* : string

proc `<`*(a,b: myObj): bool =
  result = a.id - b.id < 0

proc `<=`*(a,b: myObj): bool =
  result = a.id - b.id <= 0

proc `==`*(a,b: myObj): bool =
  result = a.id - b.id == 0

proc `$`*(a: myObj): string =
  result = intToStr(a.id) & " " & a.str

when isMainModule:
    randomize()
    var startTime = 0.0
    var endTime = 0.0
    var cumulativeTime = 0.0

    for _ in 1..100:
        var random_list = mapIt(newSeq[int](1000), int, random(1000))
        startTime = epochTime()
        qsort_inline(random_list)
        endTime = epochTime()
        cumulativeTime += endTime - startTime
    echo cumulativeTime

    var float_list = mapIt(newSeq[float](1000), float, random(1.0))
    startTime = epochTime()
    qsort_inline(float_list)
    endTime = epochTime()
    cumulativeTime = endTime - startTime
    echo cumulativeTime

    var obj_list = mapIt(newSeq[myObj](100), myObj, myObj(id:random(1000),str:"stringgg"&intToStr(random(1000))))
#    for i in 1..<100 :
#      echo string($obj_list[i])
    startTime = epochTime()
    qsort_inline(obj_list)
    endTime = epochTime()
    cumulativeTime = endTime - startTime
    echo cumulativeTime
#    for i in 1..<100 :
#      echo string($obj_list[i])
