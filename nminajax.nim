# minajax library with some additional javascript functions wrapper

type
  minAjaxConfObj {.importc.} = object
     url* : cstring
     rtype* : cstring
     data* : cstring
     success* : cstring
     rmethod* : bool
     debugLog* : bool

type
  minAjaxConf* = ref minAjaxConfObj

proc minAjax*(conf : minAjaxConfObj) {.importc.}

proc getValue*(id : cstring) : cstring {.importc.}

proc nimSetInterval*(jsfunc : cstring, interval : int, strarg : cstring) : int {.importc.}

proc nimSetTimeout*(jsfunc : cstring, timeout : int, strarg : cstring) : int {.importc.}

#proc nimSetInterval*(func : cstring, interval : int, intarg : int) : int {.importc.}

#proc nimSetTimeout*(func : cstring, timeout : int, intarg : int) : int {.importc.}
