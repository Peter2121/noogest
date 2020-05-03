const
  DEBUG* : int = 3 # from 0 (no debug messages at all) to 5 (all debug messages sent to stdout)
  DEBUG_MEM* : int = 0
  TEST* : int = 1 # if >0 we consider that there is no real temperature hardware present

const
  NO_ERROR* = 0
  ERR_NO_DEVICE* = 1
  ERR_ERR_CONFIG* = 2
  ERR_CLAILM_IF* = 3
  ERR_MODE_TEST* = 4
  ERR_NO_MEM* = 5
  ERR_LOCKED* = 6

const
  BUF_SIZE* = 8'u16
  
const
  CHAN_USE_SCHED* : string = "sched"
  CHAN_USE_TEMP* : string = "temp"
  
const
  TEMP_ACCURACY* : float = 0.2

const
  MAX_CHANNEL* : int = 5
  MAX_TEMP_CHANNEL* : int = 4

const
  ACT_SRC_UNKNOWN* : int = 0
  ACT_SRC_MANUAL* : int = 1
  ACT_SRC_SCHED* : int = 2
  ACT_SRC_TEMP* : int = 3
  ACT_SRC_TEMP_DEF* : int = 4
  
