# Assembly timing correction

The injection writer saves first index ipt_begin_save+1, whose physical time is ipt_begin_save*dt_Green. The corrected writer reports that time in t_begin_Green. Assembly uses t_begin_Green directly, or first_sample_time_Green when supplied. Legacy metadata requires an explicit injection_time_origin_version=1 to apply the old one-sample compensation.

Existing wavefield packages are unchanged by the Fortran metadata correction and are reused. Their start and end metadata are migrated before the timing reruns. Adjacent packages share one sample, so duration is npackage_Green*(npt_eachpack_Green-1)*dt_Green. npt_Green continues to count stored samples including duplicate boundaries. Main and Auto starts are 567.9321289062 and 568.3898925781 seconds.

Regression test: tests/test_assembly_time_origin.py. The backups directory was deleted at the user's request after the timing reruns. TIMING_RERUN_REPORT.json retains the historical corrected windows, backup paths and submitted jobs; those backup paths no longer exist.
