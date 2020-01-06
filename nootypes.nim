import times

type
  TempMeasurement* = object
    mTime* : Time
    mTemp* : float
  RefTempMeasurement* = ref TempMeasurement

type
  Action* = object
    aTime* : Time
    aAct* : string
    aRes* : int
