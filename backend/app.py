#!/usr/bin/python
# -*- coding: utf-8 -*-

from flask import Flask

import logging
import json
from flask import Response
from flask import render_template
from flask import request
from flask import url_for

import utils
from db import RedisTable
from initlogging import handler, print_exc

app = Flask(__name__)
app.logger.addHandler(handler)
app.logger.setLevel(logging.INFO)
LOG = app.logger
LOG.print_exc = lambda msg: print_exc(LOG, msg)
LOG.info("log started")

config = utils.ReadConfig("arad.cfg")
db = RedisTable(config)


@app.route('/')
@app.route('/index')
def IndexHandler():
    return 'Im alive'


@app.route('/getads', methods=['POST', 'GET'])
def GetAds():
    data = json.loads(request.data)
    tags = data["tags"]
    device_id = data["ad_targeting_id"]
    LOG.info(str(data))

    ret = []
    for tag in tags:
        creative = db.TagToCreative(tag)
        if creative:
            ret.append(creative)
    LOG.info("GetAds:" + str(ret))
    return Response(json.dumps(ret), mimetype='application/json')


@app.route('/add-creative', methods=['POST', 'GET'])
def AddCreative():
    data = json.loads(request.data)
    LOG.info("AddCreative:" + str(data))
    valid = utils.CheckCreativeRequest(data)
    if not valid:
        ret = {'message': "Invalid Request", "success": False}
        return Response(json.dumps(ret), mimetype='application/json')
    data["tags"] = [tag.strip() for tag in data["tags"]]
    ret = db.AddCreative(data)
    return Response(json.dumps(ret), mimetype='application/json')


@app.route('/edit-creative/<id>', methods=['POST', 'GET'])
def EditCreative(id):
    data = json.loads(request.data)
    LOG.info("EditCreative:" + str(data))
    valid = utils.CheckCreativeRequest(data)
    if not valid:
        ret = {'message': "Invalid Request", "success": False}
        return Response(json.dumps(ret), mimetype='application/json')
    data["tags"] = [tag.strip() for tag in data["tags"]]
    ret = db.EditCreative(id, data)
    return Response(json.dumps(ret), mimetype='application/json')


@app.route('/reaction', methods=['POST', 'GET'])
def LogReaction():
    request_id = utils.NewId()
    data = json.loads(request.data)
    LOG.info("SeenCreative:" + str(data))
    if not data.has_key("id") or not data.has_key("is_click"):
        ret = {'message': "send id and is_click", 'request_id': request_id, "success": False}
    else:
        db.LogReaction(data["id"], data["is_click"])
        ret = {"success": True, "request_id" : request_id}
    return Response(json.dumps(ret), mimetype='application/json')


@app.route('/creative-info', methods=['POST', 'GET'])
def CreativeInfo():
    data = json.loads(request.data)
    LOG.info("LogReaction:" + str(data))
    if not data.has_key("id"):
        ret = {'message': "Id required", "success": False}
    else:
        ret = db.CreativeInfo(data["id"])
        ret["success"] = True
    return Response(json.dumps(ret), mimetype='application/json')


@app.route('/arad/delete/<id>', methods=['GET'])
def DummyDelete(id):
    return Delete(id)

@app.route('/arad/edit/<id>', methods=['GET', 'POST'])
def DummyEdit(id):
    return Edit(id)


@app.route('/delete/<id>', methods=['GET'])
def Delete(id):
    return Response(json.dumps({"success": db.RemCreative(id)}), mimetype='application/json')


@app.route('/arad/dashboard/<id>', methods=['GET'])
def DummyDashboard(id):
    return Dashboard(id)


@app.route('/dashboard/<id>', methods=['GET'])
def Dashboard(id):
    LOG.info(id)
    data = db.CreativeInfo(id)
    LOG.info(data)
    data["delete"] = url_for('DummyDelete', id=id)
    data["edit"] = url_for('DummyEdit', id=id)
    LOG.info(data)
    return render_template('info.html', data=data)


@app.route('/new', methods=['POST', 'GET'])
def Create():
    return render_template('create.html')

@app.route('/edit/<id>', methods=['POST', 'GET'])
def Edit(id):
    LOG.info(id)
    data = db.CreativeInfo(id)
    LOG.info(data)
    data["tags"] = ','.join(data["tags"])
    return render_template('edit.html', data=data)


@app.route('/list', methods=['POST', 'GET'])
def List():
    entries = db.GetAll()
    for entry in entries:
        print entry
        entry['dashboard'] = url_for('DummyDashboard', id=entry["id"])
    return render_template('list.html', entries=entries)


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9856)
