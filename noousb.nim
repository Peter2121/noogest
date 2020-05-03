import libusb,times,tables,strutils
import nooconst,nootypes,nooglob

proc sendUsbCommand*(command : string, chann : cuchar, level : cuchar) : int =

  const
    DEV_VID : cshort = 0x000016C0
    DEV_PID : cshort = 0x000005DF
    DEV_INTF : cint = 0
    DEV_CONFIG : cint = 1
    REQ_VAL = 0x00000300'u16
    REQ_IND = 0'u16
    COMMAND_SIZE = 8'u16
    TIMEOUT : cuint = 100

  var ptrCmdPtr : ptr cuchar
  var ptrCmdArr : ptr CArray[cuchar]
  var handle : ptr LibusbDeviceHandle
  var commands = initTable[string, cuchar]()
  var res : int = 0
  var ret : int = 0
  var req = 0'u8
  var usbContext : LibusbContext
  var refUsbContext = addr(usbContext)

  commands["on"]     = (cuchar)2
  commands["off"]    = (cuchar)0
  commands["sw"]     = (cuchar)4
  commands["set"]    = (cuchar)6
  commands["bind"]   = (cuchar)15
  commands["unbind"] = (cuchar)9
  commands["preset"] = (cuchar)7

  if(DEBUG>0) :
    echo `$`(getLocalTime(getTime()))," sendUsbCommand: command=",command," channel=",intToStr(int(chann))," level=",intToStr(int(level))

  if(lockUsb) :
    return ERR_LOCKED
  res = libusbInit(addr(refUsbContext))
  if (res != 0) :
    return res
  lockUsb = true
  libusbSetDebug(refUsbContext, (cint)LibusbLogLevel.error)
  handle = libusbOpenDeviceWithVidPid(refUsbContext, DEV_VID, DEV_PID)
  if (handle == nil) :
    libusbExit(refUsbContext)
    lockUsb = false
    return ERR_NO_DEVICE
  res = libusbKernelDriverActive(handle, DEV_INTF)
  if (res > 0) :
    res = libusbDetachKernelDriver(handle, DEV_INTF)
  ret = libusbSetConfiguration(handle, DEV_CONFIG)
  if (ret < 0) :
    discard libusbAttachIKernelDriver(handle, DEV_INTF)
    libusbClose(handle)
    libusbExit(refUsbContext)
    lockUsb = false
    return ERR_ERR_CONFIG
  ret = libusbClaimInterface(handle, DEV_INTF)
  if (ret < 0) :
    discard libusbAttachIKernelDriver(handle, DEV_INTF)
    libusbClose(handle)
    libusbExit(refUsbContext)
    lockUsb = false
    return ERR_CLAILM_IF

  req = (uint8)LibusbEndpointDirection.hostToDevice
  req = req or (uint8)LibusbRequestType.class
  req = req or (uint8)LibusbRequestRecipient.interf

  try :
    ptrCmdPtr = cast[ptr cuchar] (alloc0(COMMAND_SIZE))

    if( not (ptrCmdPtr==nil) ) :
      ptrCmdArr = cast[ptr CArray[cuchar]] (ptrCmdPtr)
      ptrCmdArr[0] = (cuchar)0x00000030
      ptrCmdArr[1] = commands[command]
      ptrCmdArr[2] = (cuchar)0
      ptrCmdArr[4] = cast[cuchar](int(chann) - 1)
      ptrCmdArr[5] = level

      if(command == "set") :
        ptrCmdArr[2] = (cuchar)1

      if(DEBUG>2) :
        echo "ptrCmdArr="
        for i in 0..7 :
          echo "\t",ptrCmdArr[i]

      ret = libusbControlTransfer(handle,
                                  req,
                                  LibusbStandardRequest.setConfiguration,
                                  REQ_VAL, REQ_IND,
                                  ptrCmdPtr, COMMAND_SIZE,
                                  TIMEOUT)

      discard libusbAttachIKernelDriver(handle, DEV_INTF)
      libusbClose(handle)
      libusbExit(refUsbContext)
      dealloc(ptrCmdPtr)
      lockUsb = false
      if (ret == (int)COMMAND_SIZE) :
        return NO_ERROR
      else :
        return ret
    else :
      discard libusbAttachIKernelDriver(handle, DEV_INTF)
      libusbClose(handle)
      libusbExit(refUsbContext)
      lockUsb = false
      return ERR_NO_MEM
  except :
    discard libusbAttachIKernelDriver(handle, DEV_INTF)
    libusbClose(handle)
    libusbExit(refUsbContext)
    dealloc(ptrCmdPtr)
    lockUsb = false
    return ERR_NO_MEM

proc getUsbData*(nd : var NooData) : int =

  const
    DEV_VID : cshort = 5824
    DEV_PID : cshort = 1500
    DEV_INTF : cint = 0
    DEV_CONFIG : cint = 1
    REQ_VAL = 0x00000300'u16
    REQ_IND = 0'u16
    TIMEOUT : cuint = 100

#  var ptrBufPtr = cast[ptr cuchar] (alloc0(BUF_SIZE))
  var ptrBufPtr : ptr cuchar
#  var ptrBufArr = cast[ptr CArray[cuchar]] (ptrBufPtr)
  var ptrBufArr : ptr CArray[cuchar]
  var handle : ptr LibusbDeviceHandle
  var res : int = 0
  var ret : int = 0
  var req = 0'u8
  var usbContext : LibusbContext
  var refUsbContext = addr(usbContext)

  if(lockUsb) :
    return ERR_LOCKED
  res = libusbInit(addr(refUsbContext))
  if (res != 0) :
    return res
  lockUsb = true
  libusbSetDebug(refUsbContext, (cint)LibusbLogLevel.error)
  handle = libusbOpenDeviceWithVidPid(refUsbContext, DEV_VID, DEV_PID)
  if (handle == nil) :
    libusbExit(refUsbContext)
    lockUsb = false
    return ERR_NO_DEVICE
  res = libusbKernelDriverActive(handle, DEV_INTF)
  if (res > 0) :
    res = libusbDetachKernelDriver(handle, DEV_INTF)
  ret = libusbSetConfiguration(handle, DEV_CONFIG)
  if (ret < 0) :
    discard libusbAttachIKernelDriver(handle, DEV_INTF);
    libusbClose(handle)
    libusbExit(refUsbContext)
    lockUsb = false
    return ERR_ERR_CONFIG
  ret = libusbClaimInterface(handle, DEV_INTF)
  if (ret < 0) :
    discard libusbAttachIKernelDriver(handle, DEV_INTF);
    libusbClose(handle)
    libusbExit(refUsbContext)
    lockUsb = false
    return ERR_CLAILM_IF
  req = (uint8)LibusbEndpointDirection.deviceToHost
  req = req or (uint8)LibusbRequestType.class
  req = req or (uint8)LibusbRequestRecipient.interf
  try :
    ptrBufPtr = cast[ptr cuchar] (alloc0(BUF_SIZE))
    if( not (ptrBufPtr==nil) ) :
      ret = libusbControlTransfer(handle,
                                  req,
                                  LibusbStandardRequest.setConfiguration,
                                  REQ_VAL, REQ_IND,
                                  ptrBufPtr, BUF_SIZE,
                                  TIMEOUT)

      discard libusbAttachIKernelDriver(handle, DEV_INTF)
      libusbClose(handle)
      libusbExit(refUsbContext)
      lockUsb = false
      if (ret == (int)BUF_SIZE) :
        ptrBufArr = cast[ptr CArray[cuchar]] (ptrBufPtr)
        for i in 0..<(int)BUF_SIZE :
          nd[i] = ptrBufArr[i]
        dealloc(ptrBufPtr)
        return NO_ERROR
      else :
        dealloc(ptrBufPtr)
        return ret
    else :
      discard libusbAttachIKernelDriver(handle, DEV_INTF)
      libusbClose(handle)
      libusbExit(refUsbContext)
      lockUsb = false
      return ERR_NO_MEM
  except :
    discard libusbAttachIKernelDriver(handle, DEV_INTF)
    libusbClose(handle)
    libusbExit(refUsbContext)
    lockUsb = false
    return ERR_NO_MEM
