# dygraph library wrapper

import dom

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

type
  NimDygraphOpts* = ref NimDygraphOptsObj

type
  NimDygraphObj {.importc.} = object
    Plotters* : cstring  # TODO: put correct type
    PointType* : cstring # TODO: put correct type

proc resize*(ndo : NimDygraphObj) {.importc.}
proc resize*(ndo : NimDygraphObj, width : int, height : int) {.importc.}
proc toString*(ndo : NimDygraphObj) {.importc.}
proc updateOptions*(ndo : NimDygraphObj, opts : NimDygraphOptsObj) {.importc.}
proc updateOptions*(ndo : NimDygraphObj, opts : NimDygraphOptsObj, block_redraw : bool) {.importc.}
proc destroy*(ndo : NimDygraphObj) {.importc.}

type
  NimDygraph* = ref NimDygraphObj

proc Dygraph*(parent : Element, data : cstring) : NimDygraph {.importc.}

proc Dygraph*(parent : Element, data : cstring, opts : NimDygraphOptsObj) : NimDygraph {.importc.}

#proc newDygraph*(parent : Element, data : cstring) : NimDygraph {.importc.}
#=
#  new result
#  result = Dygraph(parent, data)

proc newDygraph*(parent : Element, data : cstring, opts : NimDygraphOptsObj) : NimDygraph {.importc.}
# {.exportc.} =
#  new result
#  var nimVar = 89
# use backticks to access Nim symbols within an emit section:
#  {.emit: """fprintf(stdout, "%d\n", cvariable + (int)`nimVar`);""".}

#  result = new Dygraph(parent, data, opts)
#  {.emit: """return new Dygraph(`parent`, `data`, `opts`);""".}
