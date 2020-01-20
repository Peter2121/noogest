# dygraph library wrapper with some additional declarations

import dom

type
  AnnotationObj* {.importc.} = object
    series* : cstring
    x* : cstring
    shortText* : cstring
    text* : cstring
    icon* : cstring
    width* : int
    height* : int
    cssClass* : cstring
    tickHeight* : int
    tickWidth* : int
    tickColor* : cstring
    attachAtBottom* : cstring

type
  Annotation* = ref AnnotationObj
  
type
  SeqAnnot* = seq[Annotation]
  PSeqAnnot* = ref SeqAnnot

type
  AreaObj {.importc.} = object
    x* : int
    y* : int
    w* : int
    h* : int

type
  Area* = ref AreaObj

type
  CanvasObj* {.importc.} = object
    fillStyle* {.importc.} : cstring
    font* {.importc.} : cstring
    width* {.importc.} : int
    height* {.importc.} : int

type
  Canvas* = ref CanvasObj
    
type
  NimDygraphObj* {.importc.} = object
    Plotters* : cstring  # TODO: put correct type
    PointType* : cstring # TODO: put correct type
    
type
  NimDygraph* = ref NimDygraphObj

type 
  UnderlayCallback = proc (canvas : Canvas, area : Area, g : NimDygraphObj)

{.push importcpp.}

type
  DrawCallback = proc (g : NimDygraphObj, is_initial : bool)

type
  ReadyCallback = proc (g : NimDygraphObj)

type
  NimDygraphOptsObj {.importc.} = object
    title* : cstring
    titleHeight* : int
    displayAnnotations* : bool
    axisLabelColor* : cstring
    axisLabelFontSize* : int
    axisLabelWidth* : int
    axisLineColor* : cstring
    axisLineWidth* : float
    axisTickSize* : int
    drawAxesAtZero* : bool
    drawAxis* : bool
    includeZero* : bool
    independentTicks* : bool
    labelsUTC* : bool
    logscale* : bool
    panEdgeFraction* : float
    xAxisHeight* : int
    xRangePad* : float
    yRangePad* : float
    customBars* : bool
    delimiter* : cstring
    errorBars* : bool
    fractions* : bool
    xLabelHeight* : int
    xlabel* : cstring
    y2label* : cstring
    yLabelWidth* : int
    ylabel* : cstring
    connectSeparatedPoints* : bool
    drawGapEdgePoints* : bool
    drawPoints* : bool
    fillGraph* : bool
    pointSize* : int
    stackedGraph* : bool
    stepPlot* : bool
    strokeBorderColor* : string
    strokeBorderWidth* : float
    strokeWidth* : float
    drawXGrid* : bool
    drawYGrid* : bool
    gridLineColor* : cstring
    gridLineWidth* : float
#    showLabelsOnHighlight* : bool
    showRangeSelector* : bool
    showRoller* : bool
    legend* : cstring # always/follow/onmouseover
    height* : int
    rightGap* : int
    width* : int
    digitsAfterDecimal* : int
    hideOverlayOnMouseOut* : bool
    labelsDivWidth* : int
    valueRange* : array[0..1, int]
    underlayCallback* : UnderlayCallback
    drawCallback* : DrawCallback

type
  NimDygraphOpts* = ref NimDygraphOptsObj

proc resize*(ndo : NimDygraphObj)
proc resize*(ndo : NimDygraphObj, width : int, height : int)
proc getOption*(ndo : NimDygraphObj, option : cstring) : int 
proc toString*(ndo : NimDygraphObj) : cstring 
proc updateOptions*(ndo : NimDygraphObj, opts : NimDygraphOptsObj)
proc updateOptions*(ndo : NimDygraphObj, opts : NimDygraphOptsObj, block_redraw : bool)
proc destroy*(ndo : NimDygraphObj)
proc setAnnotations*(ndo : NimDygraphObj, sa : SeqAnnot)
proc ready*(ndo : NimDygraphObj, rc : ReadyCallback)
proc toDomXCoord*(ndo : NimDygraphObj, x : float) : int
proc toDomYCoord*(ndo : NimDygraphObj, y : int64) : int
proc fillRect*(cnv : Canvas, x, y, width, height: int)

{.pop.}

proc Dygraph*(parent : Element, data : cstring) : NimDygraph {.importc.}

proc Dygraph*(parent : Element, data : cstring, opts : NimDygraphOptsObj) : NimDygraph {.importc.}

proc newDygraph*(parent : Element, data : cstring) : NimDygraph {.importc.}
#=
#  new result
#  result = Dygraph(parent, data)

#{.pull importcpp.}

proc newDygraph*(parent : Element, data : cstring, opts : NimDygraphOptsObj) : NimDygraph {.importc.}
# {.exportc.} =
#  new result
#  var nimVar = 89
# use backticks to access Nim symbols within an emit section:
#  {.emit: """fprintf(stdout, "%d\n", cvariable + (int)`nimVar`);""".}

#  result = new Dygraph(parent, data, opts)
#  {.emit: """return new Dygraph(`parent`, `data`, `opts`);""".}
