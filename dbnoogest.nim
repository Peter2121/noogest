import db,math,strutils,times
import nootypes,nooconst

const
  DB_DEBUG : int = 0 # from 0 (no debug messages at all) to 5 (all debug messages sent to stdout)
  DT_FORMAT = "yyyy/MM/dd HH:mm:ss,"

const
  DB_KIND : DbKind = DbKind.Sqlite
  DB_FILE : string = "noogest.db"
  DB_SCHEMA : string = """
CREATE TABLE temper
(id INTEGER PRIMARY KEY,
chan INTEGER NOT NULL,
dtm INTEGER NOT NULL,
temper FLOAT NOT NULL
);
CREATE UNIQUE INDEX idx_temper_chan_dtm 
ON temper (chan, dtm); 
CREATE INDEX idx_temper_dtm 
ON temper (dtm);
CREATE TABLE action
(id INTEGER PRIMARY KEY,
chan INTEGER NOT NULL,
dtm INTEGER NOT NULL,
action VARCHAR(15) NOT NULL,
actres INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_action_chan_dtm
ON temper (chan, dtm);
CREATE TABLE chan
(id INTEGER PRIMARY KEY,
channel INTEGER NOT NULL,
temp_channel INTEGER NOT NULL,
type_channel VARCHAR(7) NOT NULL,
name_channel VARCHAR(32) NOT NULL
);
"""

# No nooDbImportConf as there are profiles in chan table, one need to import data manually

proc nooDbInit*() =
  var sqlInitDb : SqlQuery
  var nooDb : DbConnId
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  for strInitDb in DB_SCHEMA.split(';') :
    if(DB_DEBUG>2) :
      echo "Executing SQL query: ", strInitDb
#      echo "Length: ", strInitDb.len()
    if(strInitDb.len() < 3) :
      continue
    sqlInitDb = sql(strInitDb)
    nooDb.exec(sqlInitDb)
  nooDb.close()

proc nooDbPutTemper*(channel : int, tm : TempMeasurementObj) : bool = 
  var nooDb : DbConnId
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  if(DB_DEBUG>2) :
    echo "Trying to insert temperature ", tm.mTemp, " for channel ", channel  
  let id = nooDb.tryInsertId(sql"INSERT INTO temper (chan,dtm,temper) VALUES (?,?,?)",
             channel, toUnix(tm.mTime), tm.mTemp)
  if(DB_DEBUG>2) :
    echo "Temperature inserted: ", id
  nooDb.close()
  if(id != -1) :
    return true
  else :
    return false
    
proc nooDbPutTemper*(channel : int, stm : seq[TempMeasurementObj]) : bool =
  var nooDb : DbConnId
  var res : bool = true
  var res1 : bool
  for tm in stm :
    res1 = nooDbPutTemper(channel, tm)
    res = res and res1
  return res

proc nooDbGetLastTemper*(channel : int, tm : var TempMeasurementObj) : bool =
  var nooDb : DbConnId
  var strResult : string
  var lastDtm : int
  var lastTemper : float
#  if(tm == nil) : return false
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    strResult = nooDb.getValue(sql"SELECT MAX(dtm) FROM temper WHERE chan=?", channel)
    lastDtm = strResult.parseInt()
    strResult = nooDb.getValue(sql"SELECT temper FROM temper WHERE dtm=?", lastDtm)
    lastTemper = strResult.parseFloat()
    tm.mTime = fromUnix((int64)lastDtm)
    tm.mTemp = lastTemper
  except :
    nooDb.close()
    return false
  nooDb.close()
  return true

proc nooDbGetTemper*(channel : int, stm : var seq[TempMeasurementObj], nmes : int) : int =
  var nooDb : DbConnId
  var strResult : string
  var curDtm : int
  var curTemper : float
  var tRead : int = 0
  var curRow : Row
#  if(stm == nil) : return 0
  if(stm.high>0) : return 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    for curRow in nooDb.fastRows(sql"SELECT dtm,temper FROM (SELECT dtm,temper FROM temper WHERE chan=? ORDER BY dtm DESC LIMIT ?) ORDER BY dtm", channel, nmes) :
      curDtm = curRow[0].parseInt()
      curTemper = curRow[1].parseFloat()
      stm.add((new TempMeasurementObj)[])
      stm[stm.high].mTime = fromUnix((int64)curDtm)
      stm[stm.high].mTemp = curTemper
      inc tRead
  except :
    discard
  nooDb.close()
  return tRead

proc nooDbGetTemper*(channel : int, stm : var seq[TempMeasurementObj], nmes : int, last : int) : int =
  var nooDb : DbConnId
  var strResult : string
  var curDtm : int
  var curTemper : float
  var tRead : int = 0
  var curRow : Row
#  if(stm == nil) : return 0
  if(stm.high>0) : return 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    for curRow in nooDb.fastRows(sql"SELECT dtm,temper FROM (SELECT dtm,temper FROM temper WHERE chan=? AND (strftime('%s','now')-dtm)<? ORDER BY dtm DESC LIMIT ?) ORDER BY dtm", channel, last, nmes) :
      curDtm = curRow[0].parseInt()
      curTemper = curRow[1].parseFloat()
      stm.add((new TempMeasurementObj)[])
      stm[stm.high].mTime = fromUnix((int64)curDtm)
      stm[stm.high].mTemp = curTemper
      inc tRead
  except :
    discard
  nooDb.close()
  return tRead

proc nooDbImportTemp*(channel : int, fileName : string) : int =
  var nooDb : DbConnId
  var ffff : File
  var tm : TempMeasurementObj
  try :
    ffff = open(fileName, bufSize=8000)
  except :
    return 0
  var readLine = TaintedString(newStringOfCap(120))
  var line : seq[string]
  var format : string
  var tRead = 0
  var dt : DateTime
  var ft : float
  var res : bool

  dt=getLocalTime(getTime())  # suppress compile warning
  format=DT_FORMAT.split(",")[0]
  if(format.len()<(DT_FORMAT.len()-1)) : 
    return 0
#
#  let DT_FORMAT = "yyyy/MM/dd HH:mm:ss,"
#                  2015/10/31 10:01:30,20.1\n
#
  while ffff.readLine(readLine) :
    line=readLine.split(",")
    try :
      dt=line[0].parse(format)
      ft=line[1].parseFloat()
    except :
      return tRead
    tm.mTime = toTime(dt)
    tm.mTemp = ft
    res = nooDbPutTemper(channel, tm)
    if(res) :
      inc tRead
  return tRead

proc nooDbPutAction*(channel : int, act : ActionObj) : bool = 
  var nooDb : DbConnId
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  if(DB_DEBUG>2) :
    echo "Trying to insert action ", act.aAct, " for channel ", channel  
  let id = nooDb.tryInsertId(sql"INSERT INTO action (chan,dtm,action,actres) VALUES (?,?,?,?)",
             channel, toUnix(act.aTime), act.aAct, act.aRes)
  if(DB_DEBUG>2) :
    echo "Action inserted: ", id
  nooDb.close()
  if(id != -1) :
    return true
  else :
    return false

proc nooDbGetAction*(channel : int, sact : var seq[ActionObj], nact : int) : int =
  var nooDb : DbConnId
  var strResult : string
  var curDtm : int
  var curActRes : int
  var tRead : int = 0
  var curRow : Row
#  if(stm == nil) : return 0
  if(sact.high>0) : return 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    for curRow in nooDb.fastRows(sql"SELECT dtm,action,actres FROM (SELECT dtm,action,actres FROM action WHERE chan=? ORDER BY dtm DESC LIMIT ?) ORDER BY dtm", channel, nact) :
      curDtm = curRow[0].parseInt()
      curActRes = curRow[2].parseInt()
      sact.add((new ActionObj)[])
      sact[sact.high].aTime = fromUnix((int64)curDtm)
      sact[sact.high].aAct = curRow[1]
      sact[sact.high].aRes = curActRes
      inc tRead
  except :
    discard
  nooDb.close()
  return tRead

proc nooDbGetAction*(channel : int, sact : var seq[ActionObj], nact : int, last : int) : int =
  var nooDb : DbConnId
  var strResult : string
  var curDtm : int
  var curActRes : int
  var tRead : int = 0
  var curRow : Row
#  if(stm == nil) : return 0
  if(sact.high>0) : return 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    for curRow in nooDb.fastRows(sql"SELECT dtm,action,actres FROM (SELECT dtm,action,actres FROM action WHERE chan=? AND (strftime('%s','now')-dtm)<? ORDER BY dtm DESC LIMIT ?) ORDER BY dtm", channel, last, nact) :
      curDtm = curRow[0].parseInt()
      curActRes = curRow[2].parseInt()
      sact.add((new ActionObj)[])
      sact[sact.high].aTime = fromUnix((int64)curDtm)
      sact[sact.high].aAct = curRow[1]
      sact[sact.high].aRes = curActRes
      inc tRead
  except :
    discard
  nooDb.close()
  return tRead

proc nooDbGetChanName*(channel : int) : string =
  var nooDb : DbConnId
  var chanName : string = ""
  if(channel == 0) :
    return chanName
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    chanName = nooDb.getValue(sql"SELECT name_channel FROM chan WHERE channel=?", channel)
  except :
    discard
  nooDb.close()
  return chanName

proc nooDbGetTempChanName*(tchannel : int) : string =
  var nooDb : DbConnId
  var chanName : string = ""
  if(tchannel == 0) :
    return chanName
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    chanName = nooDb.getValue(sql"SELECT name_channel FROM chan WHERE temp_channel=?", tchannel)
  except :
    discard
  nooDb.close()
  return chanName

proc nooDbGetTempChanNumber*(channel : int) : int =
  var nooDb : DbConnId
  var chanNumber : int = 0
  if(channel == 0) :
    return chanNumber
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    chanNumber = nooDb.getValue(sql"SELECT temp_channel FROM chan WHERE channel=?", channel).parseInt()
  except :
    discard
  nooDb.close()
  return chanNumber
  
proc nooDbGetChanNumber*(tchannel : int) : int =
  var nooDb : DbConnId
  var chanNumber : int = 0
  if(tchannel == 0) :
    return chanNumber
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    chanNumber = nooDb.getValue(sql"SELECT channel FROM chan WHERE temp_channel=?", tchannel).parseInt()
  except :
    discard
  nooDb.close()
  return chanNumber

#  ChanConf = object
#    channel : int
#    tchannel : int
#    profile : int
#    ctype : string
#    cname : string
#[
proc nooDbGetChanConf*(scc : var seq[ChanConf]) : int =
  var nooDb : DbConnId
  var strResult : string
  var curChan : int
  var curTempChan : int
  var curProfile : int
  var curTypeChan : string
  var curNameChan : string
  var tRead : int = 0
  var curRow : Row
  if(scc.high>0) : return 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    for curRow in nooDb.fastRows(sql"SELECT channel,temp_channel,id_profile,type_channel,name_channel FROM chan ORDER BY channel") :
      curChan = curRow[0].parseInt()
      curTempChan = curRow[1].parseInt()
      curProfile = curRow[2].parseInt()
      curTypeChan = curRow[3]
      curNameChan = curRow[4]
      scc.add((new ChanConf)[])
      scc[scc.high].channel = curChan
      scc[scc.high].tchannel = curTempChan
      scc[scc.high].profile = curProfile
      scc[scc.high].ctype = curTypeChan
      scc[scc.high].cname = curNameChan
      inc tRead
  except :
    nooDb.close()
    return tRead
  nooDb.close()
  return tRead
]#

proc nooDbIsSchedPresent*(dow : int) : bool =
  var nooDb : DbConnId
  var numSchedProf : int = 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    numSchedProf = nooDb.getValue(sql"SELECT COUNT(id_chan) FROM csprof WHERE dow=?", dow).parseInt()
  except :
    discard
  nooDb.close()
  if(numSchedProf>0) :
    return true
  else :
    return false  

proc nooDbIsSchedPresent*() : bool =
  let nowWeekDay = getLocalTime(getTime()).weekday
  let nowDow = ord(nowWeekDay)+1
  return nooDbIsSchedPresent(nowDow)

proc nooDbIsTempPresent*(dow : int) : bool =
  var nooDb : DbConnId
  var numTempProf : int = 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    numTempProf = nooDb.getValue(sql"SELECT COUNT(id_chan) FROM ctprof WHERE dow=?", dow).parseInt()
  except :
    discard
  nooDb.close()
  if(numTempProf>0) :
    return true
  else :
    return false  

proc nooDbIsTempPresent*() : bool =
  let nowWeekDay = getLocalTime(getTime()).weekday
  let nowDow = ord(nowWeekDay)+1
  return nooDbIsTempPresent(nowDow)

proc nooDbGetChanConf*(channel : int, dow : int, scc : var seq[ChanConf]) : int =
  var nooDb : DbConnId
  var strResult : string
  var curChan : int
  var curTempChan : int
  var curProfile : int
  var curTypeChan : string
  var curNameChan : string
  var tRead : int = 0
  var nowDow : int = 0
  var chanType : string
  var tableNameProf : string
  var curRow : Row
  if(scc.high>0) : return 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  if(DB_DEBUG>3) :
    echo "nooDbGetChanConf requested for configuration for channel ", channel, " and day ", dow
  try :
    chanType = nooDb.getValue(sql"SELECT type_channel FROM chan WHERE channel=?", channel)
    case chanType :
      of CHAN_USE_SCHED :
        tableNameProf="csprof"
      of CHAN_USE_TEMP :
        tableNameProf="ctprof"
      else:
        nooDb.close()
        return tRead
    if(DB_DEBUG>3) :
      echo "nooDbGetChanConf will use ", tableNameProf, " table to search for the configuration"
    for curRow in nooDb.fastRows(sql"SELECT channel,temp_channel,id_profile,type_channel,name_channel FROM chan,? WHERE dow=? AND channel=? AND channel=id_chan ORDER BY channel", tableNameProf, dow, channel) :
      curChan = curRow[0].parseInt()
      curTempChan = curRow[1].parseInt()
      curProfile = curRow[2].parseInt()
      curTypeChan = curRow[3]
      curNameChan = curRow[4]
      scc.add((new ChanConf)[])
      scc[scc.high].channel = curChan
      scc[scc.high].tchannel = curTempChan
      scc[scc.high].profile = curProfile
      scc[scc.high].ctype = curTypeChan
      scc[scc.high].cname = curNameChan
      inc tRead
  except :
    discard
  nooDb.close()
  return tRead

proc nooDbGetChanConf*(channel : int, scc : var seq[ChanConf]) : int =
  var nooDb : DbConnId
  var strResult : string
  var curChan : int
  var curTempChan : int
  var curProfile : int
  var curTypeChan : string
  var curNameChan : string
  var tRead : int = 0
  var nowDow : int = 0
  var chanType : string
  var tableNameProf : string
  var curRow : Row
  if(scc.high>0) : return 0
#   this function returns the profile data for current day of week  
  let nowWeekDay = getLocalTime(getTime()).weekday
  nowDow = ord(nowWeekDay)+1
  return nooDbGetChanConf(channel, nowDow, scc)

#  SchedEvent = object of RootObj
#    hrs : int
#    mins : int
#    channel : int
#    command : string
proc nooDbGetSchedProfile*(idprof : int, ssce : var seq[SchedEvent]) : int = 
  var nooDb : DbConnId
  var strResult : string
  var curHr : int
  var curMn : int
  var curAct : string
  var tRead : int = 0
  var curRow : Row
  if(ssce.high>0) : return 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    for curRow in nooDb.fastRows(sql"SELECT hr,mn,act FROM sprof WHERE id_profile=?",idprof) :
      curHr = curRow[0].parseInt()
      curMn = curRow[1].parseInt()
      curAct = curRow[2]
      ssce.add((new SchedEvent)[])
      ssce[ssce.high].hrs = curHr
      ssce[ssce.high].mins = curMn
      ssce[ssce.high].command = curAct
      inc tRead
  except :
    discard
  nooDb.close()
  return tRead

#  SchedTempEvent = object of SchedEvent
#    dow  : int
#    temp : int
proc nooDbGetTempProfile*(idprof : int, sste : var seq[SchedTempEvent]) : int = 
  var nooDb : DbConnId
  var strResult : string
  var curHr : int
  var curMn : int
  var curAct : string
  var curTemp : float
  var tRead : int = 0
  var curRow : Row
  if(sste.high>0) : return 0
  nooDb = initDb(DB_KIND)
  nooDb.open(DB_FILE, "", "", "")
  try :
    for curRow in nooDb.fastRows(sql"SELECT hr,mn,temper,def_act FROM tprof WHERE id_profile=?",idprof) :
      curHr = curRow[0].parseInt()
      curMn = curRow[1].parseInt()
      curTemp = curRow[2].parseFloat()
      curAct = curRow[3]
      sste.add((new SchedTempEvent)[])
      sste[sste.high].hrs = curHr
      sste[sste.high].mins = curMn
      sste[sste.high].temp = curTemp
      sste[sste.high].command = curAct
      inc tRead
  except :
    discard
  nooDb.close()
  return tRead
