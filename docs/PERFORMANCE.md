# Performance measurements

Measured on macOS 27.0.1 (26A434), Apple Silicon, release optimization. These are local observations, not guarantees for other machines or macOS releases.

Option-Tab is now parked. The window-row benchmark below exercises retained panel code; it does not describe an enabled window-switching shortcut.

## Boundary and method

`zsh scripts/benchmark.sh [report.json]` prepares the real production AppKit panel without showing it. Each process warms up 100 navigation changes, then measures 2,000 changes for 3, 18 and 50 cached window entries with titles, badges and one cached image. It uses Matte to avoid compositor/backdrop variability. CPU is process user+system time (`getrusage`); peak RSS is recorded for the full benchmark process. This is not physical key-to-photon latency and excludes discovery, icon loading, window activation and compositor display.

Before/after binaries use the same harness and differ only in redundant cell updates. Three alternating runs per binary reduce one-off scheduling noise; the table reports the median of the three p50/p95/CPU results. Cold launches, title changes and uncached icons are different workloads. Dense layouts adapt their title geometry, so times need not increase monotonically with item count.

## Navigation result

| Entries | p50 before → after | p95 before → after | CPU seconds / 2,000 before → after |
| --- | --- | --- | --- |
| 3 | 0.0412 → 0.0346 ms | 0.0544 → 0.0462 ms | 0.0759 → 0.0616 |
| 18 | 0.1253 → 0.0740 ms | 0.2104 → 0.0909 ms | 0.2282 → 0.1124 |
| 50 | 0.1948 → 0.0457 ms | 0.2308 → 0.0569 ms | 0.3998 → 0.0765 |

The cost came from assigning unchanged item content, selection and geometry to every cell, rebuilding title/accessibility state and invalidating drawing on each navigation. The optimized path updates content only when ID/name/image identity/badge/title changes, and relayouts cells only when content, selection or geometry changes. With 50 cached entries this reduced median preparation latency by about 76% and CPU for the measured loop by about 81%. The absolute saving is a fraction of a millisecond; it is not a comparable percentage improvement to whole-app switching.

Regression checks change titles, badges and icons under stable IDs and inspect actual accessible/rendered results. Matte panel previews are byte-identical before/after. Settings/Guide/About differ by only two pixels in native toolbar corners; content and geometry remain unchanged.

## Memory and idle

Benchmark median peak RSS was 39.0 MiB before and 39.4 MiB after. This small peak difference is not evidence of a durable memory optimization; allocator, framework loading and compression vary. No memory-specific change was justified.

The existing installed app consumed no measurable cumulative CPU over a 30-second baseline (0.0% sampled CPU; process CPU time unchanged to 0.01 seconds). Its physical footprint was 40.5 MiB, peak 47.8 MiB. Its compressed resident set is not comparable with a newly launched process. Main-thread sampling primarily showed event-loop waiting. There was no evidence to justify a new idle timer, cache system or focus-policy rewrite.

The authorized GUI fixture run passed: 12 cross-app exact-window commits had median 24.8 ms (range 16.2–130.9 ms); four hidden-app reveals had median 22.7 ms (20.4–32.4 ms). A same-app window commit took 41.3 ms. These small samples describe callbacks after real OS focus confirmation, not a stable percentile estimate. Minimized-only/windowless commits took about 571/565 ms including bounded confirmation; foreground and preservation of minimized/windowless state passed. The panel optimization does not change this focus path, so no focus-latency gain is claimed. After installation, a fresh GUI process consumed 0.01 CPU seconds over 30 seconds (all sampled CPU values 0.0%), with physical footprint 24.7 MiB and peak 27.5 MiB. Its different lifetime/workload prevents attributing the lower footprint to this optimization; the controlled peak-RSS comparison shows no useful memory gain. Installation details are recorded in validation. The intentional 150 ms held-shortcut presentation delay remains unchanged; quick release bypasses presentation. Focus probes/OS transitions are a separate, much larger boundary than panel preparation. Minimized-only and windowless activation can wait for bounded focus confirmation even when foreground activation succeeds; this is retained behavior and a remaining candidate for a separately specified change.

## Limits

No energy, long-duration leak, physical-key input, or compositor display timing was measured. Live fixture tests cover production focus/discovery but not the global event tap. Permission/signing context is checked from the GUI host itself. Raw private reports remain in ignored build output, rather than embedding machine paths or process details in the public source export.
