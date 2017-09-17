import ConfigParser
import random
import time


def ReadConfig(configfile):
    parser = ConfigParser.ConfigParser()
    parser.read(configfile)
    return parser


def CheckCreativeRequest(data):
    valid_tags = data.has_key("tags") and len(data["tags"])
    valid_image = data.has_key("link")
    return valid_tags and valid_image


def NewId():
    return str(random.randint(0, 100000)) + str(time.time())
