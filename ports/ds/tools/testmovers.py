"""Compare native mover samples with the real C# CTRMover export, not a reimplementation."""
import json
import math
from pathlib import Path

root = Path(__file__).resolve().parents[1]
native = json.loads((root / "build/leveltest.json").read_text())["movers"]
reference = json.loads((root / "tests/source-movers.json").read_text())
key = lambda item: tuple(item[name] for name in ("level", "kind", "index", "tick"))
lookup = {key(item):item for item in native}
errors = []
for item in reference:
    actual = lookup[key(item)]
    position = math.hypot(item["x"]-actual["x"],item["y"]-actual["y"])
    angle = abs(item["angle"]-actual["angle"])
    errors.append((max(position,angle),key(item),position,angle))
worst = sorted(errors,reverse=True)[:5]
report = dict(samples=len(errors),maximumPositionError=max(item[2] for item in errors),
              maximumAngleError=max(item[3] for item in errors),worst=worst)
(root / "build/movertest.json").write_text(json.dumps(report,indent=2))
assert all(position < .05 and angle < .05 for _,_,position,angle in errors), worst
print(f"PASS: {len(errors)} C# mover samples; max {report['maximumPositionError']:.6f} world pixels / {report['maximumAngleError']:.6f} degrees")
