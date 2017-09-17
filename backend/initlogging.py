from logging.handlers import RotatingFileHandler
import logging
import traceback

# todo : pass log location from gunicorn
handler = RotatingFileHandler(
    'server.log',
    maxBytes=1000000,
    backupCount=100)
formatter = logging.Formatter(
    "%(asctime)s - %(name)s - %(levelname)s - %(message)s")
handler.setFormatter(formatter)
handler.setLevel(logging.INFO)


def print_exc(logger, msg):
    exc = traceback.format_exc()
    logger.exception('{} Exception:\n{}'.format(msg, exc))


def getlog(name):
    logger = logging.getLogger(name)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.print_exc = lambda msg: print_exc(logger, msg)
    return logger
