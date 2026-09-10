#!/usr/bin/env python3
"""Summarize actual Wayland presentation feedback, excluding startup frames."""

import argparse
import csv
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("trace", help="CSV written by FLUTTER_LINUX_FRAME_TIMINGS")
parser.add_argument("--warmup", type=float, default=3)
parser.add_argument("--seconds", type=float, default=10)
args = parser.parse_args()
with open(args.trace, newline="") as stream:
    rows = list(csv.DictReader(stream))
presented = [row for row in rows if row["event"] == "presented"]
if not presented:
    parser.error("No presentation feedback. Keep the Wayland window visible and check compositor support.")
start = int(presented[0]["time_ns"]) + args.warmup * 1e9
end = start + args.seconds * 1e9
sample = [row for row in presented if start <= int(row["time_ns"]) < end]
times = [int(row["time_ns"]) for row in sample]
if len(times) < 2:
    parser.error("Not enough displayed frames in the selected sample.")
intervals = [(b - a) / 1e6 for a, b in zip(times, times[1:])]
ordered = sorted(intervals)
late = sum(
    int(row["refresh_ns"]) > 0 and gap * 1e6 > int(row["refresh_ns"]) * 1.5
    for row, gap in zip(sample[1:], intervals)
)
print(f"Displayed frames: {len(times)}")
print(f"Presentation FPS: {(len(times) - 1) * 1e9 / (times[-1] - times[0]):.3f}")
print(f"Interval ms: median={statistics.median(intervals):.3f}, "
      f"p99={ordered[round((len(ordered) - 1) * .99)]:.3f}, max={max(intervals):.3f}")
print(f"Gaps longer than 1.5 reported refresh periods: {late}")
print(f"Presentation flags observed: {sorted({int(row['flags']) for row in sample})}")
