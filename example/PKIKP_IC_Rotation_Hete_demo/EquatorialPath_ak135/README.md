# EquatorialPath_ak135

## Refreshing the source amplitude

After changing only the moment tensor or explosion amplitude in
`DATA/CMTSOLUTION`, run from this case directory:

```bash
bash step6_1d_dsm_synthetics.sh --synthesis-only
```

Steps 7 and 10 also refresh stale 1-D synthetics automatically. Moment-tensor
cases recombine the six Mij basis traces; explosion cases multiply the
original DSM traces by the current/original isotropic moment ratio. Each
refresh starts from the original traces, so repeated edits do not compound
the scaling. Outputs and the CMTSOLUTION snapshot are saved locally under
`WORK/DSM/1D_tele_syn/OUTPUT_FILES/CMTSOLUTION_time_sac/`, including when
the basis database is shared via `DSM_1D_SYNTHETICS_DIR` or
`DSM_DATABASE_DIR/1D_tele_syn`. Source geometry changes require new DSM
traces; anisotropic tensors cannot reuse explosion traces. Other DSM model,
receiver and sampling settings must remain unchanged. The helper does not
apply a new source time function or time shift. To update final 3-D traces
assembled with an old source, rerun the affected solver/coupling steps and
then steps 10 and 11. Database-reuse cases provide a synthesis-only Step 6
entry point; full DSM runs belong in the case producing the database.
