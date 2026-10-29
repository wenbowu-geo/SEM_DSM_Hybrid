# Main Sdiff example with automatic mesh and timing

Copy of `../test_box_size/ULVZ50km_Box315km_DistTol0p006` retaining its source, receivers, model, 18° widths, 280 km of mantle and 46.666666667 km of outer core, and 0.006° distance tolerance. It uses the same shared DSM paths as example 1 (`ULVZ50km_Box560km_DistTol0p006`); no DSM recomputation is required.

Explicit NZ_BOTTOM, NZ_ULVZ, NZ_ABOVE_ULVZ, NEX_XI, NEX_ETA, NPROC_XI, NPROC_ETA and R_TOP_BOUND overrides are removed. Step 1 chooses layer counts from wavelength targets, chooses processors within NPROC=240 and derives the top radius from geometry. Exact CMB, ULVZ-top and DSM discontinuity interfaces remain enforced.

SPECFEM3D_SOLVER_DT and NSTEP are blank: Step 8 uses the mesher-suggested time step with safety factor 0.4 and maximum DT 0.4 s, then computes run length from the source-to-box arrival span, ULVZ delay factor and 100-s additional buffer. START_TIME_CUT and END_TIME_CUT are blank: Step 7 computes them from arrivals and the 130-s before/180-s after buffers. TIME_BUFFER_CUT=50 remains only as fallback. Automatic DT and NSTEP are determined after the mesh and injected-wavefield jobs finish, not during input preparation.

Compute/default QoS is retained; SEM is capped at 240 ranks, coupling at 256. The exact copied background/Q model is preserved; only mesh and timing selection become automatic. New mesh tables and injection are required.

```bash
bash step0_prepare_model.sh --check
bash step1_specfem_mesh_database.sh
bash step2_3Dmodel_implementation.sh
bash step3_submit_specfem_mesh_gen.sh
# Wait for mesh/database generation to finish successfully.
bash step4_dsm_src_to_box.sh
bash step5_dsm_box_to_recv.sh
bash step6_1d_dsm_synthetics.sh
# Wait for any submitted DSM and SAC conversion jobs to finish successfully.
bash step7_extract_injected_waves.sh
# Wait for injection to finish successfully.
bash step8_specfem_solver.sh
# Wait for the solver to finish successfully.
bash step9_coupling.sh
# Wait for coupling to finish successfully.
bash step10_assemble_3d_sem_dsm_synthetics.sh
bash step11_rotate_synthetics_zrt.sh
```

Prepared automatic mesh: 75×80 elements, 15×16 ranks, radial layers 4/4/6/9 (23 total). This is a fresh mesh, rather than a reuse of the main mesh.

Assembly timing corrected: scattering is aligned using the physical first injected sample, accounting for the legacy one-sample metadata offset. Steps 10–11 were rerun; previous products are in `OUTPUT_FILES_before_timing_fix/`.


## Mesh update: 2026-10-17

Exact horizontal cutout of the updated 350 km reference: 76 × 76 elements over 17.1° × 17.1°, removing two elements at each lateral edge. Top remains at 2609 km depth. One bottom element is removed, placing the bottom at 2924 km depth (35 km below CMB). Radial layers are 3/4/9/11; these overrides also apply to Auto to preserve the shared mesh. SEM uses 152 ranks (38 × 4), since 76 × 76 does not support 256 ranks. Fresh mesh/database generation, injection extraction, solver and coupling runs are required. Existing outputs describe the previous mesh. This update supersedes earlier dimensions and rank counts in this file.

Current geometry: 2609–2924 km depth, 315 km thickness, 17.1° × 17.1° width, 76 × 76 horizontal elements, radial layers 3/4/9/11. Renamed from Box327km on 2026-10-18; existing updated results are preserved.
