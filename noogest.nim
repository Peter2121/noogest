import os,tables,parseutils,jester,json,strutils,times,sets,htmlgen,strtabs,asyncdispatch,locks,times,pegs,qsort,sequtils,math,threadpool,random,json,uri
import dbnoogest,nootypes,nooconst,noojsonconst,noousb

const
  MAX_COMMANDS : int = 7
#  BUF_SIZE = 8'u16
#  MAX_SCHED_EVENTS : int = 256
  MAX_MIN_SCHED : int = 360
  SLEEP_ON_SCHED : int = 60000 # milliseconds
#  SLEEP_ON_SCHED : int = 55000
  NO_TEMP : float = 1000.0
  ERR_TEMP : float = 2000.0
  DELTA_TEMP : float = 0.3 # precision of keeping temperature
  MAX_TEMP_VALUES : int = 50 # max number of temperatue measurements we send to other threads from temp() thread
  MAX_ACT_VALUES : int = 50 # max number of actions we send to other threads from temp() thread
  MAX_TEMP_MEASUREMENTS : int = 100 # max number of temperatue measurements we stock in memory
  MAX_TEMP_USABLE : int = 130  # minutes, during this time we consider temp measurement as usable
  MAX_CMD_FREQ : int = 1  # minutes, we don't send command more frequently than this value
  MAX_TEMP_CMD_SEND : int = 2 # repeat the same commands X times during MAX_TIME_TEMP_CMD_SEND
  MAX_TIME_TEMP_CMD_SEND : int = 120 # minutes
  MAX_SCHED_CMD_SEND : int = 2 # repeat the same commands X times during MAX_TIME_TEMP_CMD_SEND
  MAX_TIME_SCHED_CMD_SEND : int = 120 # minutes
  MAX_TIME_TEMP_WEB_RESP : int = 72 # hours, we don't send to web client temperature values older than this value
  MAX_TIME_TEMP_IN_DB : int = 144 # hours, we delete automatically from database temperature values older than this value
  MAX_TIME_ACT_WEB_RESP : int = 72 # hours, we don't send to web client actions older than this value
  MAX_TIME_ACT_IN_DB : int = 144 # hours, we delete automatically from database actions older than this value
  CLEAN_DB_TEMP : bool = true # clean old temperature meaurements from database?
  CLEAN_DB_ACT : bool = true # clean old actions from database?
  TEST_TEMP : float = 20.0
  TEST_TEMP_VAR : float = 5.0
  TEST_TEMP_SLEEP : int = 500 # milliseconds
  TEST_TEMP_CYCLES : int = 100 # temp simulated every TEST_TEMP_CYCLES*TEST_TEMP_SLEEP

const
  confSchedFileName : string = "sched.conf"
  confTempSchedFileName : string = "temp.conf"
  confChanFileName : string = "chan.conf"
  statusTempFileName : string = "tmch"

const
  DT_FORMAT_ACT = "yyyy/MM/dd HH:mm:ss"
  DT_FORMAT_TEMP = "yyyy/MM/dd HH:mm:ss"

type
  startMode = enum
    modeweb, modeservice

type
  TempRequest = object
    channel : int
    nmax : int
    last : int

type
  ActRequest = object
    channel : int
    nmax : int
    last : int

type
  TempArray = array[1..MAX_CHANNEL, seq[TempMeasurementObj]]

type
  IntChannel = Channel[int]
#  FloatChannel = Channel[float]
  StringChannel = Channel[string]
  BoolChannel = Channel[bool]
  TempReqChannel = Channel[TempRequest]
  TempRespChannel = Channel[TempMeasurement]
  TempMeasChannel = Channel[TempChanMeasurement]
  ActReqChannel = Channel[ActRequest]
  ChanConfChannel = Channel[SeqChanConf]
  SchedEvtChannel = Channel[SeqSchedEvent]
  SchedTempEvtChannel = Channel[SeqSchedTempEvent]
  TChanProfChannel = Channel[TChanProfile]
  TProfReqChannel = Channel[int]
  TProfRespChannel = Channel[SeqTProfile]
  SProfReqChannel = Channel[int]
  SProfRespChannel = Channel[SeqSProfile]

proc `$`(s: ChanConf) : string =
  result = intToStr(s.channel) & " " & intToStr(s.tchannel) & " " & s.ctype & " " & s.cname

proc `$`(s: SchedEvent) : string =
  result = intToStr(s.hrs) & ":" & intToStr(s.mins) & " " & intToStr(s.channel) & " " & s.command

proc `<`(a,b: SchedEvent) : bool =
  if(a.hrs<b.hrs) : result=true
  else :
    if(a.hrs>b.hrs) : result=false
    else : result=(a.mins<b.mins)

proc `$`(s: SchedTempEvent) : string =
  result = intToStr(s.hrs) & ":" & intToStr(s.mins) & " " & intToStr(s.channel) & " " & $(s.temp) & " " & s.command

type
  PTimeInfo = ref DateTime

  TimeInfoEvent = ref object of PTimeInfo
    channel : int
    command : string

  TimeInfoTempEvent = ref object of TimeInfoEvent
    temp : float

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
  result.temp=NO_TEMP

proc newTimeInfoTempEvent(ch: int; cmd: string; temp: float) : TimeInfoTempEvent =
  new result
  result.initTimeInfoEvent(ch,cmd)
  result.temp=temp

proc `$`(tite: TimeInfoTempEvent) : string =
  result = `$`(PTimeInfo(tite)[]) & " channel:" & intToStr(tite.channel) & " command:" & tite.command & " temp:" & $(tite.temp)

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
var chanReqSchedTempEvt : IntChannel
var chanRespSchedTempEvt : SchedTempEvtChannel
var chanConfReqChan : IntChannel
var chanConfRespChan : IntChannel
var chanConfReqPutTChanProf : TChanProfChannel
var chanConfRespPutTChanProf : BoolChannel
var chanConfReqTProf : TProfReqChannel
var chanConfRespTProf : TProfRespChannel
var chanConfReqSProf : SProfReqChannel
var chanConfRespSProf : SProfRespChannel

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

# TODO: ask another thread for actions
proc maySendCommand(cmd : string, channel : int, maxcmd : int) : bool =
  var sAct : seq[ActionObj]
  var res : int
  var maxActions : int
  var dtmLastAction : int = 0
  var cntAction : int = 0
  var lastActTime : Time
  var fromLastAction : int64
  maxActions = (int)2*MAX_TIME_TEMP_CMD_SEND/(MAX_TEMP_CMD_SEND*MAX_CMD_FREQ)
  sAct=newSeq[ActionObj]()
  if(DEBUG>1) :
    echo "Trying to get ", maxActions, " actions during last ", MAX_TIME_TEMP_CMD_SEND, " minutes from database"
  res = nooDbGetAction(channel, sAct, maxActions, MAX_TIME_TEMP_CMD_SEND*60)
  if(DEBUG>1) :
    echo "Got ", res, " actions"
  for act in sAct :
    if(DEBUG>2) :
      echo "Action: ", $act
    if(act.aAct != cmd) :
      cntAction = 0
      lastActTime = initTime(0,0)
      continue
    else :
      inc(cntAction)
      lastActTime=act.aTime
  if(DEBUG>1) :
    echo "Count: ", cntAction, " actions \'", cmd, "\' for ", maxcmd, " maximum"
  if(cntAction>maxcmd) :
    return false
  else :
    fromLastAction = getTime().toUnix() - lastActTime.toUnix()
    if(DEBUG>2) :
      echo "fromLastAction: ", fromLastAction
    if( fromLastAction > MAX_CMD_FREQ*60 ) :
      return true
    else :
      return false

proc cleanTemper(channel : int) : bool =
  if(DEBUG>1) :
    echo "Cleaning temperature data older than ", MAX_TIME_TEMP_IN_DB, " hours"
  let last = MAX_TIME_TEMP_IN_DB*3600
  let boolRes = nooDbCleanTemper(channel, last)
  if(DEBUG>2) :
    echo "Cleaning temperature status: ", boolRes
  return boolRes

proc cleanAction(channel : int) : bool =
  if(DEBUG>1) :
    echo "Cleaning actions older than ", MAX_TIME_ACT_IN_DB, " hours"
  let last = MAX_TIME_ACT_IN_DB*3600
  let boolRes = nooDbCleanAction(channel, last)
  if(DEBUG>2) :
    echo "Cleaning action status: ", boolRes
  return boolRes

proc temp() {.thread.} =
  var nd : NooData
  var channel : int
  var nmax : int
  var last : int
  var command : int
  var dformat : int
  var iTemp : int
  var fTemp : float
  var res : int
  var boolRes : bool
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
# ********* check last temperature request from other threads and send data as TempMeasurement **********
    doti=chanReqOneTemp.tryRecv()
    if(doti.dataAvailable) :
      if(DEBUG>1) :
        echo "temp received request for last temp on channel: ", doti.msg
      channel=doti.msg
      refTM = new TempMeasurementObj
      if(refTM != nil) :
        boolRes = nooDbGetLastTemper(channel, refTM[])
        if(DEBUG>1) :
          echo "get last temp status: ", boolRes
      else :
        if(DEBUG>0) :
          echo "Cannot allocate memory for new temperature measurement"
      chanRespOneTemp.send(refTM)

# ********* check temperature data put request from other threads and put temp data to DB and to array **********
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
        boolRes=nooDbPutTemper(channel, refTM[])
        if(DEBUG>1) :
          echo "wrote temp status: ", boolRes
      else :
        if(DEBUG>0) :
          echo "Cannot allocate memory for new temperature measurement"
      if(CLEAN_DB_TEMP) :
        discard cleanTemper(channel)

# ********* check temperature data request from other threads and send data in formatted string **********
    dti=chanReqTemp.tryRecv()
    if(dti.dataAvailable) :
      if(DEBUG>1) :
        echo "temp received request for temp on channel: ",dti.msg.channel
        echo "\tfor last: ",dti.msg.last," seconds"
        echo "\tmax number of points requested: ",dti.msg.nmax
      channel=dti.msg.channel
      nmax=dti.msg.nmax
      last=dti.msg.last
      strResp=""
      if( (channel>0) and (channel<(MAX_TEMP_CHANNEL+1)) ) :
        sTM = newSeq[TempMeasurementObj]()
        res = nooDbGetTemper(channel, sTM, nmax, last)
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
      last=dai.msg.last
      strResp=""
      if( (channel>0) and (channel<(MAX_TEMP_CHANNEL+1)) ) :
        sAct=newSeq[ActionObj]()
        strResp=""
        res = nooDbGetAction(channel, sAct, nmax, last)
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
            boolRes=nooDbPutTemper(channel, refTM[])
            if(DEBUG>1) :
              echo "wrote temp status: ", boolRes
          else :
            if(DEBUG>0) :
              echo "Cannot allocate memory for new temperature measurement"
          if(CLEAN_DB_TEMP) :
            discard cleanTemper(channel)
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
            boolRes=nooDbPutTemper(channel, refTM[])
            if(DEBUG>1) :
              echo "wrote temp status: ", boolRes
          else :
            if(DEBUG>0) :
              echo "Cannot allocate memory for new temperature measurement"
          if(CLEAN_DB_TEMP) :
            discard cleanTemper(channel)

      else :
        if(DEBUG>1) : echo "temp got error: getUsbData result - ",res

proc getProfileJson(channel : int, profile : int, seqSchedTempEvt : SeqSchedTempEvent) : string =
  var respProfile : string = ""
  var objTempEvt : JsonNode
  var jsonResp : JsonNode
  var arrTempEvt : JsonNode
  if(DEBUG>2) :
    echo "Trying to construct JSON for profile: ", $seqSchedTempEvt
    echo "\tused on channel: ", channel
  var objChan = %* { JSON_DATA_TEMP_CHAN : channel }
  var objProf = %* { JSON_DATA_PROFILE : profile }
  jsonResp = newJObject()
  jsonResp.add(JSON_DATA_TEMP_CHAN, objChan)
  jsonResp.add(JSON_DATA_PROFILE, objProf) 
  arrTempEvt = newJArray()
  for ste in seqSchedTempEvt :
    objTempEvt = %* { JSON_DATA_HOUR : ste.hrs, JSON_DATA_MIN : ste.mins, JSON_DATA_TEMP : ste.temp, JSON_DATA_ACTION : ste.command }
    arrTempEvt.add(objTempEvt)
    if(DEBUG>2) :
      echo "arrTempEvt: ", $arrTempEvt
  jsonResp.add(JSON_DATA_TEMP_EVENTS, arrTempEvt)
  if(DEBUG>2) :
    echo "jsonResp: ", $jsonResp
  respProfile = $jsonResp
  return respProfile
  
proc getTProfileNamesJson(seqTProfileNames : SeqTProfile) : string =
  var respTProfNames : string = ""
  var tp : TProfileObj
  var arrProfiles : JsonNode
  var jsonProfile : JsonNode
  arrProfiles = newJArray()
  for tp in seqTProfileNames :
    jsonProfile = %* { JSON_DATA_ID : tp.id_profile, JSON_DATA_NAME : tp.name }
    arrProfiles.add(jsonProfile)
  respTProfNames = $arrProfiles
  return respTProfNames

proc web() {.thread.} =

  echo "Starting Web interface..."

  routes:
    get "/":
      var selChannel : string = ""
      var optChannels : string = ""
      var selCommand : string = ""
      var optCommands : string = ""
      var strInputLevel : string = "Level:"
      var strDygDivId : string = ""
      var strProfDivId : string = ""
      var strProfDDDiv : string = ""
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
        strDygDivId = "dygdiv" & intToStr(i)
        strProfDivId = "profdiv" & intToStr(i)
        strProfDDDiv = "profdddiv" & intToStr(i)
        strDygTable &= `tr`(`td`(`div`(id=strDygDivId)),`td`(`div`(id=strProfDivId)), `td`(`div`(id=strProfDDDiv)))
      resp head(
        link(href="/css/table.css", rel="stylesheet"),
        script(src="/js/dygraph.js", `type`="text/javascript"),
        script(src="/js/minajax.js", `type`="text/javascript"),
        script(src="/js/dygraph-combined-dev.js", `type`="text/javascript")
        ) & body(onload="startTempTimer()",
        script(src="/js/ngclient.js", `type`="text/javascript"),
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
      if(CLEAN_DB_ACT) :
        discard cleanAction(intChannel)
      if(res==NO_ERROR) :
        resp "Success"
      else :
        resp "Result: " & intToStr(res)

    get "/act":
      var respAct : string = ""
      var reqChannel : int
      var reqMaxValues : int
      var reqLast : int
      var res : int
      var actReq : ActRequest
      let params = request.params
      res = parseInt($params["channel"],reqChannel)
      if(res == 0) : reqChannel=0
      res = parseInt($params["nmax"],reqMaxValues)
      if(res == 0) : reqMaxValues=MAX_ACT_VALUES
      res = parseInt($params["last"],reqLast)
      if(res == 0) : reqLast=MAX_TIME_ACT_WEB_RESP*3600
      if(DEBUG>0) :
        echo "web is trying to request actions for channel ",reqChannel," reqMaxValues: ",reqMaxValues," for last ", reqLast, " seconds"
      if(reqChannel>0) :
        actReq.channel = reqChannel
        actReq.nmax = reqMaxValues
        actReq.last = reqLast
        chanReqAct.send(actReq)
#        if(DEBUG>1) :
#          echo "requested channel: ",actReq.channel," nmax: ",actReq.nmax
        respAct = chanRespAct.recv()
        if(DEBUG>1) :
          echo "received: ",respAct, " actions"
      resp respAct

    get "/ntprofiles":
      var respProfiles : string = ""
      var seqTProfileNames : SeqTProfile
      if(DEBUG>0) :
        echo "web is trying to request available temperature profile names"
      chanConfReqTProf.send(0)
      seqTProfileNames=chanConfRespTProf.recv()
      respProfiles=getTProfileNamesJson(seqTProfileNames)
      resp respProfiles

    get "/profile":
      var channel : int = 0
      var reqChannel : int
      var res : int
      var profile : int
      var respProfile : string = ""
#      var objTempEvt : JsonNode
      var objProf : JsonNode
      var seqChannelConf : SeqChanConf
      var seqSchedTempEvt : SeqSchedTempEvent
      let params = request.params
      res = parseInt($params["channel"],reqChannel)
      if(res == 0) : reqChannel=0
      if(DEBUG>0) :
        echo "web is trying to request actual profile for temperature channel ",reqChannel
      if(reqChannel>0) :
        chanConfReqChan.send(reqChannel)
        if(DEBUG>2) :
          echo "requested channel number for temp channel: ",reqChannel
        channel=chanConfRespChan.recv()
        if(DEBUG>2) :
          echo "received: ",channel
        if(DEBUG>1) :
          echo "Requesting configuration for channel: ", channel
        chanReqChanConf.send(channel)
        seqChannelConf = chanRespChanConf.recv()
        if(DEBUG>2) :
          echo "received ", seqChannelConf.len(), " configuration elements for channel ", channel
        if(seqChannelConf.len()>0) :
          if(DEBUG>2) :
            echo "Working with configuration: ", $seqChannelConf[seqChannelConf.high()]
          if(seqChannelConf[seqChannelConf.high()].ctype==CHAN_USE_TEMP) :
            profile = seqChannelConf[seqChannelConf.high()].profile
            if(DEBUG>1) :
              echo "Requesting temperature events for profile: ", profile, " used on channel ", channel
            chanReqSchedTempEvt.send(profile)
            seqSchedTempEvt = chanRespSchedTempEvt.recv()
            if(DEBUG>1) :
              echo "received ", seqSchedTempEvt.len(), " temperature events"
            if(seqSchedTempEvt.len()>0) :
              respProfile = getProfileJson(reqChannel, profile, seqSchedTempEvt)
      if(DEBUG>1) :
        echo "Web is sending profile: ", respProfile
      resp respProfile
      
    get "/temp":
#      var fTemp : float
#      var seqTemp : array[1..MAX_TEMP_CHANNEL,float]
      var respTemp : string = ""
      var reqChannel : int
      var reqMaxValues : int
      var reqLast : int
      var res : int
      var tReq : TempRequest
      var strChannelName : string

      let params = request.params
#  TempReqChannel = Channel[TempRequest]
      res = parseInt($params["channel"],reqChannel)
      if(res == 0) : reqChannel=0
      res = parseInt($params["nmax"],reqMaxValues)
      if(res == 0) : reqMaxValues=MAX_TEMP_VALUES
      res = parseInt($params["last"],reqLast)
      if(res == 0) : reqLast=MAX_TIME_TEMP_WEB_RESP*3600
      if(DEBUG>0) :
        echo "web is trying to request temperature for channel ",reqChannel," reqMaxValues: ",reqMaxValues, " for last ", reqLast, " seconds"
      if(reqChannel>0) :
#  TempRequest = object
#    channel : int
#    nmax : int
#    last : int
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
        tReq.last = reqLast
        respTemp = intToStr(tReq.channel) & "\n" & strChannelName & "\nDTime,Temp\n"
        chanReqTemp.send(tReq)
        if(DEBUG>1) :
          echo "requested channel: ",tReq.channel," nmax: ",tReq.nmax
        respTemp &= chanRespTemp.recv()
        if(DEBUG>1) :
          echo "received: ",respTemp
      resp respTemp
    
    post "/profile":
      if(DEBUG>2) :
        echo "/profile Received body: ", decodeUrl(request.body)
      let jsonData = parseJson(decodeUrl(request.body).split("=")[0])
      if(DEBUG>2) :
        echo "/profile Received json: ", $jsonData
      var boolRes : bool
      var strRepStatus : string = ""
      var intRepStatus : int
      var jsonRepStatus : JsonNode
      var tchp : TChanProfile
      tchp.tchannel=jsonData{JSON_DATA_TEMP_CHAN}.getInt()
      tchp.profile=jsonData{JSON_DATA_PROFILE}.getInt()
      tchp.dow=jsonData{JSON_DATA_DOW}.getInt() # 0 for current DOW
      chanConfReqPutTChanProf.send(tchp)
      boolRes = chanConfRespPutTChanProf.recv()
      if(boolRes) :
        intRepStatus = JSON_REPLY_STATUS_OK
      else :
        intRepStatus = JSON_REPLY_STATUS_FAILED
      jsonRepStatus =  %* {JSON_DATA_TEMP_CHAN : tchp.tchannel, JSON_REPLY_STATUS : intRepStatus}
      strRepStatus = $jsonRepStatus
      if(DEBUG>2) :
        echo "Replying with json: ", strRepStatus
      resp strRepStatus      
      
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

# TODO: correctly process events near midnight
proc sched() {.thread.} =
#  var arrSchedEvt = newSeq[SchedEvent]()
  var seqSchedEvt : SeqSchedEvent
  var totalEvt : int
  var arrSchedTimeInfoEvent = newSeq[TimeInfoEvent]()
#  var arrSchedTempEvt = newSeq[SchedTempEvent]()
  var seqSchedTempEvt : SeqSchedTempEvent
  var sAct : seq[ActionObj]
  var totalTempEvt : int
  var arrSchedTimeInfoTempEvent = newSeq[TimeInfoTempEvent]()
  var seqChannelConf : SeqChanConf
  var totalChanConf : int
#  var sendCmdTime : array[1..MAX_CHANNEL,Time]
#  var lastCommand : array[1..MAX_CHANNEL,string]
#  var lastCmdSend : array[1..MAX_CHANNEL,int]
  var chanUseSched : array[1..MAX_CHANNEL,bool]
  var chanUseTemp : array[1..MAX_CHANNEL,bool]
  var lastTempEvtIndex : array[1..MAX_CHANNEL,int]
  var arrChannelProfileId : array[1..MAX_CHANNEL,int]
  var dayOfWeek : int
  var now : DateTime
  var evt : DateTime
#  var tReq : TempRequest
  var respTemp : string
#  var seqRespTemp : seq[string]
  var fTemp : float
  var tempTimeInfo : DateTime
  var tempTime : Time
  var chanTempPresent : bool = false
  var chanSchedPresent : bool = false
  let maxSecSched = MAX_MIN_SCHED*60
  var jj : int
#  var diff : int64
  var diff : Duration
  var res : int
  var channel,tchannel,profile : int
  var cmd : string
  var act : ActionObj
  var boolRes : bool
  var deltaTemp : float
  var lastTempMeas : TempMeasurement
  var nowWeekDay = int(ord(getLocalTime(getTime()).weekday))
  inc(nowWeekDay)
  echo "Current weekday: ",nowWeekDay
  sleep(500)

  for channel in 1..MAX_CHANNEL :
    chanUseSched[channel] = false
    chanUseTemp[channel] = false
#    lastCommand[channel] = ""
#    sendCmdTime[channel] = initTime(0, 0)
#    lastCmdSend[channel] = 0
#[    
  for cc in seqChannelConf :
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
]#        
# ********** Main cycle ******************        
  while (true) :
    now = getLocalTime(getTime())
    if(DEBUG>2) :
      echo "Now we are ", $now
    if(DEBUG_MEM>0) :
      echo "Enter TotalMem: ",getTotalMem()
      echo "Enter FreeMem: ",getFreeMem()
      echo "Enter OccupiedMem: ",getOccupiedMem()
# ********* processing scheduled events ***********
#  SchedEvent = object of RootObj
#    dow : int
#    hrs : int
#    mins : int
#    channel : int
#    command : string
#  ChanConf = object
#    channel : int
#    tchannel : int
#    profile : int
#    ctype : string
#    cname : string
    if(nooDbIsSchedPresent()) :
      echo "Trying to process channels using schedule"
      for channel in 1..MAX_CHANNEL :
        if(DEBUG>1) :
          echo "Requesting configuration for channel: ", channel
        chanReqChanConf.send(channel)
        seqChannelConf = chanRespChanConf.recv()
#         normally we receive only 1 record        
        if(DEBUG>1) :
          echo "received ", seqChannelConf.len(), " configuration elements for channel ", channel
        if(seqChannelConf.len()==0) :
          echo "Skipping channel ", channel
          continue          
        if(DEBUG>2) :
          echo "Working with configuration: ", $seqChannelConf[seqChannelConf.high()]
        if(not (seqChannelConf[seqChannelConf.high()].ctype==CHAN_USE_SCHED)) :
          echo "Skipping channel ", channel, " as it is not using schedule"
          continue
        profile = seqChannelConf[seqChannelConf.high()].profile
        if(DEBUG>1) :
          echo "Requesting scheduled events for profile: ", profile, " used on channel ", channel
        chanReqSchedEvt.send(profile)
        seqSchedEvt = chanRespSchedEvt.recv()
        if(DEBUG>1) :
          echo "received ", seqSchedEvt.len(), " scheduled events"  
        for se in seqSchedEvt :
          if(DEBUG>2) :
            echo "sched is processing sched event: ", $se
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
            if(DEBUG>2) :
              echo "sched added event: ",arrSchedTimeInfoEvent.high
            arrSchedTimeInfoEvent[arrSchedTimeInfoEvent.high].second = 0
            arrSchedTimeInfoEvent[arrSchedTimeInfoEvent.high].hour = se.hrs
            arrSchedTimeInfoEvent[arrSchedTimeInfoEvent.high].minute = se.mins
          else :
            if(DEBUG>2) :
              echo "diff is not in range, skipping the event"
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
            cmd = arrSchedTimeInfoEvent[jj].command
            if(maySendCommand(cmd, channel, MAX_SCHED_CMD_SEND)) :
# TODO: use database to check last commands sent!!!                
#            if( not ( (lastCommand[arrSchedTimeInfoEvent[jj].channel]==arrSchedTimeInfoEvent[jj].command) and
#                    (lastCmdSend[arrSchedTimeInfoEvent[jj].channel]>MAX_SCHED_CMD_SEND) ) ) :
# ENDOF TODO              
              if(DEBUG>0) :
                echo "sched is sending event ",jj," : ",`$`(arrSchedTimeInfoEvent[jj])
              res = sendUsbCommand(cmd, cuchar(channel), cuchar(0))
              if(DEBUG>0) :
                echo "sched got result: ",res              
              act.aTime = getTime()
              act.aAct = arrSchedTimeInfoEvent[jj].command
              act.aRes = res
              boolRes = nooDbPutAction(channel, act)
              if(DEBUG>2) :
                echo "Put action to DB result: ", boolRes
              if(CLEAN_DB_ACT) :
                discard cleanAction(channel)                
# TODO: use database to check last commands sent!!!                
#              if(res==NO_ERROR) :
#                sendCmdTime[arrSchedTimeInfoEvent[jj].channel]=getTime()
#                if(lastCommand[arrSchedTimeInfoEvent[jj].channel]==arrSchedTimeInfoEvent[jj].command) :
#                  inc lastCmdSend[arrSchedTimeInfoEvent[jj].channel]
#                else :
#                  lastCommand[arrSchedTimeInfoEvent[jj].channel]=arrSchedTimeInfoEvent[jj].command
#                  lastCmdSend[arrSchedTimeInfoEvent[jj].channel]=1
              sleep(200)
# ENDOF TODO              
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
    if(nooDbIsTempPresent()) :
      for channel in 1..MAX_CHANNEL :
        if(DEBUG>1) :
          echo "Requesting configuration for channel: ", channel
        chanReqChanConf.send(channel)
        seqChannelConf = chanRespChanConf.recv()
        if(DEBUG>1) :
          echo "received ", seqChannelConf.len(), " configuration elements for channel ", channel
        if(seqChannelConf.len()==0) :
          echo "Skipping channel ", channel
          continue          
        if(DEBUG>2) :
          echo "Working with configuration: ", $seqChannelConf[seqChannelConf.high()]
        if(not (seqChannelConf[seqChannelConf.high()].ctype==CHAN_USE_TEMP)) :
          echo "Skipping channel ", channel, " as it is not using temperature"
          continue
        profile = seqChannelConf[seqChannelConf.high()].profile
        if(DEBUG>1) :
          echo "Requesting temperature events for profile: ", profile, " used on channel ", channel
        chanReqSchedTempEvt.send(profile)
        seqSchedTempEvt = chanRespSchedTempEvt.recv()
        if(DEBUG>1) :
          echo "received ", seqSchedTempEvt.len(), " temperature events"  
        for ste in seqSchedTempEvt :
          if(DEBUG>2) :
            echo "sched is processing temp event: ", $ste
          evt = getLocalTime(getTime())
          evt.second=0
          evt.minute=ste.mins
          evt.hour=ste.hrs
          if(DEBUG>2) :
            echo "sched got event DateTime object: ",$evt
  # filter on time
          diff=toTime(now)-toTime(evt)
          if(DEBUG>2) :
            echo "sched got diff: ", diff.inSeconds
          if(diff.inSeconds>0) :
            arrSchedTimeInfoTempEvent.add(newTimeInfoTempEvent())
            if(DEBUG>2) :
              echo "sched added temp event: ",arrSchedTimeInfoTempEvent.high
            arrSchedTimeInfoTempEvent[arrSchedTimeInfoTempEvent.high].second = 0
            arrSchedTimeInfoTempEvent[arrSchedTimeInfoTempEvent.high].hour = ste.hrs
            arrSchedTimeInfoTempEvent[arrSchedTimeInfoTempEvent.high].minute = ste.mins
            arrSchedTimeInfoTempEvent[arrSchedTimeInfoTempEvent.high].channel = channel
            arrSchedTimeInfoTempEvent[arrSchedTimeInfoTempEvent.high].command = ste.command
            arrSchedTimeInfoTempEvent[arrSchedTimeInfoTempEvent.high].temp = ste.temp
        if(arrSchedTimeInfoTempEvent.len()>0) :
          if(DEBUG>1) :
            echo "sched temp is working on ", $now, " processing ", arrSchedTimeInfoTempEvent.len(), " events"
# find the last event for every channel managed by temp
          qsort_inline(arrSchedTimeInfoTempEvent)
          lastTempEvtIndex[channel] = arrSchedTimeInfoTempEvent.high
          if(DEBUG>2) :
            echo "lastTempEvtIndex:\t", lastTempEvtIndex[channel]
            if(lastTempEvtIndex[channel] != -1) :
              echo "\t",`$`(arrSchedTimeInfoTempEvent[lastTempEvtIndex[channel]])
#          if( ((getTime()-sendCmdTime[channel]).inSeconds)*60 < MAX_CMD_FREQ) : 
#            continue
          if(lastTempEvtIndex[channel] != -1) :
# get the last measured temp for the channel
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
              deltaTemp=abs(fTemp-arrSchedTimeInfoTempEvent[lastTempEvtIndex[channel]].temp)
              if(DEBUG>2) :
                echo "deltaTemp: ", deltaTemp
              if(deltaTemp>TEMP_ACCURACY) :              
                if(fTemp<arrSchedTimeInfoTempEvent[lastTempEvtIndex[channel]].temp) :
                  cmd="on"
                else :
                  if(fTemp>arrSchedTimeInfoTempEvent[lastTempEvtIndex[channel]].temp) :
                    cmd="off"
# TODO: use database to check last commands sent!!!                                    
                if(maySendCommand(cmd, channel, MAX_TEMP_CMD_SEND)) :
                  if(DEBUG>2) :
                    echo "maySendCommand accepted the command ", cmd
#                if(DEBUG>1) :
#                  echo "command: ", cmd," sent ", res," times during last ", MAX_TIME_TEMP_CMD_SEND, " minutes"
#                  echo "last command: ",lastCommand[channel]," sent ",lastCmdSend[channel]," times"
#                if(DEBUG>2) :
#                  echo $sAct
#                if( not ( (lastCommand[channel]==cmd) and (lastCmdSend[channel]>MAX_TEMP_CMD_SEND) ) ) :
#                if( not ( res>MAX_TEMP_CMD_SEND ) ) :
# ENDOF TODO
                  if(DEBUG>0) :
                    echo "sched is sending temp command \'",cmd,"\' to channel:",channel," at temp:",fTemp
                  res = sendUsbCommand(cmd, cuchar(channel), cuchar(0))
                  act.aTime = getTime()
                  act.aAct = cmd
                  act.aRes = res
                  boolRes = nooDbPutAction(channel, act)
                  if(DEBUG>2) :
                    echo "Put action to DB result: ", boolRes
                  if(DEBUG>0) :
                    echo "sched got result: ",res
                  if(CLEAN_DB_ACT) :
                    discard cleanAction(channel)
# TODO: use database to check last commands sent!!!                
#                  if(res==NO_ERROR) :
#                    sendCmdTime[channel]=getTime()
#                    if(lastCommand[channel]==cmd) :
#                      inc lastCmdSend[channel]
#                      if(DEBUG>1) :
#                        echo "incrementing lastCmdSend: ",lastCmdSend[channel]
#                    else :
#                      lastCommand[channel]=cmd
#                      lastCmdSend[channel]=1
                  sleep(200)
# ENDOF TODO
              else :
                if(DEBUG>1) :
                  echo "Temperature is not changed"
            else :
# fallback to default command
              if(DEBUG>0) :
                echo "fallback to default command for channel ",channel," diff: ",diff
              cmd=arrSchedTimeInfoTempEvent[lastTempEvtIndex[channel]].command
              if(maySendCommand(cmd, channel, MAX_TEMP_CMD_SEND)) :
                if(DEBUG>2) :
                  echo "maySendCommand accepted the command ", cmd
#              if(DEBUG>1) :
#                echo "last command: ",lastCommand[channel]," sent ",lastCmdSend[channel]," times"
#              if( not ( (lastCommand[channel]==cmd) and (lastCmdSend[channel]>MAX_TEMP_CMD_SEND) ) ) :
                if(DEBUG>0) :
                  echo "sched is sending default command \'",cmd,"\' to channel:",channel
                res = sendUsbCommand(cmd, cuchar(channel), cuchar(0))
                act.aTime = getTime()
                act.aAct = cmd
                act.aRes = res
                boolRes = nooDbPutAction(channel, act)
                if(DEBUG>2) :
                  echo "Put action to DB result: ", boolRes
                if(DEBUG>0) :
                  echo "sched got result: ",res
                if(CLEAN_DB_ACT) :
                  discard cleanAction(channel)
# TODO: use database to check last commands sent!!!                
#                if(res==NO_ERROR) :
#                  sendCmdTime[channel]=getTime()
#                  if(lastCommand[channel]==cmd) :
#                    inc lastCmdSend[channel]
#                    if(DEBUG>1) :
#                      echo "incrementing lastCmdSend: ",lastCmdSend[channel]
#                  else :
#                    lastCommand[channel]=cmd
#                    lastCmdSend[channel]=1
                sleep(200)
# ENDOF TODO
          try :
            arrSchedTimeInfoTempEvent.delete(arrSchedTimeInfoTempEvent.low,arrSchedTimeInfoTempEvent.high)        
          except :
            echo "Exception cleaning arrSchedTimeInfoTempEvent"
      if(DEBUG_MEM>0) :
        echo "Sent Temp Events TotalMem: ",getTotalMem()
        echo "Sent Temp Events FreeMem: ",getFreeMem()
        echo "Sent Temp Events OccupiedMem: ",getOccupiedMem()
      if(DEBUG_MEM>0) :
        echo "Finished Temp Events TotalMem: ",getTotalMem()
        echo "Finished Temp FreeMem: ",getFreeMem()
        echo "Finished Temp OccupiedMem: ",getOccupiedMem()
    sleep(SLEEP_ON_SCHED)

proc conf() {.thread.} =
  var seqChannelConf : SeqChanConf
  var seqSchedEvt : SeqSchedEvent
  var seqSchedTempEvt : SeqSchedTempEvent
  var seqTProfileNames : SeqTProfile
  var intRes : int = 0
  var boolRes : bool = false
  var totalChanConf : int
  var dtint: tuple[dataAvailable: bool, msg: int]
  var dttchp: tuple[dataAvailable: bool, msg: TChanProfile]
  var channel : int
  var channelName : string
  var tchannel : int
  var profile : int

  while(true) :
    sleep(200)
# ********* check conf data request from other threads and send data **********

# ********* Other thread requests channel name *************
    dtint=chanConfReqChanName.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for channel name: " & intToStr(dtint.msg)
      channel=dtint.msg
      if(channel>0 and channel<=MAX_CHANNEL) :
        channelName=nooDbGetChanName(channel)
      else :
        channelName=""
      if(DEBUG>2) :
        echo "sending reponse with name: " & channelName
      chanConfRespChanName.send(channelName)

# ********* Other thread requests temperature channel name *************
    dtint=chanConfReqTempName.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for temp channel name: " & intToStr(dtint.msg)
      channel=dtint.msg
      if(channel>0 and channel<=MAX_TEMP_CHANNEL) :
        channelName=nooDbGetTempChanName(channel)
      else :
        channelName=""
      if(DEBUG>2) :
        echo "sending reponse with name: " & channelName
      chanConfRespTempName.send(channelName)

# ********* Other thread requests temperature channel number *************
    dtint=chanConfReqTempChan.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for temp channel number for channel: " & intToStr(dtint.msg)
      channel=dtint.msg
      if(channel>0 and channel<=MAX_CHANNEL) :
        tchannel=nooDbGetTempChanNumber(channel)
      else :
        tchannel=0
      if(DEBUG>2) :
        echo "sending reponse with temp channel number: " & intToStr(tchannel)
      chanConfRespTempChan.send(tchannel)

# ********* Other thread requests channel number for temperature channel *********
    dtint=chanConfReqChan.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for channel number for temperature channel: " & intToStr(dtint.msg)
      tchannel=dtint.msg
      if(tchannel>0 and tchannel<=MAX_TEMP_CHANNEL) :
        channel=nooDbGetChanNumber(tchannel)
      else :
        channel=0
      if(DEBUG>2) :
        echo "sending reponse with channel number: " & intToStr(channel)
      chanConfRespChan.send(channel)

# ********* Other thread requests channel configuration *************
    dtint=chanReqChanConf.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for configuration of channel ", dtint.msg
      channel=dtint.msg
      seqChannelConf = newSeq[ChanConf]()      
      if(channel>0 and channel<=MAX_CHANNEL) :
        intRes = nooDbGetChanConf(channel, seqChannelConf)
#      else :
#        if(channel==0) :
#          intRes = nooDbGetChanConf(seqChannelConf)
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

# ********* Other thread requests temperature scheduled events *************
    dtint=chanReqSchedTempEvt.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for temperature scheduled events for profile number ", dtint.msg
      profile=dtint.msg
      seqSchedTempEvt = newSeq[SchedTempEvent]()
      intRes = nooDbGetTempProfile(profile, seqSchedTempEvt)
      if(DEBUG>1) :
        echo "conf received ", intRes, " temperature scheduled events for profile number ", profile, " from database"
      chanRespSchedTempEvt.send(seqSchedTempEvt)

# ********* Other thread requests change temperature channel profile *************
    dttchp=chanConfReqPutTChanProf.tryRecv()
    if(dttchp.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request to change temperature channel ", dttchp.msg.tchannel, " to profile number ", dttchp.msg.profile
      boolRes = false
      if(dttchp.msg.dow==0) :
        boolRes = nooDbSetTChanProfile(dttchp.msg.tchannel, dttchp.msg.profile)
      else :
        if( (dttchp.msg.dow>0) and (dttchp.msg.dow<8) ) : 
          boolRes = nooDbSetTChanProfile(dttchp.msg.tchannel, dttchp.msg.profile, dttchp.msg.dow)
      chanConfRespPutTChanProf.send(boolRes)
      
# ********* Other thread requests list of available temperature profiles *************
    dtint=chanConfReqTProf.tryRecv()
    if(dtint.dataAvailable) :
      if(DEBUG>2) :
        echo "conf received request for temperature profile name: " & intToStr(dtint.msg)
      profile=dtint.msg # normally 0 - return list of all profiles
      seqTProfileNames=newSeq[TProfileObj]()
      intRes=nooDbGetTProfileName(profile, seqTProfileNames)
      if(DEBUG>2) :
        echo "sending ", $intRes, " reponses"
      chanConfRespTProf.send(seqTProfileNames)

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
  chanReqSchedTempEvt.open()
  chanRespSchedTempEvt.open()
  chanConfReqChan.open()
  chanConfRespChan.open()
  chanConfReqPutTChanProf.open()
  chanConfRespPutTChanProf.open()
  chanConfReqTProf.open()
  chanConfRespTProf.open()
#  chanConfReqSProf.open()
#  chanConfRespSProf.open()
  
  
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
