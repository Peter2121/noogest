import db,math,strutils,times
import nootypes

const
  DB_DEBUG : int = 5 # from 0 (no debug messages at all) to 5 (all debug messages sent to stdout)
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
"""

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

proc nooDbPutTemper*(channel : int, tm : TempMeasurement) : bool = 
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
    
proc nooDbPutTemper*(channel : int, stm : seq[TempMeasurement]) : bool =
  var nooDb : DbConnId
  var res : bool = true
  var res1 : bool
  for tm in stm :
    res1 = nooDbPutTemper(channel, tm)
    res = res and res1
  return res

proc nooDbGetLastTemper*(channel : int, tm : var TempMeasurement) : bool =
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

proc nooDbGetTemper*(channel : int, stm : var seq[TempMeasurement], nmes : int) : int =
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
      stm.add((new TempMeasurement)[])
      stm[stm.high].mTime = fromUnix((int64)curDtm)
      stm[stm.high].mTemp = curTemper
      inc tRead
  except :
    nooDb.close()
    return tRead
  nooDb.close()
  return tRead

proc nooDbGetTemper*(channel : int, stm : var seq[TempMeasurement], nmes : int, last : int) : int =
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
      stm.add((new TempMeasurement)[])
      stm[stm.high].mTime = fromUnix((int64)curDtm)
      stm[stm.high].mTemp = curTemper
      inc tRead
  except :
    nooDb.close()
    return tRead
  nooDb.close()
  return tRead

proc nooDbImportTemp*(channel : int, fileName : string) : int =
  var nooDb : DbConnId
  var ffff : File
  var tm : TempMeasurement
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
