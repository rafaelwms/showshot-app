#!/usr/bin/env python3
"""Talks to the debug automation server (debug builds, 127.0.0.1:47391).

Sends each command and waits for its reply line before the next one —
`printf … | nc` half-closes the socket and the server then drops the replies
of commands that `await` something. `sleep N` pauses between commands.

    tool/debug_client.py 'capture area' 'sleep 1.5' 'select 100 100 600 400' 'confirm edit'
"""
import socket
import sys
import time

sock = socket.create_connection(('127.0.0.1', 47391))
stream = sock.makefile('rwb')
for command in sys.argv[1:]:
    if command.startswith('sleep '):
        time.sleep(float(command.split()[1]))
        continue
    started = time.time()
    stream.write((command + '\n').encode())
    stream.flush()
    reply = stream.readline().decode().strip()
    print(f'{command} -> {reply}  [{time.time() - started:.2f}s]', flush=True)
