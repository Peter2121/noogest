import htmlgen,dom,strutils,nminajax,dygraph,sequtils

const
  MAX_TEMP_CHANNEL : int = 4
  TEMP_REQ_INTERVAL : int = 60000 #milliseconds
  GRAPH_MIN_TEMP : int = 16
  GRAPH_MAX_TEMP : int = 26
  GRAPH_WIDTH : int = 600
  GRAPH_HEIGHT : int = 400

var
  tempGraphs : array[1..MAX_TEMP_CHANNEL, NimDygraph]

proc printData(str : cstring) {.exportc.} =
  var infoDiv = document.getElementById("info")
  infoDiv.innerHTML = str

proc getSelectedOptionText(opts : seq[OptionElement]) : string =
  for i in opts.low..opts.high :
    if(opts[i].selected == true) :
      result = $opts[i].text

proc getSelectedOptionValue(opts : seq[OptionElement]) : string =
  for i in opts.low..opts.high :
    if(opts[i].selected == true) :
      result = $opts[i].value

proc btnActionOnClick() {.exportc.} =
  let optsChannel = document.getElementById("selchan").options
  let optsCommand = document.getElementById("selcmd").options
  let inpLevel = document.getElementById("inpLevel")
  let divInfo = document.getElementById("info")
  var selectedChannel : string
  var selectedCommand : string
  var setLevel : int
  var res : int = 0
  var strLevel : string

  selectedChannel = getSelectedOptionValue(optsChannel)
  selectedCommand = getSelectedOptionValue(optsCommand)
  strLevel = $getValue("inpLevel")

  var conf = minAjaxConf()
  conf.url = "/data"
  conf.rtype = "GET"
  conf.data = "channel=" & selectedChannel & "&command=" & selectedCommand & "&level=" & strLevel
  conf.success = "printData"
  conf.debugLog = true
  minAjax(conf[])

proc createGraph*(str : cstring) {.exportc.} =
  var strData = $str
  var channel : int = 0
  var cstr : cstring
  var divId = "dygdiv"
  var strChanName : string

  var lines : seq[string]
  lines = strData.splitLines()
  try:
    channel = parseInt(lines[lines.low])
  except:
    channel = 0
  if( (lines.low+1) <= lines.high) :
    strChanName = lines[lines.low+1]
  lines.delete(lines.low,lines.low+1)
  strData = lines.join("\n")
  cstr=cstring(strData)
  divId &= intToStr(channel)
  var parent = document.getElementById(divId)
  if (tempGraphs[channel] != nil) : tempGraphs[channel][].destroy()
  var opts = NimDygraphOpts()
  opts.title = cstring("Channel: " & strChanName)
#  GRAPH_MIN_TEMP : int = 10
#  GRAPH_MAX_TEMP : int = 40
#  GRAPH_WIDTH : int = 600
#  GRAPH_HEIGHT : int = 400
  opts.displayAnnotations = true
  opts.axisLineColor = "black"
  opts.axisLineWidth = 2.0
  opts.axisLabelColor = "black"
  opts.axisLabelFontSize = 12
  opts.axisLabelWidth = 50
  opts.axisTickSize = 2
  opts.xLabelHeight = 18
  opts.yLabelWidth = 18
  opts.drawAxis = true
  opts.drawXGrid = false
  opts.drawYGrid = true
  opts.strokeWidth = 1
  opts.gridLineColor = "grey"
  opts.gridLineWidth = 1.0
  opts.connectSeparatedPoints = true
  opts.drawPoints = true
  opts.independentTicks = true
  opts.pointSize = 2
#  opts.showLabelsOnHighlight = true
  opts.digitsAfterDecimal = 1
  opts.hideOverlayOnMouseOut = false
  opts.legend = "follow"
  opts.labelsDivWidth = 250
  opts.height = GRAPH_HEIGHT
  opts.width = GRAPH_WIDTH
  opts.valueRange = [0, 0]
  opts.valueRange[0]=GRAPH_MIN_TEMP
  opts.valueRange[1]=GRAPH_MAX_TEMP
  tempGraphs[channel] = newDygraph(parent,cstr,opts[])

proc getTempOnChannel(i : int) {.exportc.} =
  var nmax : int = 40
  var conf = minAjaxConf()
  conf.url = "/temp"
  conf.rtype = "GET"
  conf.data = "channel=" & intToStr(i) & "&nmax=" & intToStr(nmax)
  conf.success = "createGraph"
  conf.debugLog = true
  minAjax(conf[])

proc startTempTimer() {.exportc.} =
  for i in 1..MAX_TEMP_CHANNEL :
    getTempOnChannel(i)
    discard nimSetInterval(cstring("getTempOnChannel"), TEMP_REQ_INTERVAL, cstring(intToStr(i)))

#proc getTempAllChannels() {.exportc.} =
#  for i in 1..MAX_TEMP_CHANNEL :
#    getTempOnChannel(i)
#    sleep(3000)

proc btnTempOnClick() {.exportc.} =
  let divInfo = document.getElementById("info")
  let optsChannel = document.getElementById("selchan").options
  var res : int = 0
  var selectedChannel : string
  var channel : int

  selectedChannel = getSelectedOptionValue(optsChannel)
  try:
    channel = parseInt(selectedChannel)
  except:
    channel = 0

  getTempOnChannel(channel)

