from __future__ import annotations


def choose(flag: bool, first: int, second: int) -> int:
    if flag:
        return first
    else:
        return second


def large_value() -> int:
    return 9007199254740993
