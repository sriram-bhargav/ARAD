import json
import redis
import utils


class RedisTable():
    def __init__(self, config):
        self.creatives = redis.StrictRedis(host='localhost',
                                           port=config.get('Redis', 'port'),
                                           db=config.get('Redis', 'creatives'))

        self.tag_to_creative = redis.StrictRedis(host='localhost',
                                                 port=config.get('Redis', 'port'),
                                                 db=config.get('Redis', 'tag_to_creative'))

        self.conversions = redis.StrictRedis(host='localhost',
                                             port=config.get('Redis', 'port'),
                                             db=config.get('Redis', 'conversions'))

    def AddCreative(self, data):
        id = utils.NewId()
        self.creatives.set(id, json.dumps(data))
        for tag in data["tags"]:
            self.tag_to_creative.sadd(tag, id)
        return {"id": id, "success": True}

    def EditCreative(self, id, data):
        self.creatives.set(id, json.dumps(data))
        for tag in data["tags"]:
            self.tag_to_creative.sadd(tag, id)
        return {"id": id, "success": True}

    def TagToCreative(self, tag):
        creatives = self.tag_to_creative.smembers(tag)
        if creatives is None or len(creatives) == 0:
            return None
        id = list(creatives)[0]
        creative = self.IdToCreative(id)
        print creative
        creative["all_tags"] = creative["tags"]
        del creative["tags"]
        creative["requested_tag"] = tag
        creative["id"] = id
        return creative

    def IdToCreative(self, id):
        data = self.creatives.get(id)
        if not data: return data
        creative = json.loads(data)
        if "snippet" not in creative and creative["link"].endswith("-big.png"):
            creative["snippet"] = creative["link"].replace("-big.png", "-small.png")
        return creative

    def RemCreative(self, id):
        data = self.IdToCreative(id)
        if not data:
            return False
        self.creatives.delete(id)
        for tag in data["tags"]:
            self.tag_to_creative.srem(tag, id)
        return True

    def LogReaction(self, id, is_click):
        hmkey = "click" if is_click else "impressions"
        old_val = self.conversions.hmget(id, hmkey)
        print old_val
        old_val = int(0 if not old_val[0] else old_val[0])
        self.conversions.hmset(id, {hmkey: old_val + 1})

    def CreativeInfo(self, id):
        clicks, impressions = [0 if not x else x for x in self.conversions.hmget(id, "click", "impressions")]
        creative = self.IdToCreative(id)
        if not creative:
            return {}
        creative["clicks"] = clicks
        creative["impressions"] = impressions
        return creative

    def GetAll(self):
        keys = self.creatives.keys("*")
        data = self.creatives.mget(keys)

        def updateInfo(key, val):
            ret = json.loads(val)
            ret["id"] = key
            return ret

        return [updateInfo(k, v) for k, v in zip(keys, data)]
