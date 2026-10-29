# Final Sdiff mega-ULVZ cases

## Hydra port

These cases were copied from the Poseidon checkout at
`SEM_DSM_Poseidon/SEM_DSM_Hybrid/example/Sdiff_mega_ULVZ` and ported to
Hydra.  Each case now uses `run_hydra.sh`, `auxiliary/hydra_workflow.py`,
and `auxiliary/hydra_environment.sh`.  The environment loads Hydra's
`gnu14/14.2.0` and `openmpi5/5.0.7` modules and uses the
`sqhao_seismo` Python environment.  Slurm partitions remain controlled by
`DATA/Par_file_SEM_DSM`; the configured `compute`, `scavenger`, and `mazu`
partitions are available on Hydra.

Only reproducible example inputs, scripts, metadata, and the reference DSM
database were copied. Archived runs, Slurm logs, and `OUTPUT_FILES*`
products were intentionally excluded. The DSM database was copied from
`test_box_size_old/ULVZ50km_Box350km_TopPlus2_DistTol0p006/WORK/DSM/` into
the corresponding reference case below. `POSEIDON_SOURCE.txt` files are
retained solely as provenance records.

Example 2 is the primary synthetic-computation case. The other cases test outer-core absorbing-boundary placement, boundary trimming and distance tolerance. All use the archived Box560km strike30/dip45/rake-90 source, its four receivers, exact 50-km ULVZ and unchanged elastic/Q background. SEM uses 240 ranks, coupling 256, and injection at most 100; all are below 280. Preparation launchers use compute.

| Example | Directory | Above / below CMB (km) | Width | Tolerance | Scientific partition |
| --- | --- | --- | --- | --- | --- |
| 1 | ULVZ50km_Box560km_DistTol0p006 | 280 / 280 | 18° | 0.006° | scavenger |
| **2 — main** | ULVZ50km_Box315km_DistTol0p006 | 280 / 35 | 17.1° | 0.006° | compute |
| 3 | ULVZ50km_Box303km_Cutout_DistTol0p006 | 268.091 / 35 | 17.4857142857143° | 0.006° | scavenger |
| 4 | ULVZ50km_Box315km_DistTol0p03 | 280 / 35 | 17.1° | 0.03° | compute |

Example 3 retains 75×80 horizontal elements while shrinking the widths; its radial boundaries trim exactly one element from each end of example 2. All cases use `SPECFEM3D_SOLVER_NSTEP=15000`; blank cut-window endpoints cause the scripts to derive the window using 130 s before and 180 s after the relevant arrivals. See each case's README and `DATA/Par_file_SEM_DSM` for precise dimensions.

Reusable DSM databases are stored under `ULVZ50km_Box350km_TopPlus2_DistTol0p006/WORK/DSM/` and shared by every active case. The reference case also points to these copied local products, so steps 4--6 reuse them instead of recomputing DSM. Each case creates its own mesh, Mij injection, and later outputs.

Compatibility note: the copied `src_to_box` depth list ends near 2935.67 km,
while the Box560km case extends to about 3169 km depth. That case is configured
to reuse the requested common database, but its depth coverage should be
validated before running; it may require the former `src_to_box_deep` data.

The four original Poseidon workflows were submitted and their mesh/database jobs completed successfully. Their initial job IDs were 2232866, 2232869, 2232872 and 2232875. Those statuses and job IDs are historical and do not describe this Hydra copy.

## Automatic version of the main case

`ULVZ50km_Box315km_DistTol0p006_Auto` removes mesh-layer, horizontal-element, MPI-layout and top-radius overrides, and leaves solver DT/NSTEP and cut-window endpoints blank. Same physical geometry and shared DSM paths as example 2. Preparation selects 75×80 horizontal elements, 15×16 ranks and 4/4/6/9 radial layers (23 total). Runtime timing is computed by steps 7 and 8.

## Lower-top strike-10 pair

The lower-top pair now matches the horizontal design of Box350km/Box315km: Box152km uses 18 degrees and 80 x 80 elements; Box129km uses 17.1 degrees and 76 x 76 elements, trimming two elements from every lateral side. Both have 0.225-degree spacing and regular cubed-sphere meshes. Depth configurations remain unchanged: 105/46.666667 km above/below CMB with 4/4/5 radial layers for Box152km; 94/35 km with 3/4/4 layers for Box129km. SEM uses 256 and 152 compute ranks respectively; coupling uses 256. Both retain strike10/dip90/rake0, shared DSM, 0.006-degree tolerance and corrected assembly timing.

## Source-labeled result folders

Completed products are labeled OUTPUT_FILES_strike30deg_dip45deg_rakeNeg90deg or OUTPUT_FILES_strike10dip90rake0. Five strike-30 cases were switched to strike 10° and steps 8–11 resubmitted with the existing Mij injection. Their completion hook verifies source consistency and renames outputs only after assembly/rotation succeed. The lower-top Box152km and Box129km cases already used strike 10° and were renamed without recomputation.


## Mesh update: 2026-10-17

The 350 km TopPlus2 tolerance-0.006 reference now uses 80 × 80 elements and 256 SEM ranks (16 × 16). All three Box315km cases now use exact 76 × 76 lateral cutouts (17.1° × 17.1°), preserving their 2609 km top depth and removing one bottom element to end at 2924 km depth. Their radial layers are 3/4/9/11, including Auto, and they use 152 SEM ranks (38 × 4). These settings supersede earlier dimensions and rank counts for these four cases. Existing mesh databases and subsequent outputs require regeneration. No jobs were submitted for this update.

## Case rename: 2026-10-18

The three former Box327km cases are now named Box315km to match their 2609–2924 km depth range (315 km thickness). Their revised meshes and steps 7–11 completed successfully on October 17. Current OUTPUT_FILES and OUTPUT_FILES_strike10dip90rake0 contain these updated results. The Auto case also uses 76 × 76 elements and 3/4/9/11 radial layers; the earlier automatic-layout description above is historical.
