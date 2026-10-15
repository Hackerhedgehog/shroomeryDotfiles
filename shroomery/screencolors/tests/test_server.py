import os
import socket
import tempfile
import time
import unittest

from screencolors import server


def connect(path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(path)
    s.settimeout(1.0)
    return s


def poll_until(srv, predicate, timeout=1.0):
    lines, end = [], time.monotonic() + timeout
    while time.monotonic() < end:
        lines += srv.poll()
        if predicate(lines):
            return lines
        time.sleep(0.01)
    return lines


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "s.sock")
        self.srv = server.Server(self.path)

    def tearDown(self):
        self.srv.close()
        self.dir.cleanup()

    def test_lock_is_exclusive(self):
        lock_path = os.path.join(self.dir.name, "l.lock")
        first = server.acquire_lock(lock_path)
        self.assertIsNotNone(first)
        self.assertIsNone(server.acquire_lock(lock_path))
        os.close(first)
        again = server.acquire_lock(lock_path)
        self.assertIsNotNone(again)
        os.close(again)

    def test_broadcast_reaches_clients(self):
        c = connect(self.path)
        poll_until(self.srv, lambda _: self.srv.client_count == 1)
        self.srv.broadcast(b'{"x":1}\n')
        self.assertEqual(c.recv(100), b'{"x":1}\n')
        c.close()

    def test_client_lines_are_returned(self):
        c = connect(self.path)
        c.sendall(b'{"type":"subscribe"}\n{"partial"')
        lines = poll_until(self.srv, lambda ls: len(ls) >= 1)
        self.assertEqual(len(lines), 1)
        client, line = lines[0]
        self.assertIn(client, self.srv.clients)
        self.assertEqual(line, '{"type":"subscribe"}')
        c.close()

    def test_send_reaches_only_that_client(self):
        a, b = connect(self.path), connect(self.path)
        poll_until(self.srv, lambda _: self.srv.client_count == 2)
        a.sendall(b"hi\n")
        (first, _), = poll_until(self.srv, lambda ls: len(ls) >= 1)
        self.srv.send(first, b"only you\n")
        self.assertEqual(a.recv(100), b"only you\n")
        b.settimeout(0.2)
        with self.assertRaises(socket.timeout):
            b.recv(100)
        a.close()
        b.close()

    def test_closed_client_is_dropped(self):
        c = connect(self.path)
        poll_until(self.srv, lambda _: self.srv.client_count == 1)
        c.close()
        poll_until(self.srv, lambda _: self.srv.client_count == 0)
        self.assertEqual(self.srv.client_count, 0)
        self.srv.broadcast(b"still fine\n")

    def test_slow_client_is_dropped(self):
        c = connect(self.path)
        poll_until(self.srv, lambda _: self.srv.client_count == 1)
        chunk = b"x" * 65535 + b"\n"
        for _ in range(64):            # 4 MiB, never read by the client
            self.srv.broadcast(chunk)
        self.assertEqual(self.srv.client_count, 0)
        c.close()

    def test_close_removes_the_socket_file(self):
        self.srv.close()
        self.assertFalse(os.path.exists(self.path))
        self.srv = server.Server(self.path)   # tearDown closes it again


if __name__ == "__main__":
    unittest.main()
