import times

type
  TempMeasurementObj* = object of RootObj
    mTime* : Time
    mTemp* : float

type
  TempMeasurement* = ref TempMeasurementObj
  
type
  TempChanMeasurement* = ref object of TempMeasurement
    channel* : int

type
  ActionObj* = object
    aTime* : Time
    aAct* : string
    aRes* : int
    
type
  Action* = ref ActionObj
  
type
  NooData* = array[0..7, cuchar]
  CArray*[T] = UncheckedArray[T]
  
type
  ChanConf* = object
    channel* : int
    tchannel* : int
    profile* : int
    ctype* : string
    cname* : string
    
type
  SeqChanConf* = seq[ChanConf]

type
  SchedEvent* = object of RootObj
    hrs* : int
    mins* : int
    channel* : int
    command* : string
    
type
  SeqSchedEvent* = seq[SchedEvent]

type
  SchedTempEvent* = object of SchedEvent
    dow*  : int
    temp* : int
