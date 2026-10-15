#!/usr/bin/env python3
"""Publish the colors of screen regions that clients subscribe to.

See ~/.config/shroomery/screencolors/README.md (architecture, protocol v2,
how to write a consumer). Started on demand by the quickshell VisualizerApp;
a second copy exits at once while one is running.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), ".."))

from screencolors import daemon  # noqa: E402


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--rate", type=float, default=5.0, help="captures per second per monitor (default 5)")
    p.add_argument("--idle-exit", type=float, default=5.0,
                   help="seconds without clients before exiting (0 = never; default 5)")
    p.add_argument("--pattern", action="store_true",
                   help="sample a fixed test picture: up red, right green, down blue, left yellow")
    p.add_argument("--watch", action="store_true", help="subscribe and print the running daemon's frames")
    p.add_argument("--monitor", default="", help="--watch: the output (default: the focused one)")
    p.add_argument("--subscribe", default="",
                   help="--watch: a subscribe message (JSON text, or @file) instead of the screen edges")
    args = p.parse_args()
    if args.watch:
        sub = None
        if args.subscribe:
            text = open(args.subscribe[1:]).read() if args.subscribe.startswith("@") else args.subscribe
            sub = json.loads(text)
        return daemon.watch(args.monitor, sub)
    if args.rate <= 0:
        p.error("--rate must be positive")
    return daemon.run(args.rate, args.idle_exit, args.pattern)


if __name__ == "__main__":
    sys.exit(main())
