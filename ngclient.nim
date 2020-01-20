import htmlgen,dom,strutils,nminajax,dygraph,sequtils,json,strscans

  
const
  MAX_TEMP_CHANNEL : int = 4
  TEMP_REQ_INTERVAL : int = 30000 #milliseconds
  GRAPH_MIN_TEMP : int = 16
  GRAPH_MAX_TEMP : int = 26
  GRAPH_WIDTH : int = 600
  GRAPH_HEIGHT : int = 400
  ACT_DRAW_WIDTH : float = 20000
#  divId : string = "dygdiv"  

var
  tempGraphs : array[1..MAX_TEMP_CHANNEL, NimDygraph]
  arrSeqAct :  array[1..MAX_TEMP_CHANNEL, seq[JsonNode]]

proc fillActionArea(canvas : Canvas, area : Area, g : NimDygraphObj) {.exportc.} =
  let strdg = g.toString()
  var ch : int
  var intDT : int
  var floatDT : float
  var strAct : string
  var intRes : int
  var canvLBX : int
  var canvLTX: int
  var canvRBX : int
  var canvRTX : int
  var canvLBY : int
  var canvLTY: int
  var canvRBY : int
  var canvRTY : int
  echo "fillActionArea got area: ", area.x, area.y, area.w, area.h
  if(scanf($strdg, "[Dygraph dygdiv$i]", ch)) :
    if(arrSeqAct[ch] == @[]) :
      echo "fillActionArea: no annotaions data for channel: ", ch
      return
    else:
      echo "fillActionArea: trying to show actions for channel: ", ch
      for sa in arrSeqAct[ch] :
# [{"Channel":3,"DTime":"2020/01/06 20:22:25","Action":"on","Result":1},
#  {"Channel":3,"DTime":"2020/01/18 22:57:16","Action":"on","Result":1},
#  {"Channel":3,"DTime":"2020/01/18 23:10:20","Action":"on","Result":1}]
        intDT=sa["DTime"].getInt()
        floatDT=1000.0*intDT.toFloat()
        strAct=sa["Action"].getStr()
        intRes=sa["Result"].getInt()
        canvLBX=g.toDomXCoord(floatDT-ACT_DRAW_WIDTH)
        canvRBX=g.toDomXCoord(floatDT+ACT_DRAW_WIDTH)
        canvLTX=canvLBX
        canvRTX=canvRBX
        canvLBY=g.toDomYCoord(GRAPH_MIN_TEMP)
        canvLTY=g.toDomYCoord(GRAPH_MAX_TEMP)
        canvRBY=canvLBY
        canvRTY=g.toDomYCoord(GRAPH_MAX_TEMP)
        case strAct :
          of "on" :
            if(intRes==0) :
              canvas.fillStyle = "Red"
            else :
              canvas.fillStyle = "LightSalmon"
          of "off" :
            if(intRes==0) :
              canvas.fillStyle = "Blue"
            else :
              canvas.fillStyle = "DeepSkyBlue"
        canvas.fillRect(canvLTX,area.y,canvRTX-canvLTX,area.h)        

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
  var cstrData : cstring
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
  cstrData=cstring(strData)
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
  opts.valueRange[0] = GRAPH_MIN_TEMP
  opts.valueRange[1] = GRAPH_MAX_TEMP
  opts.underlayCallback = fillActionArea
  tempGraphs[channel] = newDygraph(parent,cstrData,opts[])

proc cbGetAct(str : cstring) {.exportc.} =
  var pSeqAnn : PSeqAnnot
  var chan : int
  var i : int
  let strData = $str
  if(strData.len()<2) :
    echo "cbGetAct received no data in answer for actions"
    return
  else:
    echo "cbGetAct got data: ", strData
  let jsonNode = parseJson(strData)
  let seqAct = jsonNode.getElems()
  if(seqAct != @[]) :
    chan = seqAct[0]["Channel"].getInt()
    arrSeqAct[chan] = seqAct

proc getTempOnChannel(i : int) {.exportc.} =
  var nmax : int = 40
  var conf = minAjaxConf()
  conf.url = "/temp"
  conf.rtype = "GET"
  conf.data = "channel=" & intToStr(i) & "&nmax=" & intToStr(nmax)
  conf.success = "createGraph"
  conf.debugLog = true
  minAjax(conf[])

proc getActOnChannel(ch : int) {.exportc.} =
  var nmax : int = 40
  var conf = minAjaxConf()
  conf.url = "/act"
  conf.rtype = "GET"
  conf.data = "channel=" & intToStr(ch) & "&nmax=" & intToStr(nmax)
  conf.success = "cbGetAct"
  conf.debugLog = true
  minAjax(conf[])

proc startTempTimer() {.exportc.} =
  for i in 1..MAX_TEMP_CHANNEL :
    getActOnChannel(i)
    discard nimSetInterval(cstring("getActOnChannel"), TEMP_REQ_INTERVAL, cstring(intToStr(i)))
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

