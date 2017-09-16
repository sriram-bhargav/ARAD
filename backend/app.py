#!/usr/bin/python
# -*- coding: utf-8 -*-

from flask import Flask

import logging
from initlogging import handler, print_exc

app = Flask(__name__)
app.logger.addHandler(handler)
app.logger.setLevel(logging.INFO)
LOG = app.logger
LOG.print_exc = lambda msg: print_exc(LOG, msg)
LOG.info("log started")


@app.route('/')
@app.route('/index')
def IndexHandler():
    return 'Im alive'


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9856)