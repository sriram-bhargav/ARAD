import ConfigParser


def ReadConfig(configfile):
    parser = ConfigParser.ConfigParser()
    return parser.read(configfile)
