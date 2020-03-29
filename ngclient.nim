import htmlgen,dom,strutils,nminajax,dygraph,sequtils,json,strscans
import noojsonconst
  
const
  MAX_TEMP_CHANNEL : int = 4
  TEMP_REQ_INTERVAL : int = 30000 #milliseconds
  GRAPH_MIN_TEMP : int = 16
  GRAPH_MAX_TEMP : int = 26
  GRAPH_WIDTH : int = 600
  GRAPH_HEIGHT : int = 400
  ACT_DRAW_WIDTH : float = 20000
  ACT_DRAW_MIN_WIDTH_PIX : int = 2
#  divId : string = "dygdiv"  

var
  tempGraphs : array[1..MAX_TEMP_CHANNEL, NimDygraph]
  arrSeqAct :  array[1..MAX_TEMP_CHANNEL, seq[JsonNode]]
  seqTProfNames : seq[JsonNode]
  arrChanProfiles : array[1..MAX_TEMP_CHANNEL, int]

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
  var canvWidth : int
  var maxX : int
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
        strAct=sa[JSON_DATA_ACTION].getStr()
        intRes=sa[JSON_DATA_ACTION_RES].getInt()
        maxX = g.xAxisRange()[1]
        if(floatDT>maxX.toFloat()) :
          echo "Fixing action outside of right bound: ", floatDT, ">", maxX
          floatDT = maxX.toFloat()-ACT_DRAW_WIDTH
        canvLBX=g.toDomXCoord(floatDT-ACT_DRAW_WIDTH)
        canvRBX=g.toDomXCoord(floatDT+ACT_DRAW_WIDTH)
        canvLTX=canvLBX
        canvRTX=canvRBX
        canvLBY=g.toDomYCoord(GRAPH_MIN_TEMP)
        canvLTY=g.toDomYCoord(GRAPH_MAX_TEMP)
        canvRBY=canvLBY
        canvRTY=g.toDomYCoord(GRAPH_MAX_TEMP)
        canvWidth=canvRTX-canvLTX
        if(canvWidth<ACT_DRAW_MIN_WIDTH_PIX) :
          canvWidth=ACT_DRAW_MIN_WIDTH_PIX
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
        canvas.fillRect(canvLTX,area.y,canvWidth,area.h)        

proc printData(str : cstring) {.exportc.} =
  var infoDiv = document.getElementById("info")
  infoDiv.innerHTML = str

proc showProfileDropDown(tchan : int) {.exportc.} =
  var strDivContent : string = ""
  var id : int
  let profDDDiv = document.getElementById("profdddiv" & $tchan)
  strDivContent &= "<select id=" & "profdd" & $tchan & ">"
  for tp in seqTProfNames :
    id = tp[JSON_DATA_ID].getInt()
    if(id == arrChanProfiles[tchan]) :
      strDivContent &= "<option value=" & $id & " selected>" & tp[JSON_DATA_NAME].getStr() & "</option>"
    else :
      strDivContent &= "<option value=" & $id & ">" & tp[JSON_DATA_NAME].getStr() & "</option>"
  strDivContent &= "</select>"
  strDivContent &= "<br><button onclick=postTProfile(" & $tchan & ")>Set</button>"
  profDDDiv.innerHTML = strDivContent
  return

# TODO: check actually configured profile
proc postTProfile(tchan : int) {.exportc.} =
  var prof : int = 0
  var dow : int = 0
  let profDD = document.getElementById("profdd" & $tchan)
  let profSelected = profDD.value
  prof = parseInt($profSelected)
  var node : JsonNode
  node =  %* {JSON_DATA_TEMP_CHAN : tchan, JSON_DATA_PROFILE : prof, JSON_DATA_DOW : dow}
  var conf = minAjaxConf()
  conf.url = "/profile"
  conf.rtype = "POST"
  conf.data = $node
  conf.success = "resultPostProfile"
  conf.debugLog = true
  minAjax(conf[])
 
proc getProfOnChannel(ch : int) {.exportc.} =
  var nmax : int = 40
  var conf = minAjaxConf()
  conf.url = "/profile"
  conf.rtype = "GET"
  conf.data = "channel=" & intToStr(ch) & "&nmax=" & intToStr(nmax)
  conf.success = "showProfile"
  conf.debugLog = true
  minAjax(conf[])

proc resultPostProfile(str : cstring) {.exportc.} =
  let strData = $str
  var chan : int = 0
  var status : int = 0
  if(strData.len()<2) :
    echo "showProfile received no data in answer for profiles"
    return
  else:
    echo "showProfile got data: ", strData
  let jsonData = parseJson(strData)
  chan = jsonData[JSON_DATA_TEMP_CHAN].getInt()
  status = jsonData[JSON_REPLY_STATUS].getInt()
  if(status == JSON_REPLY_STATUS_OK and chan>0) :
    getProfOnChannel(chan)
    discard nimSetTimeout(cstring("getTempProfiles"), 300, "")
  return

proc showProfile(str : cstring) {.exportc.} =
  var chan : int = 0
  var profile : int = 0
  var node : JsonNode
  var strDivContent : string = ""
  let strData = $str
  if(strData.len()<2) :
    echo "showProfile received no data in answer for profiles"
    return
  else:
    echo "showProfile got data: ", strData
  let jsonData = parseJson(strData)
  node=jsonData[JSON_DATA_TEMP_CHAN]
  chan=node[JSON_DATA_TEMP_CHAN].getInt()
  strDivContent &= "Temperature channel: " & $chan
  node=jsonData[JSON_DATA_PROFILE]
  profile=node[JSON_DATA_PROFILE].getInt()
  strDivContent &= " Profile number: " & $profile
  arrChanProfiles[chan] = profile
  let arrTempEvts = jsonData[JSON_DATA_TEMP_EVENTS].getElems()
  if(arrTempEvts != @[]) :
    strDivContent &= "<table border=1>\n"
    strDivContent &= "<tr><td>Hour</td><td>Min</td><td>Temp</td><td>Default</td></tr>\n"
    for te in arrTempEvts :
      strDivContent &= "<tr>"
      strDivContent &= "<td>" & $te[JSON_DATA_HOUR].getInt() & "</td>"
      strDivContent &= "<td>" & $te[JSON_DATA_MIN].getInt() & "</td>"
      strDivContent &= "<td>" & $te[JSON_DATA_TEMP].getInt() & "</td>"
      strDivContent &= "<td>" & te[JSON_DATA_ACTION].getStr() & "</td>"
      strDivContent &= "</tr>\n"
    strDivContent &= "</table>\n"
  let infoDiv = document.getElementById("profdiv" & $chan)
  infoDiv.innerHTML = strDivContent

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

proc showTempProfilesDropDownLists(str : cstring) {.exportc.} =
  let strData = $str
  if(strData.len()<2) :
    echo "showTempProfilesDropDownLists received no data in answer for profiles"
    return
  else:
    echo "showTempProfilesDropDownLists got data: ", strData
  let jsonNode = parseJson(strData)
  seqTProfNames = jsonNode.getElems()
  for i in 1..MAX_TEMP_CHANNEL :
    showProfileDropDown(i)

proc getTempOnChannel(i : int) {.exportc.} =
  const nmax : int = 40
  const last : int = 3600*48
  var conf = minAjaxConf()
  conf.url = "/temp"
  conf.rtype = "GET"
  conf.data = "channel=" & intToStr(i) & "&nmax=" & intToStr(nmax) & "&last=" & intToStr(last)
  conf.success = "createGraph"
  conf.debugLog = true
  minAjax(conf[])

proc getActOnChannel(ch : int) {.exportc.} =
  var nmax : int = 40
  const last : int = 3600*48
  var conf = minAjaxConf()
  conf.url = "/act"
  conf.rtype = "GET"
  conf.data = "channel=" & intToStr(ch) & "&nmax=" & intToStr(nmax) & "&last=" & intToStr(last)
  conf.success = "cbGetAct"
  conf.debugLog = true
  minAjax(conf[])

proc getTempProfiles() {.exportc.} =
  var conf = minAjaxConf()
  conf.url = "/ntprofiles"
  conf.rtype = "GET"
  conf.success = "showTempProfilesDropDownLists"
  conf.debugLog = true
  minAjax(conf[])

proc startTempTimer() {.exportc.} =
  for i in 1..MAX_TEMP_CHANNEL :
    getActOnChannel(i)
    discard nimSetInterval(cstring("getActOnChannel"), TEMP_REQ_INTERVAL, cstring(intToStr(i)))
    getTempOnChannel(i)
    discard nimSetInterval(cstring("getTempOnChannel"), TEMP_REQ_INTERVAL, cstring(intToStr(i)))
    getProfOnChannel(i)
    discard nimSetInterval(cstring("getProfOnChannel"), TEMP_REQ_INTERVAL, cstring(intToStr(i)))
  getTempProfiles()
  discard nimSetInterval(cstring("getTempProfiles"), TEMP_REQ_INTERVAL, "")

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
  getActOnChannel(channel)

