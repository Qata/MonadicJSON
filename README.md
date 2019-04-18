# MonadicJSON

The JSONDecoder supplied by Foundation is currently broken when it comes to isomorphic decoding of JSON numbers.
You can read about the issue on [the Swift bugtracker](https://bugs.swift.org/browse/SR-7054).

This project does not aim to be faster than the built-in JSONSerialization-based JSONDecoder, simply to correct.
Tests have shown a 30% slowdown when using this decoder over the inbuilt one.

This project is not intended as a permanent replacement for JSONDecoder, but purely as a stopgap until SR-7054 is resolved.
