#!/usr/bin/env python

from time import sleep
from random import randint
import unicornhat as unicorn
import requests

def checkPrtg():
    try:
        resp = requests.get('https://YOUR_PRTG_ADDRESS_HERE/api/getstatus.htm?id=0&username=YOUR_USERNAME&passhash=YOUR_PASSHASH')
        if resp.status_code != 200:
            # This means something went wrong.
            return -1
        result = resp.json()
        if not result['Alarms']:
            return 0
        return result['Alarms']
    except Exception:
        return -1

def setWarning():
    unicorn.brightness(1)
    unicorn.set_all(253,106,2)
    unicorn.show()

def setAlert():
    unicorn.brightness(1)
    unicorn.set_all(255,0,0)
    unicorn.show()

def setOkay():
    unicorn.off()
    unicorn.brightness(0.5)
    unicorn.set_pixel(randint(0, 7),randint(0, 7),0,255,0)
    unicorn.show()

unicorn.set_layout(unicorn.AUTO)
unicorn.rotation(0)
unicorn.brightness(1)

while True:
    alertCount = checkPrtg()
    if alertCount == -1:
        setWarning()
    elif alertCount > 0:
        setAlert()
    else:
        setOkay()
    sleep(4.7)
