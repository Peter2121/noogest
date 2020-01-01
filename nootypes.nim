import times

type
  TempMeasurement* = object
    mTime* : Time
    mTemp* : float
  RefTempMeasurement* = ref TempMeasurement
