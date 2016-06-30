#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# DekenServer - answer queries for packages/objects via http
#
# Copyright © 2016, IOhannes m zmölnig, forum::für::umläute
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as
#  published by the Free Software Foundation, either version 3 of the
#  License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

import http.server
import socketserver
from urllib.parse import parse_qs

PORT = 8000

##### input data
# libraryfile: lists all available libraries
#    this is a dump of what puredata.info currently reports
# format: <name/description>\t<url>\t<uploader>\t<date>
#
# $ cat libraryfile.txt
# Gem/0.93.3 (deken installable file for W32 32bit/i386))	http://puredata.info/downloads/gem/releases/0.93.3/Gem-v0.93.3-(Windows-i386-32)-externals.zip	zmoelnig	2016-05-20 22:10:28
# patch2svg-plugin-v0.1--externals.zip	http://puredata.info/downloads/patch2svg-plugin/releases/0.1/patch2svg-plugin-v0.1--externals.zip	zmoelnig	2016-03-22 16:29:25
#
# lib2obj-file: lists all objects in a library
#               library-name and version are implicitly given via the filename
# <library>-v<version>-objects.txt
#
# $ cat tof-v0.2.0-objects.txt
# crossfade~ cross fade between two signals
# getdollarzero get $0 for parent patch
# path get path of running patch
# $
#
#
# all input data is refreshed continuously (for now via a cron-job),
# and DekenServer needs to make sure that it always uses the current data
# TODO: inotify


def getopts():
    import argparse
    import configparser
    cfg = configparser.ConfigParser()
    parser = argparse.ArgumentParser()

    default_config={
        "http": {"port": PORT},
#        "libraries": {"location": None},
#        "objects": {"location": None},
        }
    cfg.read_dict(default_config)
    cfg.add_section("libraries")
    cfg.add_section("objects")

    parser.add_argument('-f', '--config',
                            type=str,
                            help='read configuration from file')
    parser.add_argument('-p', '--port',
                            type=int,
                            help='port that the HTTP-server listens on (default: %d)' % PORT)
    ## LATER: --library-list could be a remote URL as well...
    parser.add_argument('-l', '--library-list',
                            type=str,
                            help='location of a list of downloadable libraries')
    parser.add_argument('objectdir', nargs='*', help='directories to watch for obj2lib files')
    args=parser.parse_args()

    if args.config:
        cfg.read(args.config)
    if args.port:
        cfg["http"]["port"]=str(args.port)
    if args.library_list:
        cfg["libraries"]["location"]=args.library_list
    if args.objectdir:
        ods=cfg["objects"].get("location");
        od=[]
        if ods:
            od=ods.split("\n")
        od+=args.objectdir
        cfg["objects"]["location"]="\n".join(od)
    d=dict()
    for k0 in cfg.sections():
        d1=dict()
        for k1 in cfg[k0]:
            d1[k1]=cfg[k0].get(k1)
        d[k0]=d1

    ## sanitize values
    try:
        ods=d["objects"]["location"]
        od=[]
        if ods:
            od=ods.split("\n")
        d["objects"]["location"]=od
    except KeyError:
        d["objects"]["location"]=[]

    try:
        port=d["http"]["port"]
        d["http"]["port"]=int(port)
    except (KeyError, ValueError):
        d["http"]["port"]=0

    return d

class Server(socketserver.TCPServer):
    def __init__(self, server_address, RequestHandlerClass, bind_and_activate=True):
        socketserver.TCPServer.__init__(self, server_address, RequestHandlerClass, bind_and_activate)
        self._userdata={}
    def set(self, key, value):
        self._userdata[key]=value;
    def get(self, key):
        return self._userdata.get(key, None)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
    def _write(self, s):
        self.wfile.write(bytes(s, 'UTF-8'))
    def search(self, query):
        return("search for: %s" % (query))
    def do_GET(self):
        """Respond to a GET request."""
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        #self._write("<html><head><title>Title goes here.</title></head>")
        #self._write("<body><p>This is a test.</p>")
        #self._write("<p>You accessed path: %s</p>" % self.path)
        #self._write("</body></html>")
    def do_POST(self):
        try:
            length = self.headers['content-length']
            data = self.rfile.read(int(length))
        except Exception as e:
            print("POST-exception: %s" % (e))
            return
        try:
            d=self.parseQuery(data)
            #self._process(d, self.respond_JSON)
            print("POST: %s" % (d))
        except TypeError as e:
            print("oops: %s" % (e))


    @staticmethod
    def parseQuery(data):
        d=data.decode()
        try:
            return json.loads(d)
        except ValueError:
            return parse_qs(d)


class DekenServer:
    def __init__(self):
        pass

def run():
    config=getopts()
    print("config: %s" % (config))

    hnd = Handler
    httpd = Server(("", config["http"]["port"]), hnd)
    #httpd.set('oracles', oracles)
    hnd.cgi_directories = ["/"]
    print("serving at port %s" % (config["http"]["port"]))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    except:
        pass
    print("shutting down")
    httpd.shutdown()


if '__main__' ==  __name__:
    run()
