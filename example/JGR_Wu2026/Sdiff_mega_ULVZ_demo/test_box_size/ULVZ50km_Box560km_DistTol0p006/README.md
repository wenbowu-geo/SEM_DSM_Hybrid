# Final Sdiff example 1: ULVZ50km_Box560km_DistTol0p006

Sensitivity test: outer-core absorbing boundary position.

Source, receivers, exact 50-km ULVZ, perturbations and elastic/Q model are copied from `old/ULVZ50km_Box560km`. The source is its strike30/dip45/rake-90 CMTSOLUTION. Mantle thickness is 280.000000000 km; outer core thickness is 280.000000000 km; total thickness is 560.000000000 km. Radial layers: 24/4/9/11. Horizontal mesh: 75 × 80, 18° × 18°. Diagnostic SEM station remains at depth 2801.5 km.

Distance tolerance: 0.006°. Scientific jobs use scavenger; SEM uses 240 ranks (15×16), coupling 256. Lightweight preparation launchers use compute to avoid the scavenger-node Slurm user-ID lookup issue. All jobs stay below 280 ranks.

All four cases read the copied DSM database under `../ULVZ50km_Box350km_TopPlus2_DistTol0p006/WORK/DSM/`; no DSM recomputation is needed. Each writes a local 1-D source combination, fresh mesh databases, injection, solver/coupling products and final outputs. The exact reference background is saved in `DATA/dsm_model_reference` so Q boundaries do not move when the mesh changes.

All cases use DT=0.0315307 s, NSTEP=14842 (467.9786494 s), and the same explicit injection window [568,1100] s. This keeps the simulated duration and physical injection time origin consistent across the tests.

```bash
bash step0_prepare_model.sh --check
bash run_hydra.sh start
bash run_hydra.sh status
```

The runner advances through mesh/database generation and steps 7–11 using afterok dependencies. Do not recompute steps 4–6; they refer to already-computed shared DSM inputs.

Step 7 waits for the copied shared DSM trees to be marked ready; mesh/database generation can run while that copy is finishing. Immutable basis records are hard-linked, with separate control-file copies; new source combinations and runtime outputs remain local.

Shared DSM copies are complete and their depth coverage verified. Initial submitted job chain: {"mesh": "2232866", "database": "2232867", "prepare_step7": "2232868", "step7": "2232878", "prepare_step8": "2232879"}.

Assembly timing corrected: scattering is aligned using the physical first injected sample, accounting for the legacy one-sample metadata offset. Steps 10–11 were rerun; previous products are in `OUTPUT_FILES_before_timing_fix/`.
