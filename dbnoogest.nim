import db,math,strutils,times
import nootypes

var theDb : DbConnId

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
"""

proc nooDbInit*() =
  var sqlInitDb : SqlQuery
  theDb = initDb(DB_KIND)
  theDb.open(DB_FILE, "", "", "")
  for strInitDb in DB_SCHEMA.split(';') :
    if(DB_DEBUG>2) :
      echo "Executing SQL query: ", strInitDb
#      echo "Length: ", strInitDb.len()
    if(strInitDb.len() < 3) :
      continue
    sqlInitDb = sql(strInitDb)
    theDb.exec(sqlInitDb)
  theDb.close()

proc nooDbPutTemper*(channel : int, tm : TempMeasurement) : bool = 
  theDb = initDb(DB_KIND)
  theDb.open(DB_FILE, "", "", "")
  let id = theDb.tryInsertId(sql"INSERT INTO temper (chan,dtm,temper) VALUES (?,?,?)",
             channel, toUnix(tm.mTime), tm.mTemp)
  if(DB_DEBUG>2) :
    echo "Temperature inserted: ", id
  theDb.close()
  if(id != -1) :
    return true
  else :
    return false
    
proc nooDbPutTemper*(channel : int, stm : seq[TempMeasurement]) : bool =
  var res : bool = true
  var res1 : bool
  for tm in stm :
    res1 = nooDbPutTemper(channel, tm)
    res = res and res1
  return res
  
proc nooDbImportTemp*(channel : int, fileName : string) : int =
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



