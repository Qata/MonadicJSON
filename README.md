# MonadicJSON

## !!! DEPRECATED !!!

The underlying issue was fixed circa iOS 17.
The library is still functional, but there's no good reason to use it.

## Original Description

The JSONDecoder supplied by Foundation is currently broken when it comes to isomorphic decoding of JSON numbers with fractional precision (what would be decoded to Float, Double and Decimal).
You can read about the issue on [the Swift bugtracker](https://bugs.swift.org/browse/SR-7054).

This project does not aim to be faster than the built-in JSONSerialization-based JSONDecoder, simply to be correct.
Tests have shown a significant slowdown when using this decoder over the inbuilt one, so if you don't need absolute precision, do not use this decoder.

This project is not intended as a permanent replacement for JSONDecoder, but purely as a stopgap until [SR-7054](https://bugs.swift.org/browse/SR-7054) is resolved.
