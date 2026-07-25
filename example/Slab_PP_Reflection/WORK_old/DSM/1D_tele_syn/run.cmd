#!/bin/bash

echo "computing the 1-D teleseismic synthetic example : `date`"

######################################Start - Specify your input parameters###################################

#################### Step 1: DSM Solver Input Control Parameters ####################

# length of seismogram. Leave empty to copy from dsm_model_input.
time_length=

# number of frequency samples. Leave empty to copy from dsm_model_input.
n_frequency=

# imaginary frequency. Leave empty to copy from dsm_model_input.
omega_imag=

# Number of processors used
NPROC=256

# DSM solver memory per CPU. Leave empty to use the cluster default.
DSM_mem_per_cpu="4G"

# Parameters for defining depths in each layer (zone).
# layer11 - the top crust
# In this case, only one depth (station at free surface) is set to compute 1-D teleseismic synthetics,
# rather the Green's function database.
declare -i ndep_top_layer1=1
id_zone_layer1=11
top_dep_layer1=0.0
bot_dep_layer1=1.0

# Ddepth_for_stress: spacing used to create three radial nodes for stress.
# depth_tolerence: threshold for merging closely spaced nodes.
depth_tolerence=0.0025
Ddepth_for_stress=0.01

# save displacement (choose 1) or velocity (choose 2) seismograms
save_velo=1

# source type, 1 for moment tensor and 2 for single force.
moment_or_force=1

currentdir=`pwd`
dir_SEM="${currentdir}/../../../../SPECFEM3D/EXAMPLES_COUPLING/Slab_PP_Reflection"
dir_src="${currentdir}/../../../src/DSM_Solver"
cmt_file="${dir_SEM}/DATA/CMTSOLUTION"
station_file="DATA/tele_station.txt"

# HPC environment settings
modules=""
mpiruncmd="mpirun"

#################### Step 2: Frequency-to-Time SAC Conversion Input Control Parameters ####################

# Frequency-domain to time-domain SAC conversion.
# The conversion job is submitted with dependency=afterok:<DSM_JOBID>.
run_freq_to_time_sac=1
freq2sac_runner="run_freq_to_time_sac.sh"
freq2sac_NPROC=1
freq2sac_time_estimate="01:00:00"
freq2sac_mem_per_cpu="4G"

# Select which frequency-domain result to convert to SAC:
#   ncomp=1: fluid scalar output, set freq2sac_fluid_quantity=potential or pressure
#   ncomp=3: vector output; set media_type=solid with solid_quantity=disp or velo,
#            or media_type=fluid with fluid_quantity=disp
#   ncomp=6: solid stress output from OUTPUT_FILES/stress
freq2sac_ncomp_seismogram=3
freq2sac_media_type="solid"
freq2sac_solid_quantity="disp"
freq2sac_fluid_quantity="potential"
freq2sac_nfrequency=

#################### Shared Output Settings ####################

ndep_total=`expr $ndep_top_layer1`

# Output directories and subdirectories
dir_output='OUTPUT_FILES'
sub_dir_output=("coef_cAnddcdr" "disp_fluid" "disp_solid" "stress" "potential" "pressure" "velo_solid")
declare -a sources=("Mzz" "Mrr" "Mtt" "Mzr" "Mzt" "Mrt")
###################################### End: Specify Input Parameters #######################################

if [ ! -f "${cmt_file}" ]; then
    echo "Error: cannot find CMTSOLUTION: ${cmt_file}"
    exit 1
fi

if [ ! -f "${station_file}" ]; then
    echo "Error: cannot find station file: ${station_file}"
    exit 1
fi

if [ "${run_freq_to_time_sac}" -eq 1 ] && [ ! -f "${freq2sac_runner}" ]; then
    echo "Error: cannot find frequency-to-SAC runner: ${freq2sac_runner}"
    exit 1
fi

source_depth_km=`awk '$1 == "depth:" {print $2}' ${cmt_file}`
source_lat=`awk '$1 == "latitude:" {print $2}' ${cmt_file}`
source_lon=`awk '$1 == "longitude:" {print $2}' ${cmt_file}`

if [ -z "${source_depth_km}" ] || [ -z "${source_lat}" ] || [ -z "${source_lon}" ]; then
    echo "Error: failed to read source depth/latitude/longitude from ${cmt_file}"
    exit 1
fi

echo "Using source depth/lat/lon from CMTSOLUTION:"
echo "  depth(km)=${source_depth_km} lat=${source_lat} lon=${source_lon}"

###################################END - Specify your input parameters#######################################



###################### Function to Set Up and Run Jobs ######################
setup_and_run_job() {
    local tensor_dir=$1
    local force_vector=$2
    local job_name=$3
    local processors=$4
    local time_estimate=$5

    echo "Setting up $tensor_dir ..."
    mkdir -p $tensor_dir
    cd $tensor_dir

    # Copy executable
    echo "    Copying executable file..."
    cp ${dir_src}/dsmti .
    if [ "${run_freq_to_time_sac}" -eq 1 ]; then
        cp ../${freq2sac_runner} .
        chmod +x ${freq2sac_runner}
    fi

    # Clean previous outputs
    if [ "$1" != "noclean" ]; then
        echo "    Cleaning OUTPUT_FILES/..."
        rm -rf OUTPUT_FILES/
    fi

    # Create necessary directories
    mkdir -p DATA ${dir_output}
    for this_subdirectory in "${sub_dir_output[@]}"; do
        mkdir -p ${dir_output}/${this_subdirectory}
    done

    # Prepare input files
    echo "    Preparing input files..."
    cp ../${station_file} DATA/
    cp ${dir_SEM}/DATA/dsm_model_input DATA/

    echo "    Creating sorted distance table from DATA/tele_station.txt..."
    rm -f DATA/station_distances.txt DATA/station_distances.tmp
    awk -v slat="${source_lat}" -v slon="${source_lon}" '
    BEGIN {
      pi = atan2(0.0,-1.0)
      deg2rad = pi / 180.0
      rad2deg = 180.0 / pi
      lat1 = slat * deg2rad
    }
    /^[[:space:]]*#/ || NF < 4 { next }
    {
      lat2 = $4 * deg2rad
      dlon = ($3 - slon) * deg2rad
      cosdel = sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(dlon)
      if (cosdel > 1.0) cosdel = 1.0
      if (cosdel < -1.0) cosdel = -1.0
      dist = atan2(sqrt(1.0 - cosdel * cosdel), cosdel) * rad2deg
      printf("%16.8f %-8s %-8s %14.6f %14.6f\n",
             dist, $1, $2, $3, $4)
    }' DATA/tele_station.txt | sort -n > DATA/station_distances.tmp

    if [ ! -s DATA/station_distances.tmp ]; then
        echo "Error: no stations found in DATA/tele_station.txt"
        exit 1
    fi

    awk '{
      dist[NR] = $1
      line[NR] = sprintf("%-8s %-8s %14.6f %14.6f %16.8f",
                         $2, $3, $4, $5, $1)
    }
    END {
      print NR > "DATA/dist_solid_list"
      for (i = 1; i <= NR; i++) {
        printf("%16.8f\n", dist[i]) >> "DATA/dist_solid_list"
        print line[i] >> "DATA/station_distances.txt"
      }
    }' DATA/station_distances.tmp
    rm -f DATA/station_distances.tmp

    # The distance values in fluids must match those in solids.
    cp DATA/dist_solid_list DATA/dist_fluid_list

    echo "    Creating depth table..."
    echo ${Ddepth_for_stress} ${depth_tolerence} > DATA/depth_solid_list
    echo ${ndep_total} >> DATA/depth_solid_list
    echo $ndep_top_layer1 $top_dep_layer1 $bot_dep_layer1 $id_zone_layer1 | awk '{
      if ($1 <= 1) {
        printf("%10.4f %d\n", $2, $4)
      } else {
        ddep=($3-$2)/($1-1.0)
        for (idep=1; idep<=$1; idep++) {
          if (idep==$1) printf("%10.4f %d\n", $3, $4)
          else printf("%10.4f %d\n", $2+(idep-1)*ddep, $4)
        }
      }
    }' >> DATA/depth_solid_list

    echo ${Ddepth_for_stress} ${depth_tolerence} > DATA/depth_fluid_list
    echo 0 >> DATA/depth_fluid_list

    # Modify the dsm_model file for this specific run.
    echo "    Modifying dsm_model file for $tensor_dir..."
    awk -v time_length="$time_length" \
        -v n_frequency="$n_frequency" \
        -v omega_imag="$omega_imag" \
        -v source_depth_km="$source_depth_km" \
        -v source_lat="$source_lat" \
        -v source_lon="$source_lon" \
        -v moment_or_force="$moment_or_force" \
        -v save_velo="$save_velo" \
        -v force="$force_vector" '{
        if (NR == 1) {
            if (time_length == "") time_length = $1
            if (n_frequency == "") n_frequency = $2
            print time_length " " n_frequency "  #time_series_length n_freqnency"
        } else if (NR == 2) {
            if (omega_imag == "") omega_imag = $1
            print omega_imag "         #omega_imag";
        } else if (NR == 3) {
            print $0
        } else if (NR == 4) {
            n_structure_zone = $1
            post_structure_line = NR + 6 * n_structure_zone
            print $0
        } else if (post_structure_line > 0 && NR <= post_structure_line) {
            print $0
        } else if (NR == post_structure_line + 1) {
            print source_depth_km " " source_lat " " source_lon " " moment_or_force " #source_depth (km) source_lat source_lon source_type";
        } else if (NR == post_structure_line + 2) {
            print force " #exp_dyn-cm Mij,i=1-6 (moment tensor) OR exp_dyn Force_i,i=1,6 (only first three forces functional)";
        } else if (NR == post_structure_line + 3) {
            print "\"DATA/depth_solid_list\" #file listing the Greens function depths in solid media";
        } else if (NR == post_structure_line + 4) {
            print "\"DATA/dist_solid_list\" #file listing the Greens function distances in solid media";
        } else if (NR == post_structure_line + 5) {
            print "\"DATA/depth_fluid_list\" #file listing the Greens function depths in fluid media";
        } else if (NR == post_structure_line + 6) {
            print "\"DATA/dist_fluid_list\" #file listing the Greens function distances in fluid media";
        } else if (NR == post_structure_line + 7) {
            print save_velo " #save displacement (choose 1) or velocity (choose 2) seismograms in solid media";
        } else {
            print $0;
        }
    }' DATA/dsm_model_input > DATA/dsm_model

    # Prepare SBATCH script
    echo "    Preparing SBATCH script..."
    echo "#!/bin/bash" >submit_DSM_${tensor_dir}.cmd
    echo "#SBATCH --time=${time_estimate}   # walltime" >> submit_DSM_${tensor_dir}.cmd
    echo "#SBATCH --ntasks=${processors}   # number of processor cores" >> submit_DSM_${tensor_dir}.cmd
    if [ -n "${DSM_mem_per_cpu}" ]; then
        echo "#SBATCH --mem-per-cpu=${DSM_mem_per_cpu}   # memory per CPU core" >> submit_DSM_${tensor_dir}.cmd
    fi
    echo "#SBATCH -J \"${job_name}\"   # job name" >> submit_DSM_${tensor_dir}.cmd
    echo "#SBATCH --partition=scavenger" >>submit_DSM_${tensor_dir}.cmd
    echo "#SBATCH --qos=scavenger" >> submit_DSM_${tensor_dir}.cmd
    echo "###module load ${modules}" >> submit_DSM_${tensor_dir}.cmd
    echo "${mpiruncmd} ./dsmti < DATA/dsm_model" >> submit_DSM_${tensor_dir}.cmd

    # Submit the job
    echo "Submitting SBATCH job..."
    dsm_jobid=$(sbatch --parsable submit_DSM_${tensor_dir}.cmd)
    echo "    Submitted ${tensor_dir} DSM job: ${dsm_jobid}"

    if [ "${run_freq_to_time_sac}" -eq 1 ]; then
        echo "    Preparing dependent frequency-to-SAC job..."
        echo "#!/bin/bash" > submit_freq2sac_${tensor_dir}.cmd
        echo "#SBATCH --time=${freq2sac_time_estimate}   # walltime" >> submit_freq2sac_${tensor_dir}.cmd
        echo "#SBATCH --ntasks=${freq2sac_NPROC}   # number of processor cores" >> submit_freq2sac_${tensor_dir}.cmd
        if [ -n "${freq2sac_mem_per_cpu}" ]; then
            echo "#SBATCH --mem-per-cpu=${freq2sac_mem_per_cpu}   # memory per CPU core" >> submit_freq2sac_${tensor_dir}.cmd
        fi
        echo "#SBATCH -J \"freq2sac_${tensor_dir}\"   # job name" >> submit_freq2sac_${tensor_dir}.cmd
        echo "#SBATCH --dependency=afterok:${dsm_jobid}" >> submit_freq2sac_${tensor_dir}.cmd
        echo "#SBATCH --partition=scavenger" >> submit_freq2sac_${tensor_dir}.cmd
        echo "#SBATCH --qos=scavenger" >> submit_freq2sac_${tensor_dir}.cmd
        if [ -n "${modules}" ]; then
            echo "module load ${modules}" >> submit_freq2sac_${tensor_dir}.cmd
        fi
        cat << EOF >> submit_freq2sac_${tensor_dir}.cmd
submit_job=0 \\
NPROC=${freq2sac_NPROC} \\
modules="${modules}" \\
mpiruncmd="${mpiruncmd}" \\
nfrequency="${freq2sac_nfrequency}" \\
ncomp_seismogram=${freq2sac_ncomp_seismogram} \\
media_type="${freq2sac_media_type}" \\
solid_quantity="${freq2sac_solid_quantity}" \\
fluid_quantity="${freq2sac_fluid_quantity}" \\
./${freq2sac_runner}

${mpiruncmd} ../../../../src/DSM_FreqToTimeSac/spectotime
EOF
        freq2sac_jobid=$(sbatch --parsable submit_freq2sac_${tensor_dir}.cmd)
        echo "    Submitted ${tensor_dir} freq-to-SAC job: ${freq2sac_jobid} (afterok:${dsm_jobid})"
    fi

    echo "    Wait for $tensor_dir job to complete (~${time_estimate})."
    cd ..
}

# Set up and run jobs for each moment tensor basis component.
# Unit is dyn_cm=10^-7 N_m, so exp = 7 means 1 N_m.
setup_and_run_job "Mzz" "7 1.0 0.0 0.0 0.0 0.0 0.0" "DSM_Mzz" ${NPROC} "23:59:00"
setup_and_run_job "Mrr" "7 0.0 1.0 0.0 0.0 0.0 0.0" "DSM_Mrr" ${NPROC} "23:59:00"
setup_and_run_job "Mtt" "7 0.0 0.0 1.0 0.0 0.0 0.0" "DSM_Mtt" ${NPROC} "23:59:00"
setup_and_run_job "Mzr" "7 0.0 0.0 0.0 1.0 0.0 0.0" "DSM_Mzr" ${NPROC} "23:59:00"
setup_and_run_job "Mzt" "7 0.0 0.0 0.0 0.0 1.0 0.0" "DSM_Mzt" ${NPROC} "23:59:00"
setup_and_run_job "Mrt" "7 0.0 0.0 0.0 0.0 0.0 1.0" "DSM_Mrt" ${NPROC} "23:59:00"

echo "All jobs submitted."
