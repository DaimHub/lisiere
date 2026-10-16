#!/usr/bin/env python3
"""Loopback-only fixture for profile isolation, including a visible Release-app check."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PAGE = r'''<!doctype html><meta charset="utf-8"><title>Profile isolation</title>
<style>body{font:18px system-ui;margin:40px;max-width:760px}input,button{font:inherit;padding:8px}pre{white-space:pre-wrap;background:#eee;padding:16px}</style>
<h1>Profile isolation</h1><p>Same origin. Separate cookies, storage, worker and HTTP cache.</p>
<label>Marker <input id="marker" value="alpha"></label> <button onclick="writeMarker(marker.value).then(refresh).catch(showError)">Save marker</button>
<button onclick="refresh()">Read stored data</button><pre id="result">Loading…</pre>
<script>
const dbName = 'profile-isolation';
function database() { return new Promise((resolve,reject) => { const r=indexedDB.open(dbName,1); r.onupgradeneeded=()=>r.result.createObjectStore('values'); r.onsuccess=()=>resolve(r.result); r.onerror=()=>reject(r.error); }); }
async function writeMarker(value) {
 document.cookie = 'profileMarker='+encodeURIComponent(value)+'; Max-Age=86400; SameSite=Lax; Path=/';
 localStorage.setItem('profileMarker',value);
 const db=await database(); await new Promise((resolve,reject)=>{const t=db.transaction('values','readwrite'); t.objectStore('values').put(value,'marker');t.oncomplete=resolve;t.onerror=()=>reject(t.error)}); db.close();
 const cache=await caches.open('profile-isolation'); await cache.put('/cached-marker',new Response(value));
 if ('serviceWorker' in navigator) { await navigator.serviceWorker.register('/worker.js?marker='+encodeURIComponent(value)); await navigator.serviceWorker.ready; }
}
async function readMarker() {
 const db=await database(); const value=await new Promise((resolve,reject)=>{const r=db.transaction('values').objectStore('values').get('marker');r.onsuccess=()=>resolve(r.result||null);r.onerror=()=>reject(r.error)});db.close();
 const cache=await caches.open('profile-isolation');const cached=await cache.match('/cached-marker');
 const registrations='serviceWorker' in navigator ? await navigator.serviceWorker.getRegistrations() : [];
 const httpCache=await (await fetch('/http-cache')).text();
 return {cookie:document.cookie,localStorage:localStorage.getItem('profileMarker'),indexedDB:value,cache:cached?await cached.text():null,workers:registrations.map(r=>(r.active||r.waiting||r.installing).scriptURL),httpCache};
}
function showError(e){result.textContent='ERROR: '+e;}
async function refresh(){try{result.textContent=JSON.stringify(await readMarker(),null,2);}catch(e){showError(e);}}
refresh();
</script>'''

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        headers = {'Cache-Control': 'no-store'}
        if path == '/worker.js':
            body = b"self.addEventListener('install',()=>self.skipWaiting());self.addEventListener('activate',e=>e.waitUntil(clients.claim()));"
            mime = 'application/javascript'
        elif path == '/http-cache':
            self.server.cache_requests += 1
            body = f'network-response-{self.server.cache_requests}'.encode()
            mime = 'text/plain'
            headers = {'Cache-Control': 'public, max-age=86400'}
        elif path == '/metrics':
            body = json.dumps({'cache_requests': self.server.cache_requests}).encode()
            mime = 'application/json'
        elif path == '/favicon.ico':
            self.send_error(404)
            return
        else:
            body, mime = PAGE.encode(), 'text/html; charset=utf-8'
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        for key, value in headers.items(): self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_): pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=0)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    server.cache_requests = 0
    print(server.server_port, flush=True)
    server.serve_forever()
