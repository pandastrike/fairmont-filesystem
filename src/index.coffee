import {promisify} from "util"
import {exec} from "child_process"
import {join, dirname} from "path"
import stream from "stream"
import {curry, binary} from "panda-garden"
import {isType, isKind, isFunction, isString, isPromise, isBuffer,
  promise, eq} from "panda-parchment"
import Method from "panda-generics"
import fs from "fs"
import minimatch from "minimatch"

{create, define} = Method

FS = do (result = {}) ->
  for key, value of fs
    result[key] = if isFunction value then (promisify value) else value
  result


# we're going to export this
{stat} = FS

exists = exist =  (path) ->
  try
    (await FS.stat path)?
  catch
    false

isDirectory =  (path) ->
  try
    (await FS.stat path).isDirectory()
  catch
    false

isFile =  (path) ->
  try
    (await FS.stat path).isFile()
  catch
    false

isReadable = (x) -> x?.read?.call?

# socket-based streams are duplex streams
# and do not inherit from stream.writable
isWritable = (x) -> x?.write?.call?

read = create
  name: "read"
  description: "reads data from file, string, or stream"

define read, isString, isString,
  (path, encoding) ->
    FS.readFile path, encoding

define read, isString, (path) -> read path, 'utf8'

readBuffer = (path) -> FS.readFile path
define read, isString, (eq undefined), readBuffer
define read, isString, (eq "binary"), readBuffer
define read, isString, (eq "buffer"), readBuffer

# Stringifies a stream's buffer according to the given encoding.
readStream = (stream, encoding = "utf8") ->
  buffer = ""
  promise (resolve, reject) ->
    stream.on "data", (data) -> buffer += data.toString(encoding)
    stream.on "end", -> resolve buffer
    stream.on "error", (error) -> reject error

# Extracts a stream's raw buffer.
readBinaryStream = (stream) ->
  buffer = new Buffer(0)
  promise (resolve, reject) ->
    stream.on "data", (data) -> buffer = Buffer.concat [buffer, data]
    stream.on "end", -> resolve buffer
    stream.on "error", (error) -> reject error

define read, isReadable, readStream
define read, isReadable, isString, readStream
define read, isReadable, (eq undefined), readBinaryStream
define read, isReadable, (eq "binary"), readBinaryStream
define read, isReadable, (eq "buffer"), readBinaryStream

write = create
  name: "write"
  description: "writes data to file or stream"

define write, isString, isBuffer,
  (path, buffer) -> FS.writeFile path, buffer

define write, isString, isString,
  (path, content) -> FS.writeFile path, content

define write, isString, isReadable,
  (path, stream) -> stream.pipe fs.createWriteStream path

define write, isWritable, isString,
  (stream, content) ->
    promise (resolve, reject) ->
      stream.write content, "utf-8", (error) ->
        if !error?
          resolve()
        else
          reject error

write = curry binary write

readdir = readDir = (path) -> FS.readdir path

ls =  (path) ->
  (join path, file) for file in (await readdir path)

lsR = lsr =  (path, visited = []) ->
  children = await ls path
  for child in children when !(child in visited)
    if await isDirectory child
      await lsR child, visited
    else
      visited.push child
  visited

rmR = rmr = (path) ->
  if (await isDirectory path)
    paths = await ls path
    (await rmr _path) for _path in paths
    await rmDir path
  else if (await isFile path)
    await rm path

glob =  (pattern, path) ->
  minimatch.match (await lsR path), (join path, pattern)

chDir = chdir = create
  name: "chdir"
  description: "Changes the working directory and makes it easy to return."

define chdir, isString, (path) ->
  cwd = process.cwd()
  process.chdir path
  -> process.chdir cwd

define chdir, isString, isFunction, (path, f) ->
  restore = chdir path
  f()
  restore()

rm = (path) -> FS.unlink path

mv = curry binary (old, _new) -> FS.rename old, _new

cp = curry binary (old, _new) ->
  promise (resolve, reject) ->
    (fs.createReadStream old)
    .pipe(fs.createWriteStream _new)
    .on "error", (error) -> reject error
    .on "close", -> resolve()

rmDir = rmdir = (path) -> FS.rmdir path

mkDir = mkdir = curry binary (mode, path) -> FS.mkdir path, mode

mkDirP = mkdirp = curry binary  (mode, path) ->
  if !(await exists path)
    parent = dirname path
    if !(await exists parent)
      await mkdirp mode, parent
    try
      await mkdir mode, path
    catch error
      if error.code != "EEXIST"
        throw error

abort = (message) ->
  console.error message if message?
  process.exit -1

run = (command) ->
  promise (resolve, reject) ->
    exec command, (error, stdout, stderr) ->
      if error
        reject error
      else
        resolve {stdout, stderr}

print = ({stdout, stderr}) ->
  process.stdout.write stdout if stdout.length > 0
  process.stderr.write stderr if stderr.length > 0

export {read, write, stat, exist, exists,
  isReadable, isWritable, isFile, isDirectory,
  readdir, readDir, ls, lsR, lsr, glob,
  mkdir, mkDir, mkdirp, mkDirP, chdir, chDir,
  cp, mv, rm, rmdir, rmDir, rmR, rmr,
  run, print, abort}
