import times

type
  TempMeasurementObj* = object
    mTime* : Time
    mTemp* : float

type
  TempMeasurement* = ref TempMeasurementObj

type
  ActionObj* = object
    aTime* : Time
    aAct* : string
    aRes* : int
    
type
  Action* = ref ActionObj
