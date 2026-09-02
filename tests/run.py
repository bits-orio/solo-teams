#!/usr/bin/env python3
"""Headless test runner for the MTS reaper.

Factorio's require() uses dotted module names that map to paths, which is
exactly stock Lua package.path behaviour, so the real modules load unchanged.
The Factorio runtime itself is mocked in tests/mock_factorio.lua.
"""
import sys, os
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{ROOT}/?.lua;{ROOT}/?/init.lua;" .. package.path')
    try:
        report = lua.execute('return (require("tests.test_reaper"))')
    except Exception as exc:
        print("HARNESS ERROR:", exc)
        return 2

    passed, failed = int(report["passed"]), int(report["failed"])
    failures = report["failures"]
    for i in range(1, len(failures) + 1):
        print("  FAIL:", failures[i])
    print(f"\n{passed} passed, {failed} failed")
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
