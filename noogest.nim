import os,tables,libusb,parseutils,jester,json,strutils,times,sets,htmlgen,strtabs,asyncdispatch,locks,times,pegs,qsort,sequtils,math,threadpool,random,json
import dbnoogest,nootypes


const
  DEBUG : int = 3 # from 0 (no debug messages at all) to 5 (all debug messages sent to stdout)
  DEBUG_MEM : int = 1
  TEST : int = 1 # if >0 we consider that there is no real temperature hardware present

const
  MAX_CHANNEL : int = 5
  MAX_TEMP_CHANNEL : int = 4
  MAX_COMMANDS : int = 7
  BUF_SIZE = 8'u16
#  MAX_SCHED_EVENTS : int = 256
  MAX_MIN_SCHED : int = 2
  SLEEP_ON_SCHED : int = 60000 # milliseconds
#  SLEEP_ON_SCHED : int = 55000
  NO_TEMP : float = 1000.0
  ERR_TEMP : float = 2000.0
  MAX_TEMP_VALUES : int = 50 # max number of temperatue measurements we send to other threads from temp() thread
  MAX_TEMP_MEASUREMENTS : int = 100 # max number of temperatue measurements we stock in memory
  MAX_TEMP_USABLE : int = 130  # minutes, during this time we consider temp measurement as usable
  MAX_CMD_FREQ : int = 5  # minutes, we don't send command more frequently than this value
  MAX_TEMP_CMD_SEND : int = 2 # repeat the same commands X times
  TEST_TEMP : float = 20.0
  TEST_TEMP_VAR : float = 5.0
  TEST_TEMP_SLEEP : int = 1000 # milliseconds
  TEST_TEMP_CYCLES : int = 90 # temp simulated every EST_TEMP_CYCLES*TEST_TEMP_SLEEP

const
  confSchedFileName : string = "sched.conf"
  confTempSchedFileName : string = "temp.conf"
  confChanFileName : string = "chan.conf"
  statusTempFileName : string = "tmch"

const
  CHAN_USE_SCHED : string = "sched"
  CHAN_USE_TEMP : string = "temp"
#  DT_FORMAT_TEMP_ = "yyyy/MM/dd HH:mm:ss,"
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

const
  NO_ERROR = 0
  ERR_NO_DEVICE = 1
  ERR_ERR_CONFIG = 2
  ERR_CLAILM_IF = 3
  ERR_MODE_TEST = 4
  ERR_NO_MEM = 5

type
  startMode = enum
    modeweb, modeservice

type
  CArray[T] = UncheckedArray[T]
#  CommandsArray = array[0..MAX_COMMANDS,string]

type
  TempRequest = object
    channel : int
    nmax : int

type
  ActRequest = object
    channel : int
    nmax : int

type
  NooData = array[0..7, cuchar]
#  TempArray = array[0..MAX_CHANNEL, float]
#  TempMeasArray = array[0..MAX_TEMP_VALUES, TempMeasurementObj]
#  tmaSeq = seq[TempMeasurementObj]
  TempArray = array[1..MAX_CHANNEL, seq[TempMeasurementObj]]

type
  IntChannel = Channel[int]
#  FloatChannel = Channel[float]
  StringChannel = Channel[string]
  TempReqChannel = Channel[TempRequest]
  TempMeasChannel = Channel[TempChanMeasurement]
  ActReqChannel = Channel[ActRequest]

type
  ChanConf = object
    channel : int
    tchannel : int
    ctype : string
    cname : string

proc `$`(s: ChanConf) : string =
  result = intToStr(s.channel) & " " & intToStr(s.tchannel) & " " & s.ctype & " " & s.cname

type
  SchedEvent = object of RootObj
    dow : int
    hrs : int
    mins : int
    channel : int
    command : string

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
    temp : int

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
var chanRespTemp : StringChannel
var chanPutTemp : TempMeasChannel
var chanConfReqChanName : IntChannel
var chanConfRespChanName : StringChannel
var chanConfReqTempName : IntChannel
var chanConfRespTempName : StringChannel
var chanConfReqTempChan : IntChannel
var chanConfRespTempChan : IntChannel
var testTempCycles : int
#var seqChannelConf : seq[ChanConf]
#var totalChanConf : int

const
  Cmds = ["on","off","sw","set","bind","unbind","preset"]
#  Channels = ["cuisine","salon","chambre","bureau","chauffe eau"]

proc sendUsbCommand(command : string, chann : cuchar, level : cuchar) : int =

  const
    DEV_VID : cshort = 0x000016C0
    DEV_PID : cshort = 0x000005DF
    DEV_INTF : cint = 0
    DEV_CONFIG : cint = 1
    REQ_VAL = 0x00000300'u16
    REQ_IND = 0'u16
    COMMAND_SIZE = 8'u16
    TIMEOUT : cuint = 100

#  var ptrCmdPtr = cast[ptr cuchar] (alloc0(COMMAND_SIZE))
  var ptrCmdPtr : ptr cuchar
#  var ptrCmdArr = cast[ptr CArray[cuchar]] (ptrCmdPtr)
  var ptrCmdArr : ptr CArray[cuchar]
  var handle : ptr LibusbDeviceHandle
  var commands = initTable[string, cuchar]()
  var res : int = 0
  var ret : int = 0
  var req = 0'u8
  var usbContext : LibusbContext
  var refUsbContext = addr(usbContext)

  commands["on"]     = (cuchar)2
  commands["off"]    = (cuchar)0
  commands["sw"]     = (cuchar)4
  commands["set"]    = (cuchar)6
  commands["bind"]   = (cuchar)15
  commands["unbind"] = (cuchar)9
  commands["preset"] = (cuchar)7

  if(DEBUG>0) :
    echo `$`(getLocalTime(getTime()))," sendUsbCommand: command=",command," channel=",intToStr(int(chann))," level=",intToStr(int(level))

  res = libusbInit(addr(refUsbContext))
  libusbSetDebug(refUsbContext, (cint)LibusbLogLevel.error)
  handle = libusbOpenDeviceWithVidPid(refUsbContext, DEV_VID, DEV_PID)
  if (handle == nil) :
    libusbExit(refUsbContext)
    return ERR_NO_DEVICE
  res = libusbKernelDriverActive(handle, DEV_INTF)
  if (res > 0) :
    res = libusbDetachKernelDriver(handle, DEV_INTF)
  ret = libusbSetConfiguration(handle, DEV_CONFIG)
  if (ret < 0) :
    discard libusbAttachIKernelDriver(handle, DEV_INTF)
    libusbClose(handle)
    libusbExit(refUsbContext)
    return ERR_ERR_CONFIG
  ret = libusbClaimInterface(handle, DEV_INTF)
  if (ret < 0) :
    discard libusbAttachIKernelDriver(handle, DEV_INTF)
    libusbClose(handle)
    libusbExit(refUsbContext)
    return ERR_CLAILM_IF

  req = (uint8)LibusbEndpointDirection.hostToDevice
  req = req or (uint8)LibusbRequestType.class
  req = req or (uint8)LibusbRequestRecipient.interf

  try :
    ptrCmdPtr = cast[ptr cuchar] (alloc0(COMMAND_SIZE))

    if( not (ptrCmdPtr==nil) ) :
      ptrCmdArr = cast[ptr CArray[cuchar]] (ptrCmdPtr)
      ptrCmdArr[0] = (cuchar)0x00000030
      ptrCmdArr[1] = commands[command]
      ptrCmdArr[2] = (cuchar)0
      ptrCmdArr[4] = cast[cuchar](int(chann) - 1)
      ptrCmdArr[5] = level

      if(command == "set") :
        ptrCmdArr[2] = (cuchar)1

      if(DEBUG>2) :
        echo "ptrCmdArr="
        for i in 0..7 :
          echo "\t",ptrCmdArr[i]

      ret = libusbControlTransfer(handle,
                                  req,
                                  LibusbStandardRequest.setConfiguration,
                                  REQ_VAL, REQ_IND,
                                  ptrCmdPtr, COMMAND_SIZE,
                                  TIMEOUT)

      discard libusbAttachIKernelDriver(handle, DEV_INTF)
      libusbClose(handle)
      libusbExit(refUsbContext)
      dealloc(ptrCmdPtr)
      if (ret == (int)COMMAND_SIZE) :
        return NO_ERROR
      else :
        return ret
    else :
      discard libusbAttachIKernelDriver(handle, DEV_INTF)
      libusbClose(handle)
      libusbExit(refUsbContext)
      return ERR_NO_MEM
  except :
    discard libusbAttachIKernelDriver(handle, DEV_INTF)
    libusbClose(handle)
    libusbExit(refUsbContext)
    dealloc(ptrCmdPtr)
    return ERR_NO_MEM

proc getUsbData(nd : var NooData) : int =

  const
    DEV_VID : cshort = 5824
    DEV_PID : cshort = 1500
    DEV_INTF : cint = 0
    DEV_CONFIG : cint = 1
    REQ_VAL = 0x00000300'u16
    REQ_IND = 0'u16
    TIMEOUT : cuint = 100

#  var ptrBufPtr = cast[ptr cuchar] (alloc0(BUF_SIZE))
  var ptrBufPtr : ptr cuchar
#  var ptrBufArr = cast[ptr CArray[cuchar]] (ptrBufPtr)
  var ptrBufArr : ptr CArray[cuchar]
  var handle : ptr LibusbDeviceHandle
  var res : int = 0
  var ret : int = 0
  var req = 0'u8
  var usbContext : LibusbContext
  var refUsbContext = addr(usbContext)

  res = libusbInit(addr(refUsbContext))
  libusbSetDebug(refUsbContext, (cint)LibusbLogLevel.error)
  handle = libusbOpenDeviceWithVidPid(refUsbContext, DEV_VID, DEV_PID)
  if (handle == nil) :
    libusbExit(refUsbContext)
    return ERR_NO_DEVICE
  res = libusbKernelDriverActive(handle, DEV_INTF)
  if (res > 0) :
    res = libusbDetachKernelDriver(handle, DEV_INTF)
  ret = libusbSetConfiguration(handle, DEV_CONFIG)
  if (ret < 0) :
    discard libusbAttachIKernelDriver(handle, DEV_INTF);
    libusbClose(handle)
    libusbExit(refUsbContext)
    return ERR_ERR_CONFIG
  ret = libusbClaimInterface(handle, DEV_INTF)
  if (ret < 0) :
    discard libusbAttachIKernelDriver(handle, DEV_INTF);
    libusbClose(handle)
    libusbExit(refUsbContext)
    return ERR_CLAILM_IF
  req = (uint8)LibusbEndpointDirection.deviceToHost
  req = req or (uint8)LibusbRequestType.class
  req = req or (uint8)LibusbRequestRecipient.interf
  try :
    ptrBufPtr = cast[ptr cuchar] (alloc0(BUF_SIZE))
    if( not (ptrBufPtr==nil) ) :
      ret = libusbControlTransfer(handle,
                                  req,
                                  LibusbStandardRequest.setConfiguration,
                                  REQ_VAL, REQ_IND,
                                  ptrBufPtr, BUF_SIZE,
                                  TIMEOUT)

      discard libusbAttachIKernelDriver(handle, DEV_INTF)
      libusbClose(handle)
      libusbExit(refUsbContext)
      if (ret == (int)BUF_SIZE) :
        ptrBufArr = cast[ptr CArray[cuchar]] (ptrBufPtr)
        for i in 0..<(int)BUF_SIZE :
          nd[i] = ptrBufArr[i]
        dealloc(ptrBufPtr)
        return NO_ERROR
      else :
        dealloc(ptrBufPtr)
        return ret
    else :
      discard libusbAttachIKernelDriver(handle, DEV_INTF)
      libusbClose(handle)
      libusbExit(refUsbContext)
      return ERR_NO_MEM
  except :
    discard libusbAttachIKernelDriver(handle, DEV_INTF)
    libusbClose(handle)
    libusbExit(refUsbContext)
    return ERR_NO_MEM

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

proc saveTempArr(tm : seq[TempMeasurementObj], fileName : string) : int =
  if(not tm.high>0) : return 0
  var ffff : File
  var strLine : string
  var tWrite = 0
  var ti : DateTime

  try :
    ffff = open(fileName, fmReadWrite, bufSize=8000)
  except :
    return 0
#
#  let DT_FORMAT = "yyyy/MM/dd HH:mm:ss,"
#                  2015/10/31 10:01:30,20.1\n
#
#  TempMeasurementObj = object
#    mTime : Time
#    mTemp : float
  for i in tm.low..tm.high :
    try :
      ti=getLocalTime(tm[i].mTime)
      strLine=ti.format(DT_FORMAT_TEMP)
      strLine &= ","
      strLine &= formatFloat(tm[i].mTemp, ffDecimal, 1)
      if(DEBUG>2) :
        echo "trying to write temp measurements to file ",fileName," : ",i," ",strLine
      writeLine(ffff,strLine)
#      writeLn(ffff,strLine) # deprecated
      inc tWrite
    except :
      break
  ffff.close()
  return tWrite

proc loadTempArr(tm : var seq[TempMeasurementObj], fileName : string) : int =
  if(tm.high>0) : return 0
  var ffff : File
  try :
    ffff = open(fileName, bufSize=8000)
  except :
    return 0
  var readLine = TaintedString(newStringOfCap(120))
  var line : seq[string]
#  var format : string
  var tRead = 0
  var dt : DateTime
  var ft : float

  dt=getLocalTime(getTime())  # suppress compile warning
#  format=DT_FORMAT_TEMP
#  format=DT_FORMAT_TEMP_.split(",")[0]
#  if(format.len()<(DT_FORMAT_TEMP_.len()-1)) : return 0
#
#  let DT_FORMAT = "yyyy/MM/dd HH:mm:ss,"
#                  2015/10/31 10:01:30,20.1\n
#
  while ffff.readLine(readLine) :
    line=readLine.split(",")
    try :
      dt=line[0].parse(DT_FORMAT_TEMP)
      ft=line[1].parseFloat()
    except :
      return 0
    tm.add((new TempMeasurementObj)[])
    tm[tm.high].mTime = toTime(dt)
    tm[tm.high].mTemp = ft
    inc tRead
  return tRead

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
  var tArr : TempArray
  var strDTime : string
  var strTemp : string
  var strResp : string = ""
  var boundSeq : int
  var sAct : seq[ActionObj]
  var jsonResp : JsonNode
  var dtResp : DateTime
  var unixDT : int64
#  var jsonAct : JsonNode
#  let DT_FORMAT = "yyyy/MM/dd HH:mm:ss,"
  var refTM : TempMeasurement
#              2015/10/31 10:01:30,20.1,25.5\n
#  var mTemp : TempArray
#  tmaSeq = seq[TempMeasurementObj]
#  TempArray = array[1..MAX_CHANNEL, ref tmaSeq]
#  TempMeasurementObj = object
#    mTime : Time
#    mTemp : float
  var dti: tuple[dataAvailable: bool, msg: TempRequest]
  var dai: tuple[dataAvailable: bool, msg: ActRequest]
  var dtpi: tuple[dataAvailable: bool, msg: TempChanMeasurement]

#  for i in mTemp.low..mTemp.high :
#    mTemp[i]=NO_TEMP
  if(TEST>0) : 
    randomize()
    testTempCycles = 0
  for i in 1..MAX_TEMP_CHANNEL :
    tArr[i] = newSeq[TempMeasurementObj]()
    res = nooDbGetTemper(i, tArr[i], MAX_TEMP_MEASUREMENTS-1)
#    res=loadTempArr(tArr[i], statusTempFileName&intToStr(i))
    if(DEBUG>0) :
      echo "Load data for channel ", i, " nooDbGetTemper: ", res
      echo "Temperature data loaded for the period from ", 
        format(getLocalTime(tArr[i][tArr[i].low].mTime),DT_FORMAT_TEMP), " to ", 
        format(getLocalTime(tArr[i][tArr[i].high].mTime),DT_FORMAT_TEMP)
      sleep(1000)

  while(true) :
    if(TEST>0) : sleep(TEST_TEMP_SLEEP)
    else : sleep(300)
    if(DEBUG>3) :
      echo "Messages in chanReqTemp: ", chanReqTemp.peek()
      echo "Messages in chanReqAct: ", chanReqAct.peek()    
      echo "Messages in chanPutTemp: ", chanPutTemp.peek()    
# ********* check temp data put request from other threads and put temp data to DB and to array **********
    dtpi=chanPutTemp.tryRecv()
    if(dtpi.dataAvailable) :
      if(DEBUG>1) :
        echo "temp received put request for temp on channel: ",dtpi.msg[].channel
        echo "temp received: ",dtpi.msg[].mTemp
      channel=dtpi.msg[].channel
      if( (tArr[channel].high-tArr[channel].low)>MAX_TEMP_MEASUREMENTS) :
        if(DEBUG>1) :
          echo "temp is removing old temp measurement: ",tArr[channel].low
        tArr[channel].delete(tArr[channel].low,tArr[channel].low)
      refTM = new TempMeasurementObj
      refTM.mTime = dtpi.msg[].mTime
      refTM.mTemp = dtpi.msg[].mTemp
      tArr[channel].add( refTM[] )
      boolres=nooDbPutTemper(channel, refTM[])
#            res=saveTempArr(tArr[channel], statusTempFileName & intToStr(channel))
      if(DEBUG>1) :
        echo "wrote temp status: ", boolres

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
        if( tArr[channel].len() > 0) :
          if(DEBUG>1) :
            echo "tArr bounds: ",tArr[channel].low,"..",tArr[channel].high
          if( nmax>(tArr[channel].high-tArr[channel].low) ) : boundSeq=tArr[channel].low
          else : boundSeq=tArr[channel].high-nmax+1
          if(DEBUG>1) :
            echo "temp is answering with bounds: ",boundSeq,"..",tArr[channel].high
          for i in boundSeq..tArr[channel].high :
#              2015/10/01 10:01:30,20.1,25.5\n
            try :
              strDTime=format(getLocalTime(tArr[channel][i].mTime),DT_FORMAT_TEMP)
            except :
              if(DEBUG>0) :
                echo "error formatting mTime"
              strDTime=""
            fTemp=tArr[channel][i].mTemp
            if( (fTemp==NO_TEMP) or (fTemp==ERR_TEMP) ) : strTemp=""
            else : strTemp=formatFloat(fTemp, ffDecimal, 1)
            if( (strDTime.len>1) and (strTemp.len>1) ) : strResp &= (strDTime & "," & strTemp & "\n")
        else :
          strResp=""
        chanRespTemp.send(strResp)
      else :
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
#            try :
#              strDTime=format(getLocalTime(act.aTime),DT_FORMAT_ACT)
#            except :
#              if(DEBUG>0) :
#                echo "error formatting aTime"
#              strDTime=""
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
            if( (tArr[channel].high-tArr[channel].low)>MAX_TEMP_MEASUREMENTS) :
              if(DEBUG>1) :
                echo "temp is removing old temp measurement: ",tArr[channel].low
              tArr[channel].delete(tArr[channel].low,tArr[channel].low)
            refTM.mTime=getTime()
            refTM.mTemp=fTemp
            tArr[channel].add( refTM[] )
            boolres=nooDbPutTemper(channel, refTM[])
#            res=saveTempArr(tArr[channel], statusTempFileName & intToStr(channel))
            if(DEBUG>1) :
              echo "wrote temp status: ", boolres
          else :
            if(DEBUG>0) :
              echo "Cannot allocate memory: ",tArr[channel].high
              echo "Probably you need to decrease MAX_TEMP_MEASUREMENTS (currently set to ",MAX_TEMP_MEASUREMENTS,")"
      of ERR_NO_DEVICE :
        if(DEBUG>1) : echo "Cannot find nooLite device"
      of ERR_ERR_CONFIG :
        if(DEBUG>1) : echo "Cannot set configuration"
      of ERR_CLAILM_IF :
        if(DEBUG>1) : echo "Cannot claim interface"
      of ERR_MODE_TEST :
        inc testTempCycles
        if(testTempCycles<TEST_TEMP_CYCLES) :
          continue
        if(DEBUG>1) : echo "Working in test mode"
        testTempCycles = 0
        for i in 1..MAX_TEMP_CHANNEL :
          channel=i
#          echo intToStr(channel)
          fTemp=TEST_TEMP+(rand(TEST_TEMP_VAR)-TEST_TEMP_VAR/2)
          if(DEBUG>1) :
            echo `$`(getLocalTime(getTime()))," temp simulated new data: channel=",channel," temp=",formatFloat(fTemp,ffDecimal,1)
          refTM = new TempMeasurementObj
          if(refTM != nil) :
            if( (tArr[channel].high-tArr[channel].low)>MAX_TEMP_MEASUREMENTS) :
              if(DEBUG>1) :
                echo "temp is removing old temp measurement: ",tArr[channel].low
              tArr[channel].delete(tArr[channel].low,tArr[channel].low)
            refTM.mTime=getTime()
            refTM.mTemp=fTemp
            tArr[channel].add( refTM[] )
            boolres=nooDbPutTemper(channel, refTM[])
#            res=saveTempArr(tArr[channel], statusTempFileName & intToStr(channel))
            if(DEBUG>1) :
              echo "wrote temp status: ", boolres
          else :
            if(DEBUG>0) :
              echo "Cannot allocate memory: ",tArr[channel].high
              echo "Probably you need to decrease MAX_TEMP_MEASUREMENTS (currently set to ",MAX_TEMP_MEASUREMENTS,")"

      else :
        if(DEBUG>1) : echo "temp got error: getUsbData result - ",res

proc getChannelConf(scc : var seq[ChanConf]) : int =
  var i : int = 0
  if(scc.high>0) : return 0

  var ffff = open(confChanFileName, bufSize=8000)
  var res = TaintedString(newStringOfCap(120))

#  for x in lines(confFileName) :
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
#      var arrChannelConf = newSeq[ChanConf]()
#      var totalChanConf : int

#      totalChanConf = getChannelConf(arrChannelConf)
#  ChanConf = object
#    channel : int
#    tchannel : int
#    ctype : string
#    cname : string

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
#        chanConfReqTempName.send(reqChannel)
#        if(DEBUG>2) :
#          echo "requested temp channel name for: ",reqChannel
#        strChannelName = chanConfRespTempName.recv()
#        if(DEBUG>2) :
#          echo "received: ",strChannelName
#        if(strChannelName.len<1) :
#          strChannelName = intToStr(tReq.channel)
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
#      var strChannel : string
      var res : int
      var tReq : TempRequest
#      var arrChannelConf = newSeq[ChanConf]()
#      var totalChanConf : int
      var strChannelName : string

#      totalChanConf = getChannelConf(arrChannelConf)
#  ChanConf = object
#    channel : int
#    tchannel : int
#    ctype : string
#    cname : string

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
#  chanConfReqChanName.open()
#  chanConfRespChanName.open()
#  chanConfReqTempName.open()
#  chanConfRespTempName.open()
#  chanConfReqTempChan.open()
#  chanConfRespTempChan.open()
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

proc getTempSchedule(sct : var seq[SchedTempEvent]) : int =
  var i : int = 0
  if(sct.high>0) : return 0

  var ffff = open(confTempSchedFileName, bufSize=8000)
  var res = TaintedString(newStringOfCap(120))

#  for x in lines(confFileName) :
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
  var arrSchedEvt = newSeq[SchedEvent]()
  var totalEvt : int
  var arrSchedTimeInfoEvent = newSeq[TimeInfoEvent]()
  var arrSchedTempEvt = newSeq[SchedTempEvent]()
  var totalTempEvt : int
  var arrSchedTimeInfoTempEvent = newSeq[TimeInfoTempEvent]()
  var arrChannelConf = newSeq[ChanConf]()
  var totalChanConf : int
  var sendCmdTime : array[1..MAX_CHANNEL,Time]
  var lastCommand : array[1..MAX_CHANNEL,string]
  var lastCmdSend : array[1..MAX_CHANNEL,int]
  var chanUseSched : array[1..MAX_CHANNEL,bool]
  var chanUseTemp : array[1..MAX_CHANNEL,bool]
  var lastTempEvtIndex : array[1..MAX_CHANNEL,int]
  var dayOfWeek : int
  var now : DateTime
  var evt : DateTime
  var tReq : TempRequest
  var respTemp : string
  var seqRespTemp : seq[string]
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
  var channel,tchannel : int
  var cmd : string
  var act : ActionObj
  var boolRes : bool
  var nowWeekDay = int(ord(getLocalTime(getTime()).weekday))
  inc(nowWeekDay)
  sleep(1000)
  totalEvt = getSchedule(arrSchedEvt)
  totalTempEvt = getTempSchedule(arrSchedTempEvt)
  totalChanConf = getChannelConf(arrChannelConf)
  if(DEBUG>0) :
    echo "sched got sched events: ",(totalEvt+1)
    echo "sched got temp events: ",(totalTempEvt+1)
    echo "sched got chanconf records: ",(totalChanConf+1)
  if(DEBUG>2) :
    echo "Sched events:"
    for j in 0..totalEvt :
      echo "\t",`$`(arrSchedEvt[j])
    echo "Temp events:"
    for j in 0..totalTempEvt :
      echo "\t",`$`(arrSchedTempEvt[j])
    echo "Chanconf records:"
    for j in 0..totalChanConf :
      echo "\t",`$`(arrChannelConf[j])
    echo "Current weekday: ",nowWeekDay
  for j in 1..MAX_CHANNEL :
    chanUseSched[j] = false
    chanUseTemp[j] = false
    lastCommand[j] = ""
    sendCmdTime[j] = initTime(0, 0)
    lastCmdSend[j] = 0
  for j in 0..totalChanConf :
#  ChanConf = object
#    channel : int
#    tchannel : int
#    ctype : string
#    cname : string
#  CHAN_USE_SCHED : string = "sched"
#  CHAN_USE_TEMP : string = "temp"
#  var chanUseSched : array[1..MAX_CHANNEL,bool]
#  var chanUseTemp : array[1..MAX_CHANNEL,bool]
    case arrChannelConf[j].ctype :
      of CHAN_USE_SCHED :
        chanUseSched[arrChannelConf[j].channel] = true
        chanUseTemp[arrChannelConf[j].channel] = false
        chanSchedPresent = true
        if(DEBUG>1) :
          echo "channel ",j," using sched"
        continue
      of CHAN_USE_TEMP :
        chanUseSched[arrChannelConf[j].channel] = false
        chanUseTemp[arrChannelConf[j].channel] = true
        chanTempPresent = true
        if(DEBUG>1) :
          echo "channel ",j," using temp"
        continue
      else:
        continue
  while (true) :
    now = getLocalTime(getTime())
    if(DEBUG_MEM>0) :
      echo "Enter TotalMem: ",getTotalMem()
      echo "Enter FreeMem: ",getFreeMem()
      echo "Enter OccupiedMem: ",getOccupiedMem()
    if(chanSchedPresent) :
# processing sched events
      for i in 0..totalEvt :
        if(DEBUG>2) :
          echo "sched is processing sched event numero: ",i
        dayOfWeek=arrSchedEvt[i].dow
# filter on weekdays
        if(not isWeekDayNow(dayOfWeek)) : continue
        evt = getLocalTime(getTime())
        evt.second=0
        evt.minute=arrSchedEvt[i].mins
        evt.hour=arrSchedEvt[i].hrs
        if(DEBUG>2) :
          echo "sched got event object: ",$evt
# filter on time
        diff=toTime(now)-toTime(evt)
        if(DEBUG>2) :
          echo "sched got diff: ", diff.inSeconds
        if( (diff.inSeconds>0) and (diff.inSeconds<maxSecSched) ) :
          arrSchedTimeInfoEvent.add(newTimeInfoEvent(arrSchedEvt[i].channel,arrSchedEvt[i].command))
          j=arrSchedTimeInfoEvent.high
          if(DEBUG>2) :
            echo "sched added event: ",j
          arrSchedTimeInfoEvent[j].second = 0
          arrSchedTimeInfoEvent[j].hour = arrSchedEvt[i].hrs
          arrSchedTimeInfoEvent[j].minute = arrSchedEvt[i].mins
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
          if( chanUseSched[arrSchedTimeInfoEvent[jj].channel] and not
                  ( (lastCommand[arrSchedTimeInfoEvent[jj].channel]==arrSchedTimeInfoEvent[jj].command) and
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
            for jj in 0..totalChanConf :
              if(arrChannelConf[jj].channel==channel) :
                tchannel=arrChannelConf[jj].tchannel
            if(DEBUG>2) :
              echo "sched resolved temp channel: ",tchannel," for channel: ",channel
            if(DEBUG>1) :
              echo "sched is trying to get last temp for temp channel:",tchannel
            tReq.channel = tchannel
            tReq.nmax = 1
            chanReqTemp.send(tReq)
            if(DEBUG>2) :
              echo "requested channel: ",tReq.channel," nmax: ",tReq.nmax
            respTemp = chanRespTemp.recv()
            if(respTemp.len()>1) :
              respTemp.removeSuffix()
            if(DEBUG>1) :
              echo "received temp: ",respTemp," for channel ",channel
#  yyyy/MM/dd HH:mm:ss,TT.t\n
            seqRespTemp=respTemp.split(',')
            if(seqRespTemp.len()>1) :
              try :
                tempTimeInfo=seqRespTemp[0].parse(DT_FORMAT_ACT)
                tempTime=tempTimeInfo.toTime()
                if(DEBUG>1) :
                  echo "tempTime: ",$tempTime
              except :
                tempTime=initTime(0, 0)
#              seqRespTemp[1].removeSuffix()
              try :
                fTemp=seqRespTemp[1].parseFloat()
                if(DEBUG>1) :
                  echo "fTemp: ",formatFloat(fTemp,ffDecimal,1)
              except :
                fTemp=ERR_TEMP
            else :
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
                  echo "sched is sending temp command \'",cmd,"\' to channel:",j," at temp:",seqRespTemp[1]
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
      arrSchedTimeInfoTempEvent.delete(arrSchedTimeInfoTempEvent.low,arrSchedTimeInfoTempEvent.high)
      if(DEBUG_MEM>0) :
        echo "Finished Temp Events TotalMem: ",getTotalMem()
        echo "Finished Temp FreeMem: ",getFreeMem()
        echo "Finished Temp OccupiedMem: ",getOccupiedMem()
    sleep(SLEEP_ON_SCHED)

proc conf() {.thread.} =
#  var seqChannelConf : seq[ChanConf]
  var seqChannelConf = newSeq[ChanConf]()
  var totalChanConf : int
  var dtint: tuple[dataAvailable: bool, msg: int]
  var channel : int
  var channelName : string
  var tchannel : int

  if(DEBUG>1) :
    echo "nooconf is trying to read channels config"
  totalChanConf = getChannelConf(seqChannelConf)
  if(DEBUG>1) :
    echo "channels config read: " & intToStr(totalChanConf)
  while(true) :
    sleep(200)
# ********* check conf data request from other threads and send data **********
#  chanConfReqChanName.open()
#  chanConfRespChanName.open()
#  chanConfReqTempName.open()
#  chanConfRespTempName.open()
#  chanConfReqTempChan.open()
#  chanConfRespTempChan.open()
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
  chanConfReqChanName.open()
  chanConfRespChanName.open()
  chanConfReqTempName.open()
  chanConfRespTempName.open()
  chanConfReqTempChan.open()
  chanConfRespTempChan.open()
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
