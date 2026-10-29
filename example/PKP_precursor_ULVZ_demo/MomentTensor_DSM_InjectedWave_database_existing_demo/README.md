# MomentTensor_DSM_InjectedWave_database_existing_demo

This example reuses DSM databases, injected wavefields, and the completed
1-D synthetics from the case configured by `DSM_DATABASE_DIR`.

Run `bash step6_1d_dsm_synthetics.sh` to check compatibility. It checks the
CMTSOLUTION snapshot (including tensor and timing), receiver names and
coordinates, background model, synthesis provenance, and the completeness,
sampling and finite samples of the required Z/R/T SAC files. It does not
submit DSM jobs, recombine basis traces, or write to the shared database.

Step 10 performs the same check and reads the shared final 1-D synthetics
directly. It uses the actual injection timing for the scattering contribution.
Incompatible inputs stop the workflow; prepare matching databases and final
1-D synthetics in the producing example instead of modifying shared traces.
