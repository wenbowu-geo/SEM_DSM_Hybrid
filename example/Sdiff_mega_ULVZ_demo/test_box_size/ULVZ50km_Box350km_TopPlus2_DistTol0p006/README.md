# Box327km with two extra top elements

Adds two top elements of the original thickness 11.9090909091 km, raising
the top by 23.8181818182 km. Total thickness is
350.484848485 km. Layers are 4/4/9/13. The original
18°×18°, 75×80 horizontal mesh and original radial elements are preserved.
Coupling boundaries retain their original physical locations. Source,
teleseismic receivers, diagnostic receiver depth 2801.5 km, ULVZ, background
model, DT and injection window remain unchanged. Distance threshold is
0.006°. Partition is compute.

The original source-to-box DSM data ends at depth 2609 km; the new top
is at 2585.18181818 km. This is the reference case that generates the
source-to-box, box-to-receiver, and 1-D DSM databases shared by the other
box-size examples. Its three `DSM_*_DIR` reuse parameters are intentionally
blank so steps 4--6 compute into the local `WORK/DSM` tree.

Run steps 4--6 and wait for their submitted DSM jobs (including the Step 6
frequency-to-time and synthesis dependencies) to finish successfully before
starting the mesh-to-coupling workflow. Job records from `run_hydra.sh` are
stored in `WORK/Hydra/workflow.json`.

```bash
bash step0_prepare_model.sh --check
bash step4_dsm_src_to_box.sh
bash step5_dsm_box_to_recv.sh
bash step6_1d_dsm_synthetics.sh
# Wait for all DSM jobs to finish successfully.
bash run_hydra.sh start
```


## Mesh update: 2026-10-17

Reference mesh: 80 × 80 horizontal elements over 18° × 18°, using 256 SEM ranks (16 × 16). Radial mesh unchanged. Fresh mesh/database generation, injection extraction, solver and coupling runs are required. Existing outputs describe the previous mesh. This update supersedes earlier dimensions and rank counts in this file.
