# BioNDP – Milestone 1 Progress (Nov 17, 2026)

## What I'm trying to show

In-storage systems like GRAINS and MegIS move a big part of genome analysis into the SSD, but both still leave some work for the host CPU. Neither paper measures how much that leftover work costs. My project has two goals:

1. **Measure the host-side work** that remains after the SSD is done, for both GRAINS and MegIS, and find out whether it is memory-bound or compute-bound.
2. **Estimate whether near-memory processing (NMP) helps** with the GRAINS merge step, which I expect to be memory-bound. MegIS's leftover work is mostly read alignment, which is compute-heavy, so I use it as the counter-example where NMP should not help much.

## How I'm doing it

GRAINS hasn't released its code, and MegIS's code stops before abundance estimation. So I use the software that does the same host-side job:

- **GRAINS → Fulgor.** Fulgor is the software baseline in the GRAINS paper. For each read, it looks up every k-mer in the index (GRAINS does this inside the SSD), then merges the results to classify the read (GRAINS leaves this to the host). I'll split those two phases and measure only the merge.
- **MegIS → Minimap2.** MegIS's host aligns reads to the candidate species to estimate abundance. I run Minimap2 against the ground-truth genomes, since MegIS's candidate list should be very close to the true one.
- **No SSD emulation.** I only care about what happens after the data reaches host memory.

### Steps

| # | Step | Why |
|---|---|---|
| 1 | Get CAMI data and make read subsets | Realistic metagenomic input; subsets show how cost grows with input size |
| 2 | Build and run Fulgor | Stand-in for the GRAINS pipeline |
| 3 | Run Minimap2 on candidate genomes | Stand-in for MegIS abundance estimation |
| 4 | Split Fulgor into lookup and merge phases | So the host-only (merge) part can be measured on its own |
| 5 | Profile with `perf` + RAPL | Time, IPC, cache misses, memory traffic, energy → memory-bound or compute-bound? |
| 6 | Build a Python NMP model using published UPMEM numbers | Estimate merge time and energy on near-memory units |
| 7 | Compare CPU vs. NMP for the merge step | Does NMP actually help? |
| 8–10 | Plots, report, presentation | |

My baseline is the CPU running all the leftover work, which I measure myself. The GRAINS paper reports lookup speedups, so I can also estimate how big the merge becomes *after* GRAINS speeds up the lookup.

## What's done (Steps 1–3 ✅)

**Data.** I downloaded CAMI I Low complexity (11 GB) from GigaDB. It includes the reads (2×150 bp, paired), the gold-standard profile (60 strains, 23 species), and the source genomes (60 genomes + 20 small circular elements, 158 Mbp total). Since the reads were simulated from exactly these genomes, I use all of them as the MegIS candidate list.

**Subsets.** 100K, 500K, 1M, and 5M read pairs, taken from the start of the file so pairs stay together. Both tools treat each mate as a separate read, so the subsets contain 0.2M–10M reads.

**Indexes.** Fulgor (k=31, m=19): 118 MB. Minimap2 (`-x sr`): 443 MB.

**First runs** (single thread, end-to-end):

| Read pairs | Fulgor time | Fulgor mapped | Minimap2 time | Minimap2 mapped |
|---|---|---|---|---|
| 100K | 1.9 s | 99.1% | 4.5 s | 99.9% |
| 500K | 13.6 s | 99.1% | 29.2 s | 99.9% |
| 1M | 24.5 s | 99.1% | 39.5 s | 99.9% |
| 5M | 90.5 s | 99.1% | 227.0 s | 99.9% |

Peak memory: Fulgor ~130 MB, Minimap2 ~930 MB.

Both tools map over 99% of reads, which confirms the data and indexes are correct. Run time grows roughly linearly with input size. Minimap2 is about 2.5× slower than Fulgor because it does full base-level alignment, which fits my expectation that MegIS's host work is compute-heavy.

**Problems I fixed along the way**
- The download ran at about 0.3 MB/s over one connection. I switched to 16 parallel range requests, which brought it to about 6.6 MB/s.
- My first Minimap2 runs skipped base-level alignment (PAF output without `-c` only does chaining) and looked faster than Fulgor. I re-ran with `-c` so the full alignment cost is included.

## Things to watch in Milestone 2

- **Timing noise.** Time per read varies between runs (Fulgor 9–14 µs/read, Minimap2 20–29 µs/read), even though the work per read is the same. My laptop has a hybrid CPU with performance and efficiency cores, so for profiling I'll pin each run to one performance core and repeat it 3–5 times.
- **Small index.** With only 80 references, Fulgor's index is small and its color sets are short, so the merge might partly fit in cache and not look memory-bound. GRAINS uses graphs with thousands of genomes. If that happens, I'll scale the reference set up (CAMI Medium/High genomes, or extra RefSeq genomes).

## Next (due Dec 4)

- Step 4: modify Fulgor so the lookup and merge phases run and get measured separately.
- Step 5: profile both tools with `perf` and RAPL across all subsets.
- Step 6: collect the UPMEM numbers and write the NMP model.

*Versions: Fulgor commit ef65419, Minimap2 2.27-r1193, Intel Core Ultra 7 258V, 32 GB RAM, Linux.*
