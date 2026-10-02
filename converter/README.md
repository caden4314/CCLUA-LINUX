# Converter

This directory will contain Ubuntu-to-CCLUA semantic converters.

Planned stages:

1. Image acquisition and checksum verification.
2. ISO/rootfs extraction on the development PC.
3. Filesystem and package inventory.
4. Service/systemd graph extraction.
5. Command inventory and behavior catalog.
6. Config/schema conversion.
7. CCLUA compatibility library generation.
8. Native Lua program/service implementation.
9. Image assembly into `.luaiso`.
10. Conformance tests comparing expected Ubuntu-like behavior with CCLUA output.

Generated output should never overwrite manually maintained native implementations without review.
