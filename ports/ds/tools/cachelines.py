"""Check final ARM9 symbols, not just source declarations, for SD buffer isolation."""
import re


buffers = ("frontend::compressed", "frontend::staged", "upper::input", "upper::backdrop",
           "upper::palette", "audio::longbuffer", "audio::shortbuffer", "audio::musicbuffer")
flags = ("frontend::frozen", "frontend::armed", "frontend::captured", "upper::pending")


def validate(symbols):
    entries = {}
    for line in symbols.splitlines():
        match = re.fullmatch(r"([0-9a-f]+) ([0-9a-f]+) [a-zA-Z] (.+)", line)
        if match:
            address, size, name = match.groups()
            entries[name] = (int(address, 16), int(size, 16))
    failures = []
    for name in buffers:
        if name not in entries:
            failures.append(f"Missing buffer {name}")
            continue
        address, size = entries[name]
        if address % 32 or size % 32:
            failures.append(f"{name}: address={address:08x} size={size}, not whole cache lines")
        first, end = address // 32, (address + size + 31) // 32
        for flag in flags:
            if flag in entries and first <= entries[flag][0] // 32 < end:
                failures.append(f"{name} shares a cache line with IRQ state {flag}")
    assert not failures, "\n".join(failures)
    return {name: entries[name] for name in buffers}
