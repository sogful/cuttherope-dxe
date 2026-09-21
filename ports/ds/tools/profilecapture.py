"""Read-only profiling of the instrumented ROM; never changes game state."""

import json
import statistics
from PIL import ImageChops, ImageStat

fields = (
    "frame physics samples ropes scene upload read decode wait transfer render "
    "weights segments bodies uploads uploadbytes previousevictions polygons vertices "
    "gpuerrors uploadstart uploadend visibleupload commands holds upperdraw upperreads upperplace upperblit upperworld upperhud"
).split()
timings = fields[1:11]+["upperdraw","upperplace","upperblit","upperworld","upperhud"]


class recorder:
    def __init__(self, directory, report, read, framebuffer):
        self.directory, self.report = directory, report
        self.read, self.framebuffer = read, framebuffer
        self.records, self.anomalies = [], []
        self.previous = None
        self.frame = self.sequence = self.emuframe = self.stale = 0

    def observe(self, state):
        self.emuframe += 1
        values = dict(zip(fields, self.read("profiledata")))
        if values["frame"] != self.sequence and values["frame"] == state["frames"]:
            self.sequence = values["frame"]
            values.update({key: state[key] for key in (
                "level", "view", "state", "ticks", "menuage", "door", "doorframe",
                "transition", "intro", "micros", "flash", "vblanks", "resets", "repacks"
            )})
            values["emuframe"] = self.emuframe
            for key in timings:
                values[key] = round(values[key] * 1000000 / 33513982, 2)
            self.records.append(values)
        submitted=self.read("renderstamp",1)[0]
        self.stale = self.stale + 1 if submitted == self.frame else 0
        self.frame = submitted
        image = self.framebuffer().crop((0, 192, 256, 384))
        if self.previous and self.stale >= 3 and state["frames"] > 20:
            difference = ImageChops.difference(image, self.previous)
            mean = sum(ImageStat.Stat(difference).mean) / 3
            if mean > 0.5:
                changes = [b - a for a, b in zip(self.previous.tobytes(), image.tobytes())]
                event = {"emuframe": self.emuframe, "state": state, "stale": self.stale,
                         "difference": mean, "minimumChannelChange": min(changes),
                         "maximumChannelChange": max(changes),
                         "live": dict(zip(fields, self.read("_ZN9profiling4dataE")))}
                self.anomalies.append(event)
                if len(self.anomalies) <= 24:
                    label = "stale-change-" + str(len(self.anomalies))
                    self.previous.save(self.directory / (label + "-before.png"))
                    image.save(self.directory / (label + "-after.png"))
        self.previous = image

    def save(self):
        summaries = {}
        for level in sorted({item["level"] for item in self.records}):
            rows = [item for item in self.records if item["level"] == level
                    and item["view"] == 0 and item["state"] == 0 and not any(item[key] for key in
                    ("intro", "door", "transition", "flash", "uploads")) and item["ticks"] >= 30]
            if rows:
                summaries[f"{level // 25 + 1}-{level % 25 + 1}"] = {
                    "frames": len(rows),
                    "medianUs": {key: round(statistics.median(item[key] for item in rows), 2)
                                 for key in ("micros", *timings)},
                    "maxPolygons": max(item["polygons"] for item in rows),
                    "maxVertices": max(item["vertices"] for item in rows),
                    "maxRopeSegments": max(item["segments"] for item in rows),
                    "maxCurveWeights": max(item["weights"] for item in rows),
                }
        result = {"romSha256": self.report["romSha256"], "summaries": summaries,
                  "gpuErrors": max((item["gpuerrors"] for item in self.records), default=0),
                  "visibleUploads": sum(item["visibleupload"] for item in self.records),
                  "previousFrameEvictions": sum(item["previousevictions"] for item in self.records),
                  "capturedFrameHolds": sum(item["holds"] for item in self.records),
                  "staleFrameChanges": self.anomalies, "samples": self.records}
        (self.directory / "profile.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print("PROFILE:", json.dumps({key: value for key, value in result.items()
                                     if key not in ("samples", "staleFrameChanges")}), flush=True)
        print("Changes after >=3 frames without a submitted lower frame:", len(self.anomalies), flush=True)
