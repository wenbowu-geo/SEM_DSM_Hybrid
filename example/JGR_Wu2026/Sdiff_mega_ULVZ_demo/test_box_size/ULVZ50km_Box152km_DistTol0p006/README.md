# Lower-top Sdiff case: ULVZ50km_Box152km_DistTol0p006

Horizontal mesh: 18.0 degrees in both directions; 80 x 80 elements; 0.225 degree spacing. The 152 km mesh matches the 350 km horizontal design; the 129 km mesh matches the 315 km horizontal design, trimming two elements from each lateral side of the 152 km mesh. Both use regular cubed-sphere meshes.

Depth geometry and radial interfaces are unchanged: 105 km above and 46.666666666667 km below CMB; radial layers [4, 4, 5] from bottom upward. The 129 km case trims one element at each radial end. Exact 50 km ULVZ, elastic/Q background, strike10/dip90/rake0 source, 0.006 degree tolerance, DT=0.0315307 s, NSTEP=14842 and 568-1100 s injection window are preserved.

SEM uses 256 compute ranks (16 x 16); coupling uses 256. Reuse shared DSM databases and existing 1-D synthetics. Regenerate mesh, SEM databases, injection and steps 8-11. Previous outputs: archive/before-horizontal-mesh-update-20261018-022746.
