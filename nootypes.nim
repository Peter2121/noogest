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
