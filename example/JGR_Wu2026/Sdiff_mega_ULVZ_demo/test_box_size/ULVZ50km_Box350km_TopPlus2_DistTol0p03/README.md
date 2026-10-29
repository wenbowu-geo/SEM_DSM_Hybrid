# Box327km with two extra top elements

Adds two top elements of the original thickness 11.9090909091 km, raising
the top by 23.8181818182 km. Total thickness is
350.484848485 km. Layers are 4/4/9/13. The original
18°×18°, 75×80 horizontal mesh and original radial elements are preserved.
Coupling boundaries retain their original physical locations. Source,
teleseismic receivers, diagnostic receiver depth 2801.5 km, ULVZ, background
model, DT and injection window remain unchanged. Distance threshold is
0.03°. Partition is compute.

The original source-to-box DSM data ends at depth 2609 km; the new top
is at 2585.18181818 km. This case generates a fresh local six-component
source-to-box database; the tested shared DSM database is untouched.
Receiver-side DSM and 1-D basis traces are reused. The runner waits for
mesh/database generation and all six new DSM jobs before injection, then
advances through steps 8–11. Workflow submitted on compute; job records are in WORK/Hydra/workflow.json.

```bash
bash step0_prepare_model.sh --check
bash run_hydra.sh start
```
