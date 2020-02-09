import os,tables,parseutils,jester,json,strutils,times,sets,htmlgen,strtabs,asyncdispatch,locks,times,pegs,qsort,sequtils,math,threadpool,random,json
import dbnoogest,nootypes,nooconst,noousb

const
  MAX_CHANNEL : int = 5
  MAX_TEMP_CHANNEL : int = 4
  MAX_COMMANDS : int = 7
#  BUF_SIZE = 8'u16
#  MAX_SCHED_EVENTS : int = 256
  MAX_MIN_SCHED : int = 2
  SLEEP_ON_SCHED : int = 60000 # milliseconds
#  SLEEP_ON_SCHED : int = 55000
  NO_TEMP : float = 1000.0
  ERR_TEMP : float = 2000.0
  DELTA_TEMP : float = 0.3 # precision of keeping temperature
  MAX_TEMP_VALUES : int = 50 # max number of temperatue measurements we send to other threads from temp() thread
  MAX_TEMP_MEASUREMENTS : int = 100 # max number of temperatue measurements we stock in memory
  MAX_TEMP_USABLE : int = 130  # minutes, during this time we consider temp measurement as usable
  MAX_CMD_FREQ : int = 5  # minutes, we don't send command more frequently than this value
  MAX_TEMP_CMD_SEND : int = 2 # repeat the same commands X times
  TEST_TEMP : float = 20.0
  TEST_TEMP_VAR : float = 5.0
  TEST_TEMP_SLEEP : int = 500 # milliseconds
  TEST_TEMP_CYCLES : int = 200 # temp simulated every EST_TEMP_CYCLES*TEST_TEMP_SLEEP

const
  confSchedFileName : string = "sched.conf"
  confTempSchedFileName : string = "temp.conf"
  confChanFileName : string = "chan.conf"
  statusTempFileName : string = "tmch"

const
  CHAN_USE_SCHED : string = "sched"
  CHAN_USE_TEMP : string = "temp"
  DT_FORMAT_ACT = "yyyy/MM/dd HH:mm:ss"
  DT_FORMAT_TEMP = "yyyy/MM/dd HH:mm:ss"

const
  JSON_DATA_CHAN : string = "Channel"
  JSON_DATA_TEMP : string = "Temp"
  JSON_DATA_HUMID : string = "Humid"
  JSON_DATA_DTM : string = "DTime"
  JSON_DATA_ACTION : string = "Action"
  JSON_DATA_ACTION_RES : string = "Result"
  JSON_REPLY_STATUS : string = "Status"
  JSON_REPLY_STATUS_OK : int = 0
  JSON_REPLY_STATUS_PARTIAL : int = 1
  JSON_REPLY_STATUS_NODATA : int = 2
  JSON_REPLY_CMD : string = "Command"

type
  startMode = enum
    modeweb, modeservice

type
  TempRequest = object
    channel : int
    nmax : int

type
  ActRequest = object
    channel : int
    nmax : int

type
  TempArray = array[1..MAX_CHANNEL, seq[TempMeasurementObj]]

type
  IntChannel = Channel[int]
#  FloatChannel = Channel[float]
  StringChannel = Channel[string]
  TempReqChannel = Channel[TempRequest]
  TempRespChannel = Channel[TempMeasurement]
  TempMeasChannel = Channel[TempChanMeasurement]
  ActReqChannel = Channel[ActRequest]
  ChanConfChannel = Channel[SeqChanConf]
  SchedEvtChannel = Channel[SeqSchedEvent]

proc `$`(s: ChanConf) : string =
  result = intToStr(s.channel) & " " & intToStr(s.tchannel) & " " & intToStr(s.profile) & " " & s.ctype & " " & s.cname

proc `$`(s: SchedEvent) : string =
  result = intToStr(s.dow) & " " & intToStr(s.hrs) & ":" & intToStr(s.mins) & " " & intToStr(s.channel) & " " & s.command

proc `<`(a,b: SchedEvent) : bool =
  if( (a.dow==0) or (b.dow==0) ):
    if(a.hrs<b.hrs) : result=true
    else :
      if(a.hrs>b.hrs) : result=false
      else : result=(a.mins<b.mins)
  else: result=(a.dow<b.dow)

type
  SchedTempEvent = object of SchedEvent
    temp : int

proc `$`(s: SchedTempEvent) : string =
  result = intToStr(s.dow) & " " & intToStr(s.hrs) & ":" & intToStr(s.mins) & " " & intToStr(s.channel) & " " & intToStr(s.temp) & " " & s.command

type
  PTimeInfo = ref DateTime

  TimeInfoEvent = ref object of PTimeInfo
    channel : int
    command : string

  TimeInfoTempEvent = ref object of TimeInfoEvent
    temp : int # change it to float!!!

proc initTimeInfoEvent(tie : TimeInfoEvent, ch : int = 0, cmd : string = "") =
  var ti=getLocalTime(getTime())
  tie.channel = ch
  tie.command = cmd
  tie.second = ti.second
  tie.hour = ti.hour
  tie.minute = ti.minute
  tie.monthday = ti.monthday
  tie.month = ti.month
  tie.year = ti.year
  tie.weekday = ti.weekday
  tie.yearday = ti.yearday
  tie.isDST = ti.isDST
#  tie.tzname = ti.tzname
  tie.timezone = ti.timezone
  tie.utcOffset = ti.utcOffset

proc newTimeInfoEvent() : TimeInfoEvent =
  new result
  result.initTimeInfoEvent()

proc newTimeInfoEvent(ch: int; cmd: string) : TimeInfoEvent =
  new result
  result.initTimeInfoEvent(ch,cmd)

proc `$`(tie: TimeInfoEvent) : string =
  result = `$`(PTimeInfo(tie)[]) & " channel:" & intToStr(tie.channel) & " command:" & tie.command

proc `<`*(a,b: TimeInfoEvent): bool =
  result = `<`(toTime(PTimeInfo(a)[]),toTime(PTimeInfo(b)[]))

proc `<=`*(a,b: TimeInfoEvent): bool =
  result = `<=`(toTime(PTimeInfo(a)[]),toTime(PTimeInfo(b)[]))

proc `==`*(a,b: TimeInfoEvent): bool =
  result = `==`(toTime(PTimeInfo(a)[]),toTime(PTimeInfo(b)[]))

proc newTimeInfoTempEvent() : TimeInfoTempEvent =
  new result
  result.initTimeInfoEvent()
  result.temp=int(NO_TEMP)

proc newTimeInfoTempEvent(ch: int; cmd: string; temp: int) : TimeInfoTempEvent =
  new result
  result.initTimeInfoEvent(ch,cmd)
  result.temp=temp

proc `$`(tite: TimeInfoTempEvent) : string =
  result = `$`(PTimeInfo(tite)[]) & " channel:" & intToStr(tite.channel) & " command:" & tite.command & " temp:" & intToStr(tite.temp)

proc `<`*(a,b: TimeInfoTempEvent): bool =
  result = `<`(toTime(PTimeInfo(a)[]),toTime(PTimeInfo(b)[]))

proc `<=`*(a,b: TimeInfoTempEvent): bool =
  result = `<=`(toTime(PTimeInfo(a)[]),toTime(PTimeInfo(b)[]))

proc `==`*(a,b: TimeInfoTempEvent): bool =
  result = `==`(toTime(PTimeInfo(a)[]),toTime(PTimeInfo(b)[]))

#var chanAskTemp : IntChannel
var chanReqAct : ActReqChannel
var chanRespAct : StringChannel
var chanReqTemp : TempReqChannel
var chanReqOneTemp : IntChannel
var chanRespTemp : StringChannel
var chanRespOneTemp : TempRespChannel
var chanPutTemp : TempMeasChannel
var chanConfReqChanName : IntChannel
var chanConfRespChanName : StringChannel
var chanConfReqTempName : IntChannel
var chanConfRespTempName : StringChannel
var chanConfReqTempChan : IntChannel
var chanConfRespTempChan : IntChannel
var chanReqChanConf : IntChannel
var chanRespChanConf : ChanConfChannel
var chanReqSchedEvt : IntChannel
var chanRespSchedEvt : SchedEvtChannel
var testTempCycles : int
#var seqChannelConf : seq[ChanConf]
#var totalChanConf : int

const
  Cmds = ["on","off","sw","set","bind","unbind","preset"]

proc usage() : void =
  let strusage : string = """
    Usage: noogest <command> [<channel>] [<level>]\n
    <command> may be:\n
    web - Start web interface (port 5000)\n
    service - Start web interface and scheduler\n
    initdb - Initialize database\n
    on - Turn channel ON\n
    off - Turn channel OFF\n
    sw - Switch channel ON/OFF\n
    set - Set level for channel\n
    bind - Bind channel\n
    unbind - Unbind channel\n
    preset - Activate preset\n
    <channel> must be [1..8]\n
    <level> must be [0..100] (can be used with "set" command only)\n
    """
  echo strusage
  return

proc temp() {.thread.} =
  var nd : NooData
  var channel : int
  var nmax : int
  var command : int
  var dformat : int
  var iTemp : int
  var fTemp : float
  var res : int
  var boolres : bool
  var prevCnt : int = -10000
  var currCnt : int
  var strDTime : string
  var strTemp : string
  var strResp : string = ""
  var boundSeq : int
  var sAct : seq[ActionObj]
  var sTM : seq[TempMeasurementObj]    
  var jsonResp : JsonNode
  var dtResp : DateTime
  var unixDT : int64
  var refTM : TempMeasurement
  var dti: tuple[dataAvailable: bool, msg: TempRequest]
  var dai: tuple[dataAvailable: bool, msg: ActRequest]
  var dtpi: tuple[dataAvailable: bool, msg: TempChanMeasurement]
  var doti: tuple[dataAvailable: bool, msg: int]

  if(TEST>0) : 
    randomize()
    testTempCycles = 0
  while(true) :
    if(TEST>0) : sleep(TEST_TEMP_SLEEP)
    else : sleep(300)
    if(DEBUG>3) :
      echo "Messages in chanReqTemp: ", chanReqTemp.peek()
      echo "Messages in chanReqAct: ", chanReqAct.peek()    
      echo "Messages in chanPutTemp: ", chanPutTemp.peek()    
      echo "Messages in chanReqOneTemp: ", chanReqOneTemp.peek()
# ********* check last temp request from other threads and send data as TempMeasurement **********
    doti=chanReqOneTemp.tryRecv()
    if(doti.dataAvailable) :
      if(DEBUG>1) :
        echo "temp received request for last temp on channel: ", doti.msg
      channel=doti.msg
      refTM = new TempMeasurementObj
      if(refTM != nil) :
        boolres = nooDbGetLastTemper(channel, refTM[])
        if(DEBUG>1) :
          echo "get last temp status: ", boolres
      else :
        if(DEBUG>0) :
          echo "Cannot allocate memory for new temperature measurement"
      chanRespOneTemp.send(refTM)

# ********* check temp data put request from other threads and put temp data to DB and to array **********
    dtpi=chanPutTemp.tryRecv()
    if(dtpi.dataAvailable) :
      if(DEBUG>1) :
        echo "temp received put request for temp on channel: ",dtpi.msg[].channel
        echo "temp received: ",dtpi.msg[].mTemp
      channel=dtpi.msg[].channel
      refTM = new TempMeasurementObj
      if(refTM != nil) :
        refTM.mTime = dtpi.msg[].mTime
        refTM.mTemp = dtpi.msg[].mTemp
        boolres=nooDbPutTemper(channel, refTM[])
        if(DEBUG>1) :
          echo "wrote temp status: ", boolres
      else :
        if(DEBUG>0) :
          echo "Cannot allocate memory for new temperature measurement"

# ********* check temp data request from other threads and send data in formatted string **********
    dti=chanReqTemp.tryRecv()
    if(dti.dataAvailable) :
      if(DEBUG>1) :
        echo "temp received request for temp on channel: ",dti.msg.channel
        echo "max number of points requested: ",dti.msg.nmax
      channel=dti.msg.channel
      nmax=dti.msg.nmax
      strResp=""
      if( (channel>0) and (channel<(MAX_TEMP_CHANNEL+1)) ) :
        sTM = newSeq[TempMeasurementObj]()
        res = nooDbGetTemper(channel, sTM, nmax)
        if(DEBUG>1) :
          echo "temp received ", res, " temperature measurements from database"
          echo "for bounds ", sTM.low, "..", sTM.high
        for tm in sTM :
#              2015/10/01 10:01:30,20.1,25.5\n
          try :
            strDTime=format(getLocalTime(tm.mTime), DT_FORMAT_TEMP)
          except :
            if(DEBUG>0) :
              echo "error formatting mTime"
            strDTime=""
          fTemp=tm.mTemp
          if( (fTemp==NO_TEMP) or (fTemp==ERR_TEMP) ) : 
            strTemp=""
          else : 
            strTemp=formatFloat(fTemp, ffDecimal, 1)
          if( (strDTime.len>1) and (strTemp.len>1) ) : 
            strResp &= (strDTime & "," & strTemp & "\n")
      else :
        strResp=""
      chanRespTemp.send(strResp)

# ********* check actions data request from other threads and send data in json string **********
    dai=chanReqAct.tryRecv()
    if(dai.dataAvailable) :
      if(DEBUG>1) :
        echo "temp received request for actions on channel: ",dai.msg.channel
        echo "max number of points requested: ",dai.msg.nmax
      channel=dai.msg.channel
      nmax=dai.msg.nmax
      strResp=""
      if( (channel>0) and (channel<(MAX_TEMP_CHANNEL+1)) ) :
        sAct=newSeq[ActionObj]()
        strResp=""
        res = nooDbGetAction(channel, sAct, nmax)
        if(DEBUG>0) :
          echo "Received action records from database: ", res
        if(res>0) :
          jsonResp = newJArray()
          for act in sAct :
            dtResp=getLocalTime(act.aTime)
            unixDT=dtResp.toTime().toUnix()
#  JSON_DATA_CHAN : string = "Channel"
#  JSON_DATA_TEMP : string = "Temp"
#  JSON_DATA_HUMID : string = "Humid"
#  JSON_DATA_DTM : string = "DTime"
#  JSON_DATA_ACTION : string = "Action"
#  JSON_DATA_ACTION_RES : string = "Result"
#  JSON_REPLY_STATUS : string = "Status"
#  JSON_REPLY_STATUS_OK : int = 0
#  JSON_REPLY_STATUS_PARTIAL : int = 1
#  JSON_REPLY_STATUS_NODATA : int = 2
#  JSON_REPLY_CMD : string = "Command"
            jsonResp.add( %* {JSON_DATA_CHAN : channel, JSON_DATA_DTM : unixDT, JSON_DATA_ACTION : act.aAct, JSON_DATA_ACTION_RES : act.aRes} )
          strResp = $jsonResp
          if(DEBUG>1) :
            echo "temp is answering with actions:\n",strResp            
      chanRespAct.send(strResp)

# ********* get temperature from hardware *************
    if(TEST==0) : res = getUsbData(nd)
    else : res=ERR_MODE_TEST

    case res :
      of NO_ERROR :
        if(DEBUG>3) :
          echo `$`(getLocalTime(getTime()))," temp received buffer:"
          for i in 0..<(int)BUF_SIZE :
            echo "\t",i," ",nd[i]
        currCnt = int(nd[0]) and 63
        if(currCnt == prevCnt) :
          continue
        else :
          prevCnt = currCnt
          channel = (int) nd[1]
          inc(channel)
          if( (channel<1) or (channel>(MAX_TEMP_CHANNEL)) ) : continue
          command = (int) nd[2]
          dformat = (int) nd[3]
          if(DEBUG>2) :
            echo `$`(getLocalTime(getTime()))," temp got new data: channel=",channel," command=",command," dataformat=",dformat
          if( (command==21) and (dformat>2) ) :
            iTemp = int(((uint8(nd[5]) and 0x0f'u8) shl 8) + (uint8(nd[4]) and 0xff'u8))
            if (iTemp >= 0x800) :
              iTemp = iTemp - 0x1000
            fTemp = float(iTemp) / 10
#            humi = int(uint8(nd[6]) and 0xff'u8)
          if(DEBUG>0) :
            echo `$`(getLocalTime(getTime()))," temp decoded new data: channel=",channel," temp=",formatFloat(fTemp,ffDecimal,1)
          refTM = new TempMeasurementObj
          if(refTM != nil) :
            refTM.mTime=getTime()
            refTM.mTemp=fTemp
            boolres=nooDbPutTemper(channel, refTM[])
            if(DEBUG>1) :
              echo "wrote temp status: ", boolres
          else :
            if(DEBUG>0) :
              echo "Cannot allocate memory for new temperature measurement"
      of ERR_NO_DEVICE :
        if(DEBUG>1) : echo "Error USB read: cannot find nooLite device"
      of ERR_ERR_CONFIG :
        if(DEBUG>1) : echo "Error USB read: cannot set configuration"
      of ERR_CLAILM_IF :
        if(DEBUG>1) : echo "Error USB read: cannot claim interface"
      of ERR_MODE_TEST :
        inc testTempCycles
        if(testTempCycles<TEST_TEMP_CYCLES) :
          continue
        if(DEBUG>1) : echo "Working in test mode"
        testTempCycles = 0
        for i in 1..MAX_TEMP_CHANNEL :
          channel=i
          fTemp=TEST_TEMP+(rand(TEST_TEMP_VAR)-TEST_TEMP_VAR/2)
          if(DEBUG>1) :
            echo `$`(getLocalTime(getTime()))," temp simulated new data: channel=",channel," temp=",formatFloat(fTemp,ffDecimal,1)
          refTM = new TempMeasurementObj
          if(refTM != nil) :
            refTM.mTime=getTime()
            refTM.mTemp=fTemp
            boolres=nooDbPutTemper(channel, refTM[])
            if(DEBUG>1) :
              echo "wrote temp status: ", boolres
          else :
            if(DEBUG>0) :
              echo "Cannot allocate memory for new temperature measurement"

      else :
        if(DEBUG>1) : echo "temp got error: getUsbData result - ",res
#[
# No nooDbImportConf as there are profiles in chan table, one need to import data manually
proc getChannelConf(scc : var seq[ChanConf]) : int =
  var i : int = 0
  if(scc.high>0) : return 0

  var ffff = open(confChanFileName, bufSize=8000)
  var res = TaintedString(newStringOfCap(120))

  while ffff.readLine(res) :
#    if x =~ peg"^{[0-7]}';'{[0-2][0-9]}':'{[0-5][0-9]}';'{[0-9]}';'{[0-9][0-9]}';'{\a*}.*" :
    if res =~ peg"^{[1-9]}';'{[1-9]}';'{\a*}';'{\a*}" :
      var ncc=ChanConf()
      ncc.channel = parseInt(matches[0])
      ncc.tchannel = parseInt(matches[1])
      ncc.ctype = matches[2]
      ncc.cname = matches[3]
      if(DEBUG>2) :
        echo "matches: ",matches[0]," ",matches[1]," ",matches[2]," ",matches[3]
      if( (ncc.channel>MAX_CHANNEL) or (ncc.tchannel>MAX_TEMP_CHANNEL) ) : continue
      case ncc.ctype :
        of "temp" :
          scc.add(ncc)
          inc(i)
        of "sched" :
          ncc.tchannel=0
          scc.add(ncc)
          inc(i)
        else :
          discard
  if(DEBUG>1) :
    echo "getChannelConf: matched lines - ",i
#  close(ffff)   #  problem with jester if this file is closed here
  dec(i)
  result=i
]#
proc web() {.thread.} =

  echo "Starting Web interface..."
#  var arrChannelConf = newSeq[ChanConf]()
#  var totalChanConf : int

#  totalChanConf = getChannelConf(arrChannelConf)

  routes:
    get "/":
      var selChannel : string = ""
      var optChannels : string = ""
      var selCommand : string = ""
      var optCommands : string = ""
      var strInputLevel : string = "Level:"
      var strDivId : string = ""
      var strDygTable : string = ""
      var channelName : string = ""

      for i in 1..MAX_CHANNEL :
        chanConfReqChanName.send(i)
        if(DEBUG>2) :
          echo "requested channel name for: ",i
        channelName = chanConfRespChanName.recv()
        if(DEBUG>2) :
          echo "received: ",channelName
        if(channelName.len>1) :
          optChannels &= `option`(channelName,value=intToStr(i))
      selChannel = select(id="selchan", optChannels)
      for i in 0..<MAX_COMMANDS :
        optCommands &= `option`(Cmds[i],value=Cmds[i])
      selCommand = select(id="selcmd", optCommands)
      for i in 1..MAX_TEMP_CHANNEL :
        strDivId = "dygdiv" & intToStr(i)
        strDygTable &= `tr`(`td`(`div`(id=strDivId)))
      resp body(onload="startTempTimer()",
        script(src="/js/ngclient.js", `type`="text/javascript"),
        script(src="/js/dygraph.js", `type`="text/javascript"),
        script(src="/js/minajax.js", `type`="text/javascript"),
        script(src="/js/dygraph-combined-dev.js", `type`="text/javascript"),
        `table`(
          `tr`(
            `td`(selChannel),
            `td`(selCommand),
            `td`(`table`(`tr`(`td`(strInputLevel),`td`(`input`(id="inpLevel",`type`="text",value="1"))))),
            `td`(`button`(id="btnAction","Send Command",onclick="btnActionOnClick()")),
            `td`(`button`(id="btnTemp","Get Temp",onclick="btnTempOnClick()"))
            )
          ),
        `div`(id="info"),
        `table`(strDygTable)
        )
    get "/data":
      var intLevel : int
      var intChannel : int
      var strCommand : string
      var res : int
      var act : ActionObj
      var boolRes : bool
      let params = request.params
      res = parseInt($params["level"],intLevel)
      if(res == 0) : intLevel=0
      if (intLevel < 0) : intLevel=0
      if (intLevel > 100) : intLevel=100
      intLevel=(int)(34.0+1.23*(float)intLevel)
      res = parseInt($params["channel"],intChannel)
      if(res == 0) :
        resp "Invalid channel:" & $params["channel"]
        return
      strCommand = $params["command"]
      res = sendUsbCommand(strCommand, cuchar(intChannel), cuchar(intLevel))
      act.aTime = getTime()
      act.aAct = strCommand
      act.aRes = res
      boolRes = nooDbPutAction(intChannel, act)
      if(DEBUG>2) :
        echo "Put action to DB result: ", boolRes
      if(res==NO_ERROR) :
        resp "Success"
      else :
        resp "Result: " & intToStr(res)

    get "/act":
      var respAct : string = ""
      var reqChannel : int
      var reqMaxValues : int
      var res : int
      var actReq : ActRequest
      let params = request.params
      res = parseInt($params["channel"],reqChannel)
      if(res == 0) : reqChannel=0
      res = parseInt($params["nmax"],reqMaxValues)
      if(res == 0) : reqMaxValues=MAX_TEMP_VALUES
      if(DEBUG>0) :
        echo "web is trying to request actions for channel ",reqChannel," reqMaxValues: ",reqMaxValues
      if(reqChannel>0) :
        actReq.channel = reqChannel
        actReq.nmax = reqMaxValues
        chanReqAct.send(actReq)
        if(DEBUG>1) :
          echo "requested channel: ",actReq.channel," nmax: ",actReq.nmax
        respAct = chanRespAct.recv()
        if(DEBUG>1) :
          echo "received: ",respAct
      resp respAct
      
    get "/temp":
#      var fTemp : float
#      var seqTemp : array[1..MAX_TEMP_CHANNEL,float]
      var respTemp : string = ""
      var reqChannel : int
      var reqMaxValues : int
      var res : int
      var tReq : TempRequest
      var strChannelName : string

      let params = request.params
#  TempReqChannel = Channel[TempRequest]
      res = parseInt($params["channel"],reqChannel)
      if(res == 0) : reqChannel=0
      res = parseInt($params["nmax"],reqMaxValues)
      if(res == 0) : reqMaxValues=MAX_TEMP_VALUES
      if(DEBUG>0) :
        echo "web is trying to request temperature for channel ",reqChannel," reqMaxValues: ",reqMaxValues
      if(reqChannel>0) :
#  TempRequest = object
#    channel : int
#    nmax : int
        chanConfReqTempName.send(reqChannel)
        if(DEBUG>2) :
          echo "requested temp channel name for: ",reqChannel
        strChannelName = chanConfRespTempName.recv()
        if(DEBUG>2) :
          echo "received: ",strChannelName
        if(strChannelName.len<1) :
          strChannelName = intToStr(tReq.channel)
        tReq.channel = reqChannel
        tReq.nmax = reqMaxValues
        respTemp = intToStr(tReq.channel) & "\n" & strChannelName & "\nDTime,Temp\n"
        chanReqTemp.send(tReq)
        if(DEBUG>1) :
          echo "requested channel: ",tReq.channel," nmax: ",tReq.nmax
        respTemp &= chanRespTemp.recv()
        if(DEBUG>1) :
          echo "received: ",respTemp
      resp respTemp
    
    post "/data":
#  JSON_DATA_CHAN : string = "Channel"
#  JSON_DATA_TEMP : string = "Temp"
#  JSON_DATA_HUMID : string = "Humid"
#  JSON_DATA_DTM : string = "DTime"
#  JSON_REPLY_STATUS : string = "Status"
#  JSON_REPLY_STATUS_OK : int = 0
#  JSON_REPLY_STATUS_PARTIAL : int = 1
#  JSON_REPLY_STATUS_NODATA : int = 2
#  JSON_REPLY_CMD : string = "Command"
      if(DEBUG>2) :
        echo "Received body: ", request.body
      let jsonData = parseJson(request.body)
      if(DEBUG>2) :
        echo "Received json: ", $jsonData
      var strRepStatus : string = ""
      var jsonRepStatus : JsonNode
      var intRepStatus : int
      var dataChan : int
      var dataDT : BiggestInt
      var dataTemp : float
      var dataHumid : float
      var tChMeas : TempChanMeasurement
      dataChan=jsonData{JSON_DATA_CHAN}.getInt() # Always present
      dataDT=jsonData{JSON_DATA_DTM}.getBiggestInt() # Always present
      dataTemp=jsonData{JSON_DATA_TEMP}.getFloat() # Always present
      dataHumid=jsonData{JSON_DATA_HUMID}.getFloat() # Optional -> JSON_REPLY_STATUS_PARTIAL
      if(DEBUG>1) :
        echo "Received dataDT: ", dataDT
        echo "Received dataTemp: ", dataTemp
        echo "Received dataHumid: ", dataHumid
      if(dataChan>0 and dataDT>0 and dataTemp>0) :
        if(dataHumid>0) : 
          intRepStatus=JSON_REPLY_STATUS_OK
        else:
          intRepStatus=JSON_REPLY_STATUS_PARTIAL
      else:
        intRepStatus=JSON_REPLY_STATUS_NODATA
      jsonRepStatus =  %* {JSON_REPLY_STATUS : intRepStatus}
      strRepStatus = $jsonRepStatus
      if(DEBUG>2) :
        echo "Replying with json: ", strRepStatus
      tChMeas = TempChanMeasurement(mTime: fromUnix(dataDT), mTemp: dataTemp, channel: dataChan)
      chanPutTemp.send(tChMeas)
      resp strRepStatus
      
  runForever()
  return
#[
proc getSchedule(sc : var seq[SchedEvent]) : int =
  var i : int = 0
  if(sc.high>0) : return 0
  var fff = open(confSchedFileName, bufSize=8000)
  var res = TaintedString(newStringOfCap(120))

#  for x in lines(confFileName) :
  while fff.readLine(res) :
#    if x =~ peg"^{[0-7]}';'{[0-2][0-9]}':'{[0-5][0-9]}';'{[0-9]}';'{\a*}.*" :
    if res =~ peg"^{[0-7]}';'{[0-2][0-9]}':'{[0-5][0-9]}';'{[0-9]}';'{\a*}.*" :
      if(DEBUG>3) :
        sleep(300)
        echo "matched line: ",i
      var nsc=SchedEvent()
      sc.add(nsc)
      sc[i].dow = parseInt(matches[0])
      sc[i].hrs = parseInt(matches[1])
      sc[i].mins = parseInt(matches[2])
      sc[i].channel = parseInt(matches[3])
      sc[i].command = matches[4]
      if( (sc[i].hrs>23) or (sc[i].mins>59) or (sc[i].channel>MAX_CHANNEL) ) : continue
      if( (sc[i].command=="on") or (sc[i].command=="off") ) : inc(i)
  if(DEBUG>2) :
    echo "Total lines matched : ",i
    sleep(10000)
#  close(fff)   #  problem with jester if this file is closed here
  if(DEBUG>2) :
    echo "getSchedule: matched lines - ",i
    sleep(10000)
  dec(i)
  result=i
]#
proc getTempSchedule(sct : var seq[SchedTempEvent]) : int =
  var i : int = 0
  if(sct.high>0) : return 0

  var ffff = open(confTempSchedFileName, bufSize=8000)
  var res = TaintedString(newStringOfCap(120))

  while ffff.readLine(res) :
#    if x =~ peg"^{[0-7]}';'{[0-2][0-9]}':'{[0-5][0-9]}';'{[0-9]}';'{[0-9][0-9]}';'{\a*}.*" :
    if res =~ peg"^{[0-7]}';'{[0-2][0-9]}':'{[0-5][0-9]}';'{[0-9]}';'{[0-9][0-9]}';'{\a*}.*" :
      var nsc=SchedTempEvent()
      sct.add(nsc)
      sct[i].dow = parseInt(matches[0])
      sct[i].hrs = parseInt(matches[1])
      sct[i].mins = parseInt(matches[2])
      sct[i].channel = parseInt(matches[3])
      sct[i].temp = parseInt(matches[4])
      sct[i].command = matches[5]
      if( (sct[i].hrs>23) or (sct[i].mins>59) or (sct[i].channel>MAX_CHANNEL) ) : continue
      if( (sct[i].command=="on") or (sct[i].command=="off") ) : inc(i)
  if(DEBUG>2) :
    echo "getTempSchedule: matched lines - ",i
    sleep(10000)
#  close(ffff)   #  problem with jester if this file is closed here
  dec(i)
  result=i

proc isWeekDayNow(dow : int) : bool =
  if( (dow<0) or (dow>7) ) :return false
  if(dow==0) : return true

  let nowWeekDay = getLocalTime(getTime()).weekday
  if( ord(nowWeekDay) == (dow-1) ) : result=true
  else : result=false

# TODO: correctly process events near midnight
proc sched() {.thread.} =
#  var arrSchedEvt = newSeq[SchedEvent]()
  var seqSchedEvt : SeqSchedEvent
  var totalEvt : int
  var arrSchedTimeInfoEvent = newSeq[TimeInfoEvent]()
  var arrSchedTempEvt = newSeq[SchedTempEvent]()
  var totalTempEvt : int
  var arrSchedTimeInfoTempEvent = newSeq[TimeInfoTempEvent]()
  var seqChannelConf : SeqChanConf
  var totalChanConf : int
  var sendCmdTime : array[1..MAX_CHANNEL,Time]
  var lastCommand : array[1..MAX_CHANNEL,string]
  var lastCmdSend : array[1..MAX_CHANNEL,int]
  var chanUseSched : array[1..MAX_CHANNEL,bool]
  var chanUseTemp : array[1..MAX_CHANNEL,bool]
  var lastTempEvtIndex : array[1..MAX_CHANNEL,int]
  var arrChannelProfileId : array[1..MAX_CHANNEL,int]
  var dayOfWeek : int
  var now : DateTime
  var evt : DateTime
  var tReq : TempRequest
  var respTemp : string
#  var seqRespTemp : seq[string]
  var fTemp : float
  var tempTimeInfo : DateTime
  var tempTime : Time
  var chanTempPresent : bool = false
  var chanSchedPresent : bool = false
  let maxSecSched = MAX_MIN_SCHED*60
  var j,jj : int
#  var diff : int64
  var diff : Duration
  var res : int
  var channel,tchannel,profile : int
  var cmd : string
  var act : ActionObj
  var boolRes : bool
  var lastTempMeas : TempMeasurement
  var nowWeekDay = int(ord(getLocalTime(getTime()).weekday))
  inc(nowWeekDay)
  sleep(1000)
#  totalEvt = getSchedule(arrSchedEvt)
  totalTempEvt = getTempSchedule(arrSchedTempEvt)
#  totalChanConf = getChannelConf(arrChannelConf)
#  totalChanConf = nooDbGetChanConf(arrChannelConf)
  if(DEBUG>1) :
    echo "Requesting configuration for all channels"
  chanReqChanConf.send(0)
  seqChannelConf = chanRespChanConf.recv()
  if(DEBUG>1) :
    echo "received ", seqChannelConf.high-seqChannelConf.low+1, " configuration elements"  
  totalChanConf=seqChannelConf.high-seqChannelConf.low
  if(DEBUG>0) :
#    echo "sched got sched events: ",(totalEvt+1)
    echo "sched got temp events: ",(totalTempEvt+1)
    echo "sched got chanconf records: ", totalChanConf+1
  if(DEBUG>2) :
#    echo "Sched events:"
#    for j in 0..totalEvt :
#      echo "\t",`$`(arrSchedEvt[j])
    echo "Temp events:"
    for j in 0..totalTempEvt :
      echo "\t",`$`(arrSchedTempEvt[j])
    echo "Chanconf records:"
    for cc in seqChannelConf :
      echo "\t",$cc
    echo "Current weekday: ",nowWeekDay
  for j in 1..MAX_CHANNEL :
    chanUseSched[j] = false
    chanUseTemp[j] = false
    lastCommand[j] = ""
    sendCmdTime[j] = initTime(0, 0)
    lastCmdSend[j] = 0
  for cc in seqChannelConf :
#  ChanConf = object
#    channel* : int
#    tchannel* : int
#    profile* : int
#    ctype* : string
#    cname* : string
#  CHAN_USE_SCHED : string = "sched"
#  CHAN_USE_TEMP : string = "temp"
#  var chanUseSched : array[1..MAX_CHANNEL,bool]
#  var chanUseTemp : array[1..MAX_CHANNEL,bool]
    if(DEBUG>2) :
      echo "Config: ", $cc
    arrChannelProfileId[cc.channel] = cc.profile
    case cc.ctype :
      of CHAN_USE_SCHED :
        chanUseSched[cc.channel] = true
        chanUseTemp[cc.channel] = false
        chanSchedPresent = true
        if(DEBUG>1) :
          echo "channel ", cc.channel, " uses sched"
        continue
      of CHAN_USE_TEMP :
        chanUseSched[cc.channel] = false
        chanUseTemp[cc.channel] = true
        chanTempPresent = true
        if(DEBUG>1) :
          echo "channel ", cc.channel, " uses temp"
        continue
      else:
        continue
# ********** Main cycle ******************        
  while (true) :
    now = getLocalTime(getTime())
    if(DEBUG_MEM>0) :
      echo "Enter TotalMem: ",getTotalMem()
      echo "Enter FreeMem: ",getFreeMem()
      echo "Enter OccupiedMem: ",getOccupiedMem()
# ********* processing scheduled events ***********
#  SchedEvent* = object of RootObj
#    dow* : int
#    hrs* : int
#    mins* : int
#    channel* : int
#    command* : string
    if(chanSchedPresent) :
      for channel in 1..MAX_CHANNEL :
        if(not chanUseSched[channel]) :
          continue
        profile = arrChannelProfileId[channel]
        if(DEBUG>1) :
          echo "Requesting scheduled events for profile: ", profile, " used on channel ", channel
        chanReqSchedEvt.send(profile)
        seqSchedEvt = chanRespSchedEvt.recv()
        if(DEBUG>1) :
          echo "received ", seqSchedEvt.high-seqSchedEvt.low+1, " scheduled events"  
        for se in seqSchedEvt :
          if(DEBUG>2) :
            echo "sched is processing sched event: ", $se
          dayOfWeek=se.dow
# filter on weekdays
          if(not isWeekDayNow(dayOfWeek)) : continue
          evt = getLocalTime(getTime())
          evt.second=0
          evt.minute=se.mins
          evt.hour=se.hrs
          if(DEBUG>2) :
            echo "sched got event DateTime object: ",$evt
# filter on time
          diff=toTime(now)-toTime(evt)
          if(DEBUG>2) :
            echo "sched got diff: ", diff.inSeconds
          if( (diff.inSeconds>0) and (diff.inSeconds<maxSecSched) ) :
            arrSchedTimeInfoEvent.add(newTimeInfoEvent(channel, se.command))
            j=arrSchedTimeInfoEvent.high
            if(DEBUG>2) :
              echo "sched added event: ",j
            arrSchedTimeInfoEvent[j].second = 0
            arrSchedTimeInfoEvent[j].hour = se.hrs
            arrSchedTimeInfoEvent[j].minute = se.mins
        if(DEBUG_MEM>0) :
          echo "Selected Events TotalMem: ",getTotalMem()
          echo "Selected Events FreeMem: ",getFreeMem()
          echo "Selected Events OccupiedMem: ",getOccupiedMem()
        if(arrSchedTimeInfoEvent.len()>0) :
          qsort_inline(arrSchedTimeInfoEvent)
          if(DEBUG_MEM>0) :
            echo "Sorted Events TotalMem: ",getTotalMem()
            echo "Sorted Events FreeMem: ",getFreeMem()
            echo "Sorted Events OccupiedMem: ",getOccupiedMem()
          if(DEBUG>0) :
            echo "sched is working on ",$now," processing ",arrSchedTimeInfoEvent.len()," events"
          for jj in arrSchedTimeInfoEvent.low..arrSchedTimeInfoEvent.high :
# check if the channel should be managed by schedule
            if( not ( (lastCommand[arrSchedTimeInfoEvent[jj].channel]==arrSchedTimeInfoEvent[jj].command) and
                    (lastCmdSend[arrSchedTimeInfoEvent[jj].channel]>MAX_TEMP_CMD_SEND) ) ) :
              if(DEBUG>0) :
                echo "sched is sending event ",jj," : ",`$`(arrSchedTimeInfoEvent[jj])
              res = sendUsbCommand(arrSchedTimeInfoEvent[jj].command, cuchar(arrSchedTimeInfoEvent[jj].channel), cuchar(0))
              if(DEBUG>0) :
                echo "sched got result: ",res              
              act.aTime = getTime()
              act.aAct = arrSchedTimeInfoEvent[jj].command
              act.aRes = res
              boolRes = nooDbPutAction(arrSchedTimeInfoEvent[jj].channel, act)
              if(DEBUG>2) :
                echo "Put action to DB result: ", boolRes
              if(res==NO_ERROR) :
                sendCmdTime[arrSchedTimeInfoEvent[jj].channel]=getTime()
                if(lastCommand[arrSchedTimeInfoEvent[jj].channel]==arrSchedTimeInfoEvent[jj].command) :
                  inc lastCmdSend[arrSchedTimeInfoEvent[jj].channel]
                else :
                  lastCommand[arrSchedTimeInfoEvent[jj].channel]=arrSchedTimeInfoEvent[jj].command
                  lastCmdSend[arrSchedTimeInfoEvent[jj].channel]=1
              sleep(200)
          if(DEBUG_MEM>0) :
            echo "Sent Sched Events TotalMem: ",getTotalMem()
            echo "Sent Sched Events FreeMem: ",getFreeMem()
            echo "Sent Sched Events OccupiedMem: ",getOccupiedMem()
          arrSchedTimeInfoEvent.delete(arrSchedTimeInfoEvent.low,arrSchedTimeInfoEvent.high)
          if(DEBUG_MEM>0) :
            echo "Finished Sched Events TotalMem: ",getTotalMem()
            echo "Finished Sched FreeMem: ",getFreeMem()
            echo "Finished Sched OccupiedMem: ",getOccupiedMem()
# ********* end processing sched events ***********
# processing temp events
# arrSchedTempEvt
#  SchedTempEvent
#    dow : int
#    hrs : int
#    mins : int
#    channel : int
#    command : string
#    temp : int
#newTimeInfoTempEvent
    if(chanTempPresent) :
      for i in 0..totalTempEvt :
        if(DEBUG>2) :
          echo "sched is processing temp event numero: ",i
        dayOfWeek=arrSchedTempEvt[i].dow
# filter on weekdays
        if(not isWeekDayNow(dayOfWeek)) : continue
        evt = getLocalTime(getTime())
        evt.second=0
        evt.minute=arrSchedTempEvt[i].mins
        evt.hour=arrSchedTempEvt[i].hrs
        if(DEBUG>2) :
          echo "sched got temp event object: ",$evt
# filter on time
        diff=toTime(now)-toTime(evt)
        if(DEBUG>2) :
          echo "sched got diff: ", diff.inSeconds
        if(diff.inSeconds>0) :
          arrSchedTimeInfoTempEvent.add(newTimeInfoTempEvent())
          j=arrSchedTimeInfoTempEvent.high
          if(DEBUG>2) :
            echo "sched added temp event: ",j
          arrSchedTimeInfoTempEvent[j].second = 0
          arrSchedTimeInfoTempEvent[j].hour = arrSchedTempEvt[i].hrs
          arrSchedTimeInfoTempEvent[j].minute = arrSchedTempEvt[i].mins
          arrSchedTimeInfoTempEvent[j].channel = arrSchedTempEvt[i].channel
          arrSchedTimeInfoTempEvent[j].command = arrSchedTempEvt[i].command
          arrSchedTimeInfoTempEvent[j].temp = arrSchedTempEvt[i].temp
      if(arrSchedTimeInfoTempEvent.len()>0) :
        qsort_inline(arrSchedTimeInfoTempEvent)
        if(DEBUG>1) :
          echo "sched temp is working on ",$now," processing ",arrSchedTimeInfoTempEvent.len()," events"
# find the last event for every channel managed by temp
        for j in 1..MAX_CHANNEL :
          lastTempEvtIndex[j] = -1
        for jj in countdown(arrSchedTimeInfoTempEvent.high,arrSchedTimeInfoTempEvent.low) :
          if(DEBUG>2) :
            echo "jj=",jj," searching last event: ",lastTempEvtIndex[arrSchedTimeInfoTempEvent[jj].channel]," ",chanUseTemp[arrSchedTimeInfoTempEvent[jj].channel]
          if( (lastTempEvtIndex[arrSchedTimeInfoTempEvent[jj].channel] == -1) and chanUseTemp[arrSchedTimeInfoTempEvent[jj].channel] ) :
            lastTempEvtIndex[arrSchedTimeInfoTempEvent[jj].channel] = jj
            if(DEBUG>2) :
              echo "last temp event index for channel ",arrSchedTimeInfoTempEvent[jj].channel," set to ",jj
        if(DEBUG>2) :
          echo "lastTempEvtIndex:"
          for j in 1..MAX_CHANNEL :
            echo "\t",lastTempEvtIndex[j]
            if(lastTempEvtIndex[j] != -1) :
              echo "\t\t",`$`(arrSchedTimeInfoTempEvent[lastTempEvtIndex[j]])
        for j in 1..MAX_CHANNEL :
          if( ((getTime()-sendCmdTime[j]).inSeconds)*60 < MAX_CMD_FREQ) : continue
          if(lastTempEvtIndex[j] != -1) :
# get the last measured temp for the channel
            channel=arrSchedTimeInfoTempEvent[lastTempEvtIndex[j]].channel
            tchannel = -1
            for cc in seqChannelConf :
              if(cc.channel==channel) :
                tchannel=cc.tchannel
            if(DEBUG>2) :
              echo "sched resolved temp channel: ", tchannel, " for channel: ",channel
            if(DEBUG>1) :
              echo "sched is trying to get last temp for temp channel:", tchannel
            chanReqOneTemp.send(tchannel)
            if(DEBUG>2) :
              echo "requested last temperature for channel: ",tchannel
            lastTempMeas=chanRespOneTemp.recv()
            if(lastTempMeas != nil) :
              tempTime=lastTempMeas[].mTime
              fTemp=lastTempMeas[].mTemp
              if(DEBUG>1) :
                echo "received temp: ",fTemp," for channel ",channel
            else :  
              if(DEBUG>1) :
                echo "received nil from chanRespOneTemp for channel ", channel
              tempTime=initTime(0, 0)
              fTemp=ERR_TEMP
              
            diff=toTime(now)-tempTime
            if(DEBUG>1) :
              echo "tempTime diff: ", diff.inSeconds
            if( (tempTime!=initTime(0, 0)) and (fTemp!=ERR_TEMP) and (int(float(diff.inSeconds)/60.0) < MAX_TEMP_USABLE) ):
# trying to use temp
              if(DEBUG>1) :
                echo "trying to use temp to send command for channel ",channel
              if(toInt(fTemp)<arrSchedTimeInfoTempEvent[lastTempEvtIndex[j]].temp) :
                cmd="on"
              else :
                if(toInt(fTemp)>arrSchedTimeInfoTempEvent[lastTempEvtIndex[j]].temp) :
                  cmd="off"
              if(DEBUG>1) :
                echo "last command: ",lastCommand[j]," sent ",lastCmdSend[j]," times"
              if( not ( (lastCommand[j]==cmd) and (lastCmdSend[j]>MAX_TEMP_CMD_SEND) ) ) :
                if(DEBUG>0) :
                  echo "sched is sending temp command \'",cmd,"\' to channel:",j," at temp:",fTemp
                res = sendUsbCommand(cmd, cuchar(j), cuchar(0))
                act.aTime = getTime()
                act.aAct = cmd
                act.aRes = res
                boolRes = nooDbPutAction(j, act)
                if(DEBUG>2) :
                  echo "Put action to DB result: ", boolRes
                if(DEBUG>0) :
                  echo "sched got result: ",res
                if(res==NO_ERROR) :
                  sendCmdTime[j]=getTime()
                  if(lastCommand[j]==cmd) :
                    inc lastCmdSend[j]
                    if(DEBUG>1) :
                      echo "incrementing lastCmdSend: ",lastCmdSend[j]
                  else :
                    lastCommand[j]=cmd
                    lastCmdSend[j]=1
                sleep(200)
            else :
# fallback to default command
              if(DEBUG>0) :
                echo "fallback to default command for channel ",channel," diff: ",diff
              cmd=arrSchedTimeInfoTempEvent[lastTempEvtIndex[j]].command
              if(DEBUG>1) :
                echo "last command: ",lastCommand[j]," sent ",lastCmdSend[j]," times"
              if( not ( (lastCommand[j]==cmd) and (lastCmdSend[j]>MAX_TEMP_CMD_SEND) ) ) :
                if(DEBUG>0) :
                  echo "sched is sending default command \'",cmd,"\' to channel:",j
                res = sendUsbCommand(cmd, cuchar(j), cuchar(0))
                act.aTime = getTime()
                act.aAct = cmd
                act.aRes = res
                boolRes = nooDbPutAction(j, act)
                if(DEBUG>2) :
                  echo "Put action to DB result: ", boolRes
                if(DEBUG>0) :
                  echo "sched got result: ",res
                if(res==NO_ERROR) :
                  sendCmdTime[j]=getTime()
                  if(lastCommand[j]==cmd) :
                    inc lastCmdSend[j]
                    if(DEBUG>1) :
                      echo "incrementing lastCmdSend: ",lastCmdSend[j]
                  else :
                    lastCommand[j]=cmd
                    lastCmdSend[j]=1
                sleep(200)
      if(DEBUG_MEM>0) :
        echo "Sent Temp Events TotalMem: ",getTotalMem()
        echo "Sent Temp Events FreeMem: ",getFreeMem()
        echo "Sent Temp Events OccupiedMem: ",getOccupiedMem()
      try :
        arrSchedTimeInfoTempEvent.delete(arrSchedTimeInfoTempEvent.low,arrSchedTimeInfoTempEvent.high)        
      except :
        echo "Exception cleaning arrSchedTimeInfoTempEvent"
      if(DEBUG_MEM>0) :
        echo "Finished Temp Events TotalMem: ",getTotalMem()
        echo "Finished Temp FreeMem: ",getFreeMem()
        echo "Finished Temp OccupiedMem: ",getOccupiedMem()
    sleep(SLEEP_ON_SCHED)

proc conf() {.thread.} =
  var seqChannelConf : SeqChanConf
  var seqSchedEvt : SeqSchedEvent
  var intRes : int
  var totalChanConf : int
  var dtint: tuple[dataAvailable: bool, msg: int]
  var channel : int
  var channelName : string
  var tchannel : int
  var profile : int

  if(DEBUG>1) :
    echo "nooconf is trying to read channels config"
#  totalChanConf = getChannelConf(seqChannelConf)
  totalChanConf = nooDbGetChanConf(seqChannelConf)
  
  if(DEBUG>1) :
    echo "channels config read: ", totalChanConf
  while(true) :
    sleep(200)
# ********* check conf data request from other threads and send data **********
#  chanConfReqChanName.open()
#  chanConfRespChanName.open()
#  chanConfReqTempName.open()
#  chanConfRespTempName.open()
#  chanConfReqTempChan.open()
#  chanConfRespTempChan.open()

# ********* Other thread requests channel name *************
    dtint=chanConfReqChanName.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for channel name: " & intToStr(dtint.msg)
      channel=dtint.msg
      channelName=""
      for i in seqChannelConf.low..seqChannelConf.high :
        if(seqChannelConf[i].channel==channel) :
          channelName=seqChannelConf[i].cname
      if(DEBUG>2) :
        echo "sending reponse with name: " & channelName
      chanConfRespChanName.send(channelName)

# ********* Other thread requests temperature channel name *************
    dtint=chanConfReqTempName.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for temp channel name: " & intToStr(dtint.msg)
      channel=dtint.msg
      channelName=""
      for i in seqChannelConf.low..seqChannelConf.high :
        if(seqChannelConf[i].tchannel==channel) :
          channelName=seqChannelConf[i].cname
      if(DEBUG>2) :
        echo "sending reponse with name: " & channelName
      chanConfRespTempName.send(channelName)

# ********* Other thread requests temperature channel number *************
    dtint=chanConfReqTempChan.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for temp channel: " & intToStr(dtint.msg)
      channel=dtint.msg
      tchannel=0
      for i in seqChannelConf.low..seqChannelConf.high :
        if(seqChannelConf[i].channel==channel) :
          tchannel=seqChannelConf[i].tchannel
      if(DEBUG>2) :
        echo "sending reponse with channel: " & intToStr(tchannel)
      chanConfRespTempChan.send(tchannel)

# ********* Other thread requests channel configuration *************
    dtint=chanReqChanConf.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for configuration of channel ", dtint.msg
      channel=dtint.msg
      seqChannelConf = newSeq[ChanConf]()      
      if(channel>0 and channel<=MAX_CHANNEL) :
        intRes = nooDbGetChanConf(channel, seqChannelConf)
      else :
        if(channel==0) :
          intRes = nooDbGetChanConf(seqChannelConf)
      if(DEBUG>1) :
        echo "conf received ", intRes, " configuration values from database"
      chanRespChanConf.send(seqChannelConf)

# ********* Other thread requests scheduled events *************
    dtint=chanReqSchedEvt.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for scheduled events for profile number ", dtint.msg
      profile=dtint.msg
      seqSchedEvt = newSeq[SchedEvent]()
      intRes = nooDbGetSchedProfile(profile, seqSchedEvt)
      if(DEBUG>1) :
        echo "conf received ", intRes, " scheduled events for profile number ", profile, " from database"
      chanRespSchedEvt.send(seqSchedEvt)

proc nooStart(mode : startMode) =
  var L : Lock
  var thrWeb : Thread[void]
  var thrSched : Thread[void]
  var thrTemp : Thread[void]
  var thrConf : Thread[void]

  chanReqAct.open()
  chanRespAct.open()
  chanReqTemp.open()
  chanRespTemp.open()
  chanPutTemp.open()
  chanReqOneTemp.open()
  chanRespOneTemp.open()  
  chanConfReqChanName.open()
  chanConfRespChanName.open()
  chanConfReqTempName.open()
  chanConfRespTempName.open()
  chanConfReqTempChan.open()
  chanConfRespTempChan.open()
  chanReqChanConf.open()
  chanRespChanConf.open()
  chanReqSchedEvt.open()
  chanRespSchedEvt.open()
  
  initLock(L)
  acquire(L) # lock stdout
  if(DEBUG>0) :
    echo "Starting Conf thread..."
  createThread[void](thrConf, conf)
  sleep(1000)
  if(DEBUG>0) :
    echo "Starting Temp thread..."
  createThread[void](thrTemp, temp)
  sleep(1000)
  if(DEBUG>0) :
    echo "Starting Web thread..."
  createThread[void](thrWeb, web)
  sleep(300)
  if(mode == modeservice) :
    if(DEBUG>0) :
      echo "Starting Scheduler thread..."
    createThread[void](thrSched, sched)
  release(L)
#[
  if(DEBUG>2) :
    echo "chanReqAct waiting: ", chanReqAct.ready()
    echo "chanReqTemp waiting: ", chanReqTemp.ready()
    echo "chanConfReqChanName waiting: ", chanConfReqChanName.ready()
    echo "chanConfRespTempName waiting: ", chanConfRespTempName.ready()
    echo "chanConfReqTempChan waiting: ", chanConfReqTempChan.ready()
]#  
  while (true) :
    sleep(1000)
    if(not thrConf.running) :
      acquire(L) # lock stdout
      if(DEBUG>0) :
        echo "Restarting Conf thread..."
      createThread[void](thrConf, conf)
      release(L)
    if(not thrWeb.running) :
      acquire(L) # lock stdout
      if(DEBUG>0) :
        echo "Restarting Web thread..."
      createThread[void](thrWeb, web)
      release(L)
    if(mode == modeservice) :
      if(not thrSched.running) :
        acquire(L) # lock stdout
        if(DEBUG>0) :
          echo "Restarting Scheduler thread..."
        createThread[void](thrSched, sched)
        release(L)
    if(not thrTemp.running) :
      acquire(L) # lock stdout
      if(DEBUG>0) :
        echo "Restarting Temp thread..."
      createThread[void](thrTemp, temp)
      release(L)

when declared(commandLineParams):
  var res : int = 0
  var channel : int = 0
  var level : int = 0
  var thr : Thread[void]
  var confirm : string

  let args = commandLineParams()
  if args.len < 1 :
    usage()
    quit (1)
  else:
    case args[0] :
      of "web" :
        nooStart(modeweb)
      of "service" :
        nooStart(modeservice)
      of "initdb" :
        echo "Are you sure to initialise the database?"
        echo "All existing data will be destroyed!!"
        echo "Y/N ?"
        confirm = readLine(stdin)
        if(confirm == "Y" or confirm == "y") :
          nooDbInit()
          for i in 1..MAX_TEMP_CHANNEL :
            res=nooDbImportTemp(i, statusTempFileName&intToStr(i)) 
            echo "Imported ", res, " temperature records from ", statusTempFileName&intToStr(i), " file"
        else :
          echo "Not confirmed, aborting..."
          quit(1)
      of "on","off","sw","set","bind","unbind","preset" :
        if (args.len < 2) :
          usage()
          quit (1)
        else :
          res = parseInt(args[1],channel)
          if (res == 0) :
            echo "Error reading channel from command line"
            usage()
            quit (1)
          if (channel>MAX_CHANNEL) or (channel<0) :
            echo "Error reading channel from command line"
            usage()
            quit (1)
#          else :
#            channel = channel - 1
          case args[0] :
            of "set" :
              if (args.len) < 3 :
                usage()
                quit (1)
              else :
                res = parseInt(args[2],level)
                if(res == 0) :
                  echo "Error reading level from command line"
                  usage()
                  quit (1)
                if (level < 0) : level=0
                if (level > 100) : level=100
                level=(int)(34.0+1.23*(float)level)
            else :
              discard
          res = sendUsbCommand(args[0],(cuchar)channel,(cuchar)level)
          case res :
            of ERR_NO_DEVICE :
              echo("Cannot find nooLite device")
              quit (1)
            of ERR_ERR_CONFIG :
              echo("Cannot set configuration")
              quit (1)
            of ERR_CLAILM_IF :
              echo("Cannot claim interface")
              quit (1)
            of NO_ERROR :
              echo("Success")
              quit (0)
            else :
              echo "Control result: " & intToStr(res)
              quit (0)
      else:
        discard

else:
  usage()
  quit (1)
