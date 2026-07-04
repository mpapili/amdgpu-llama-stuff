import urllib.request, json

payload = json.dumps({
    "messages": [{"role": "user", "content": "hey"}],
    "stream": False
}).encode()

req = urllib.request.Request(
    "http://127.0.0.1:8080/v1/chat/completions",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=60) as r:
    print(r.read().decode())
