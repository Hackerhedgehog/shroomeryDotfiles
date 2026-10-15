"""Unix socket server: broadcast lines to every client and read their commands.

Non-blocking throughout. A client that stops reading is dropped once
MAX_PENDING bytes are queued for it, so it can never stall the daemon.
"""
import fcntl
import os
import socket

MAX_PENDING = 256 * 1024


def acquire_lock(path):
    """An fd holding an exclusive lock on path, or None when another daemon has it."""
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return None
    return fd


class _Client:
    def __init__(self, sock):
        self.sock = sock
        self.inbox = b""
        self.outbox = b""


class Server:
    def __init__(self, path):
        self.path = path
        try:
            os.unlink(path)  # stale socket from a crashed daemon (we hold the lock)
        except FileNotFoundError:
            pass
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(path)
        os.chmod(path, 0o600)
        self.sock.listen(8)
        self.sock.setblocking(False)
        self.clients = []

    @property
    def client_count(self):
        return len(self.clients)

    def poll(self):
        """Accept new clients; return (client, line) for each complete line."""
        while True:
            try:
                conn, _ = self.sock.accept()
            except BlockingIOError:
                break
            conn.setblocking(False)
            self.clients.append(_Client(conn))
        lines = []
        for c in list(self.clients):
            try:
                while True:
                    chunk = c.sock.recv(4096)
                    if not chunk:
                        self._drop(c)
                        break
                    c.inbox += chunk
            except BlockingIOError:
                pass
            except OSError:
                self._drop(c)
                continue
            *done, c.inbox = c.inbox.split(b"\n")
            lines += [(c, line.decode(errors="replace")) for line in done if line.strip()]
        return lines

    def send(self, c, data):
        """Queue `data` for one client and send what the socket takes now."""
        if c not in self.clients:
            return
        if len(c.outbox) > MAX_PENDING:
            self._drop(c)
            return
        c.outbox += data
        try:
            sent = c.sock.send(c.outbox)
            c.outbox = c.outbox[sent:]
        except BlockingIOError:
            pass
        except OSError:
            self._drop(c)

    def broadcast(self, data):
        for c in list(self.clients):
            self.send(c, data)

    def _drop(self, c):
        if c in self.clients:
            self.clients.remove(c)
        try:
            c.sock.close()
        except OSError:
            pass

    def close(self):
        for c in list(self.clients):
            self._drop(c)
        self.sock.close()
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass
