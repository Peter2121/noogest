#!/bin/sh
nim -d:release --outdir:./public/js js ngclient.nim
#nim -d:release --outdir:./public/js js dygraph.nim
nim c --threads:on --opt:none --debuginfo --gc:markAndSweep noogest.nim
