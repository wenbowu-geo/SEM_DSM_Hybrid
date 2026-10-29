# Final Sdiff example 2: ULVZ50km_Box315km_DistTol0p006

Primary synthetic-computation case.

Source, receivers, exact 50-km ULVZ, perturbations and elastic/Q model are copied from `old/ULVZ50km_Box560km`. The source is its strike30/dip45/rake-90 CMTSOLUTION. Mantle thickness is 280.000000000 km; outer core thickness is 46.666666667 km; total thickness is 326.666666667 km. Radial layers: 4/4/9/11. Horizontal mesh: 75 × 80, 18° × 18°. Diagnostic SEM station remains at depth 2801.5 km.

Distance tolerance: 0.006°. Scientific jobs use compute; SEM uses 240 ranks (15×16), coupling 256. Lightweight preparation launchers use compute to avoid the scavenger-node Slurm user-ID lookup issue. All jobs stay below 280 ranks.

All four cases read the copied DSM database under `../ULVZ50km_Box350km_TopPlus2_DistTol0p006/WORK/DSM/`; no DSM recomputation is needed. Each writes a local 1-D source combination, fresh mesh databases, injection, solver/coupling products and final outputs. The exact reference background is saved in `DATA/dsm_model_reference` so Q boundaries do not move when the mesh changes.

All cases use DT=0.0315307 s, NSTEP=14842 (467.9786494 s), and the same explicit injection window [568,1100] s. This keeps the simulated duration and physical injection time origin consistent across the tests.

```bash
bash step0_prepare_model.sh --check
bash run_hydra.sh start
bash run_hydra.sh status
```

The runner advances through mesh/database generation and steps 7–11 using afterok dependencies. Do not recompute steps 4–6; they refer to already-computed shared DSM inputs.

Step 7 waits for the copied shared DSM trees to be marked ready; mesh/database generation can run while that copy is finishing. Immutable basis records are hard-linked, with separate control-file copies; new source combinations and runtime outputs remain local.

Shared DSM copies are complete and their depth coverage verified. Initial submitted job chain: {"mesh": "2232869", "database": "2232870", "prepare_step7": "2232871", "step7": "2232882", "prepare_step8": "2232884"}.

Assembly timing corrected: scattering is aligned using the physical first injected sample, accounting for the legacy one-sample metadata offset. Steps 10–11 were rerun; previous products are in `OUTPUT_FILES_before_timing_fix/`.


## Mesh update: 2026-10-17

Exact horizontal cutout of the updated 350 km reference: 76 × 76 elements over 17.1° × 17.1°, removing two elements at each lateral edge. Top remains at 2609 km depth. One bottom element is removed, placing the bottom at 2924 km depth (35 km below CMB). Radial layers are 3/4/9/11; these overrides also apply to Auto to preserve the shared mesh. SEM uses 152 ranks (38 × 4), since 76 × 76 does not support 256 ranks. Fresh mesh/database generation, injection extraction, solver and coupling runs are required. Existing outputs describe the previous mesh. This update supersedes earlier dimensions and rank counts in this file.

Current geometry: 2609–2924 km depth, 315 km thickness, 17.1° × 17.1° width, 76 × 76 horizontal elements, radial layers 3/4/9/11. Renamed from Box327km on 2026-10-18; existing updated results are preserved.
