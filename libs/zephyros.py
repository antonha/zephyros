import socket
import threading
import json
import Queue
import sys
import atexit



_old_excepthook = sys.excepthook
def myexcepthook(exctype, value, traceback):
    if exctype == KeyboardInterrupt:
        pass
    else:
        _old_excepthook(exctype, value, traceback)
sys.excepthook = myexcepthook






sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(('127.0.0.1', 1235))

rawMessageQueue = Queue.Queue(10)

def msgIdGen():
    i = 0
    while True:
        i += 1
        yield i

reifiedMsgIdGen = msgIdGen()


def runInBackground(fn):
    t = threading.Thread(target=fn)
    t.daemon = True
    t.start()



class DataReader:
    def __init__(self):
        self.buf = ''
        self.readingSize = None

    def processData(self):
        if self.readingSize:
            l = len(self.buf)
            if l >= self.readingSize:
                msg, self.buf = self.buf[:l], self.buf[l:]
                obj = json.loads(msg)
                self.readingSize = None
                rawMessageQueue.put(obj)
                self.processData()
        else:
            idx = self.buf.find('\n')
            if idx != -1:
                self.readingSize = int(self.buf[:idx])
                self.buf = self.buf[idx+1:]
                self.processData()


@runInBackground
def readForever():
    reader = DataReader()
    while True:
        reader.buf += sock.recv(4096)
        reader.processData()



sendDataQueue = Queue.Queue(10)



@runInBackground
def sendDataFully():
    while True:
        data = sendDataQueue.get()
        while len(data) > 0:
            numWrote = sock.send(data)
            data = data[numWrote:]




individualMessageQueues = {}


def sendMessage(msg, infinite=True, callback=None):
    msgId = reifiedMsgIdGen.next()
    tempSendQueue = Queue.Queue(10)
    individualMessageQueues[msgId] = tempSendQueue

    msg.insert(0, msgId)
    msgStr = json.dumps(msg)
    sendDataQueue.put(str(len(msgStr)) + '\n' + msgStr)

    if callback is not None:
        def tempFn():
            tempSendQueue.get() # ignore first
            if infinite:
                while True:
                    obj = tempSendQueue.get()
                    callback(obj[1])
            else:
                obj = tempSendQueue.get()
                callback(obj[1])
        runInBackground(tempFn)
        return None
    else:
        return tempSendQueue.get()[1]


@runInBackground
def dispatchIndividualMessagesForever():
    while True:
        msg = rawMessageQueue.get()
        msgId = msg[0]
        thisQueue = individualMessageQueues[msgId]
        thisQueue.put(msg)

def zephyros(fn):
    runInBackground(fn)
    while True: pass


class Proxy:
    def __init__(self, id): self.id = id
    def _send_sync(self, *args): return sendMessage([self.id] + list(args))

class Window(Proxy):
    def title(self): return self._send_sync('title')
    def frame(self): return self._send_sync('frame')
    def set_frame(self, f): self._send_sync('set_frame', f)



class Api:
    def alert(self, msg, duration=1): sendMessage([0, 'alert', msg, duration])
    def focused_window(self): return Window(sendMessage([0, 'focused_window']))
    def bind(self, key, mods, fn):
        def tmp_fn(obj): fn()
        sendMessage([0, 'bind', key, mods], callback=tmp_fn)
    def choose_from(self, lst, title, lines, chars, fn):
        sendMessage([0, 'choose_from', lst, title, lines, chars], callback=fn, infinite=False)

api = Api()
