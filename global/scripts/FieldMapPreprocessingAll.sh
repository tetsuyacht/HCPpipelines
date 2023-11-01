#!/bin/bash 

# Requirements for this script
#  installed versions of: FSL, gradunwarp (HCP version)
#  environment: HCPPIPEDIR, FSLDIR, HCPPIPEDIR_Global, PATH for gradient_unwarp.py

# -----------------------------------------------------------------------------------
#  Constants for specification of Averaging and Readout Distortion Correction Method
# -----------------------------------------------------------------------------------

SIEMENS_METHOD_OPT="SiemensFieldMap"
GENERAL_ELECTRIC_METHOD_OPT="GeneralElectricFieldMap"
PHILIPS_METHOD_OPT="PhilipsFieldMap"


# ------------------------------------------------------------------------------
#  Verify required environment variables are set
# ------------------------------------------------------------------------------

# if [ -z "${HCPPIPEDIR}" ]; then
# 	echo "$(basename ${0}): ABORTING: HCPPIPEDIR environment variable must be set"
# 	exit 1
# else
# 	echo "$(basename ${0}): HCPPIPEDIR: ${HCPPIPEDIR}"
# fi

# if [ -z "${FSLDIR}" ]; then
#   echo "$(basename ${0}): ABORTING: FSLDIR environment variable must be set"
#   exit 1
# else
#   echo "$(basename ${0}): FSLDIR: ${FSLDIR}"
# fi

# if [ -z "${HCPPIPEDIR_Global}" ]; then
# 	echo "$(basename ${0}): ABORTING: HCPPIPEDIR_Global environment variable must be set"
# 	exit 1
# else
# 	echo "$(basename ${0}): HCPPIPEDIR_Global: ${HCPPIPEDIR_Global}"
# fi



set -eu

pipedirguessed=0
if [[ "${HCPPIPEDIR:-}" == "" ]]
then
    pipedirguessed=1
    #fix this if the script is more than one level below HCPPIPEDIR
    export HCPPIPEDIR="$(dirname -- "$0")/.."
fi

# Load function libraries
source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@"         # Debugging functions; also sources log.shlib
source "$HCPPIPEDIR/global/scripts/newopts.shlib" "$@"


opts_SetScriptDescription "Script for generating a fieldmap suitable for FSL from Siemens Gradient Echo field map, and also do gradient non-linearity distortion correction of these"

opts_AddMandatory '--method' 'DistortionCorrection' 'method' "method to use for susceptibility distortion correction (SDC)
        '${SIEMENS_METHOD_OPT}'
             use Siemens specific Gradient Echo Field Maps for SDC
        '${GENERAL_ELECTRIC_METHOD_OPT}'
             use General Electric specific Gradient Echo Field Maps for SDC

        '${PHILIPS_METHOD_OPT}'
             use Philips specific Gradient Echo Field Maps for SDC"

opts_AddMandatory '--ofmapmag' 'MagnitudeOutput' 'image' "output distortion corrected fieldmap magnitude image"

opts_AddMandatory '--ofmapmagbrain' 'MagnitudeBrainOutput' 'image' "output distortion-corrected brain-extracted fieldmap magnitude image"

opts_AddMandatory '--ofmap' 'FieldMapOutput' 'image' "output distortion corrected fieldmap image (rad/s)"

#Optional Arguments
opts_AddOptional '--echodiff' 'DeltaTE' 'number (milliseconds)' "echo time difference for Siemens and Philips fieldmap images (in milliseconds)"

opts_AddOptional '--fmap' 'GEB0InputName' 'number (degrees)' "input General Electric fieldmap with fieldmap in deg and magnitude image"

opts_AddOptional '--fmapphase' 'PhaseInputName' 'number (radians)' "input Siemens/Philips fieldmap phase image - in radians"

opts_AddOptional '--fmapmag' 'MagnitudeInputName' 'image' "input Siemens/Philips fieldmap magnitude image - can be a 4D containing more than one"

opts_AddOptional '--workingdir' 'WD' 'path' 'working dir' "."

opts_AddOptional '--gdcoeffs' 'GradientDistortionCoeffs' 'path' "gradient distortion coefficients file" "NONE"

opts_ParseArguments "$@"

if ((pipedirguessed))
then
    log_Err_Abort "HCPPIPEDIR is not set, you must first source your edited copy of Examples/Scripts/SetUpHCPPipeline.sh"
fi

#display the parsed/default values
opts_ShowValues

log_Check_Env_Var FSLDIR

################################################ SUPPORT FUNCTIONS ##################################################

# source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@" # Debugging functions; also sources log.shlib

# Usage() {
#   echo "$(basename $0): Script for generating a fieldmap suitable for FSL from Siemens Gradient Echo field map,"
#   echo "               and also do gradient non-linearity distortion correction of these"
#   echo " "
#   echo "Usage: $(basename $0) [--workingdir=<working directory>]"
#   echo "            --method=<distortion correction method (SiemensFieldMap/PhilipsFieldMap/GeneralElectricFieldMap)>"
#   echo "            --fmapmag=<input Siemens/Philips fieldmap magnitude image - can be a 4D containing more than one>"
#   echo "            --fmapphase=<input Siemens/Philips fieldmap phase image - in radians>"
#   echo "            --fmap=<input General Electric fieldmap with fieldmap in deg and magnitude image>"
#   echo "            --echodiff=<echo time difference for Siemens and Philips fieldmap images (in milliseconds)>"
#   echo "            --ofmapmag=<output distortion corrected fieldmap magnitude image>"
#   echo "            --ofmapmagbrain=<output distortion-corrected brain-extracted fieldmap magnitude image>"
#   echo "            --ofmap=<output distortion corrected fieldmap image (rad/s)>"
#   echo "            [--gdcoeffs=<gradient distortion coefficients file>]"
}

# # function for parsing options
# getopt1() {
#     sopt="$1"
#     shift 1
#     for fn in $@ ; do
# 	if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
# 	    echo $fn | sed "s/^${sopt}=//"
# 	    return 0
# 	fi
#     done
# }

# defaultopt() {
#     echo $1
# }


################################################### OUTPUT FILES #####################################################

# Output images (in $WD): Magnitude  Magnitude_brain Magnitude_brain_mask FieldMap  
#         Plus the following if gradient distortion correction is run:
#                         Magnitude_gdc Magnitude_gdc_warp  Magnitude_brain_gdc FieldMap_gdc  
# Output images (not in $WD):  ${MagnitudeOutput}  ${MagnitudeBrainOutput}  ${FieldMapOutput}

################################################## OPTION PARSING #####################################################

# # Just give usage if no arguments specified
# if [ $# -eq 0 ] ; then Usage; exit 0; fi
# # check for correct options
# if [ $# -lt 5 ] ; then Usage; exit 1; fi

# # parse arguments
# WD=`getopt1 "--workingdir" $@`
# DistortionCorrection=`getopt1 "--method" $@`

case $DistortionCorrection in

    $SIEMENS_METHOD_OPT)

        # --------------------------------------
        # -- Siemens Gradient Echo Field Maps --
        # --------------------------------------
            if [[ $MagnitudeInputName == "" ||  $PhaseInputName == "" || $DeltaTE == ""]]
            then 
                log_Err_Abort "$DistortionCorrection method requires --fmapmag, --fmapphase, and --echodiff"
            fi
        ;;

    ${GENERAL_ELECTRIC_METHOD_OPT})

        # -----------------------------------------------
        # -- General Electric Gradient Echo Field Maps --
        # ----------------------------------------------- 

        if [[ $GEB0InputName == "" ]]
        then 
            log_Err_Abort "$DistortionCorrection method requires --fmap"
        fi
        ;;

    ${PHILIPS_METHOD_OPT})

        # --------------------------------------
        # -- Philips Gradient Echo Field Maps --
        # --------------------------------------
        if [[ $MagnitudeInputName == "" ||  $PhaseInputName == "" || $DeltaTE == ""]]
        then 
            log_Err_Abort "$DistortionCorrection method requires --fmapmag, --fmapphase, and --echodiff"
        fi
        ;;

    *)
        log_Err "Unable to create FSL-suitable readout distortion correction field map"
        log_Err_Abort "Unrecognized distortion correction method: ${DistortionCorrection}"
esac

# MagnitudeOutput=`getopt1 "--ofmapmag" $@`
# MagnitudeBrainOutput=`getopt1 "--ofmapmagbrain" $@`
# FieldMapOutput=`getopt1 "--ofmap" $@`
# GradientDistortionCoeffs=`getopt1 "--gdcoeffs" $@`

# default parameters
GlobalScripts=${HCPPIPEDIR_Global}
# WD=`defaultopt $WD .`
# GradientDistortionCoeffs=`defaultopt $GradientDistortionCoeffs "NONE"`

log_Msg "Field Map Preprocessing and Gradient Unwarping"
log_Msg "START"

mkdir -p $WD

# Record the input options in a log file
echo "$0 $@" >> $WD/log.txt
echo "PWD = `pwd`" >> $WD/log.txt
echo "date: `date`" >> $WD/log.txt
echo " " >> $WD/log.txt

########################################## DO WORK ########################################## 

case $DistortionCorrection in

    $SIEMENS_METHOD_OPT)

        # --------------------------------------
        # -- Siemens Gradient Echo Field Maps --
        # --------------------------------------

		    ${FSLDIR}/bin/fslmaths ${MagnitudeInputName} -Tmean ${WD}/Magnitude
		    ${FSLDIR}/bin/bet ${WD}/Magnitude ${WD}/Magnitude_brain -f 0.35 -m #Brain extract the magnitude image
		    ${FSLDIR}/bin/imcp ${PhaseInputName} ${WD}/Phase
		    ${FSLDIR}/bin/fsl_prepare_fieldmap SIEMENS ${WD}/Phase ${WD}/Magnitude_brain ${WD}/FieldMap ${DeltaTE}

        ;;

    ${GENERAL_ELECTRIC_METHOD_OPT})

        # -----------------------------------------------
        # -- General Electric Gradient Echo Field Maps --
        # ----------------------------------------------- 

        ${FSLDIR}/bin/fslsplit ${GEB0InputName}     # split image into vol0000=fieldmap and vol0001=magnitude
		    mv vol0000.nii.gz ${WD}/FieldMap_deg.nii.gz
		    mv vol0001.nii.gz ${WD}/Magnitude.nii.gz
		    ${FSLDIR}/bin/bet ${WD}/Magnitude ${WD}/Magnitude_brain -f 0.35 -m #Brain extract the magnitude image
		    ${FSLDIR}/bin/fslmaths ${WD}/FieldMap_deg.nii.gz -mul 6.28 ${WD}/FieldMap.nii.gz

        ;;

    ${PHILIPS_METHOD_OPT})

        # --------------------------------------
        # -- Philips Gradient Echo Field Maps --
        # --------------------------------------

		    ${FSLDIR}/bin/fslmaths ${MagnitudeInputName} -Tmean ${WD}/Magnitude
        # Brain extract the magnitude image
    		${FSLDIR}/bin/bet ${WD}/Magnitude ${WD}/Magnitude_brain -f 0.35 -m
    		${FSLDIR}/bin/fslmaths ${WD}/Magnitude_brain -ero ${WD}/Magnitude_brain_ero
    		rm ${WD}/Magnitude_brain.nii.gz
    		mv ${WD}/Magnitude_brain_ero.nii.gz ${WD}/Magnitude_brain.nii.gz

        # Create a binary brain mask
        ${FSLDIR}/bin/fslmaths ${WD}/Magnitude_brain.nii.gz -thr 0.00000001 -bin ${WD}/Mask_brain.nii.gz
        # Convert fieldmap to radians
        $FSLDIR/bin/fslmaths ${PhaseInputName} -mul 3.14159 -div 180 -mas ${WD}/Mask_brain.nii.gz ${WD}/FieldMap_rad -odt float
        # Unwrap fieldmap
        $FSLDIR/bin/prelude -p ${WD}/FieldMap_rad -a ${WD}/Magnitude_brain.nii.gz -m ${WD}/Mask_brain.nii.gz -o ${WD}/FieldMap_rad_unwrapped -v
        # Convert to rads/sec (DeltaTE is echo time difference)
        asym=`echo ${DeltaTE} / 1000 | bc -l`
        $FSLDIR/bin/fslmaths ${WD}/FieldMap_rad_unwrapped -div $asym ${WD}/FieldMap_rps -odt float
        # Call FUGUE to extrapolate from mask (fill holes, etc)
        $FSLDIR/bin/fugue --loadfmap=${WD}/FieldMap_rps --mask=${WD}/Mask_brain.nii.gz --savefmap=${WD}/FieldMap.nii.gz
        # Demean the image (avoid voxel translation)
        $FSLDIR/bin/fslmaths ${WD}/FieldMap.nii.gz -sub `${FSLDIR}/bin/fslstats ${WD}/FieldMap.nii.gz -k ${WD}/Mask_brain.nii.gz -P 50` -mas ${WD}/Mask_brain.nii.gz ${WD}/FieldMap.nii.gz -odt float

        ;;

    *)
        log_Err "Unable to create FSL-suitable readout distortion correction field map"
        log_Err_Abort "Unrecognized distortion correction method: ${DistortionCorrection}"
esac

log_Msg "DONE: fsl_prepare_fieldmap.sh"

if [ ! $GradientDistortionCoeffs = "NONE" ] ; then
  ${GlobalScripts}/GradientDistortionUnwarp.sh \
      --workingdir=${WD} \
      --coeffs=${GradientDistortionCoeffs} \
      --in=${WD}/Magnitude \
      --out=${WD}/Magnitude_gdc \
      --owarp=${WD}/Magnitude_gdc_warp
      
  ${FSLDIR}/bin/applywarp --rel --interp=nn -i ${WD}/Magnitude_brain -r ${WD}/Magnitude_brain -w ${WD}/Magnitude_gdc_warp -o ${WD}/Magnitude_brain_gdc
  ${FSLDIR}/bin/fslmaths ${WD}/Magnitude_gdc -mas ${WD}/Magnitude_brain_gdc ${WD}/Magnitude_brain_gdc
  ${FSLDIR}/bin/fslmaths ${WD}/Magnitude_brain_gdc -bin -ero -ero ${WD}/Magnitude_brain_gdc_ero
  ${FSLDIR}/bin/fslmaths ${WD}/FieldMap -mas ${WD}/Magnitude_brain_gdc_ero -dilM -dilM -dilM -dilM -dilM ${WD}/FieldMap_dil
  ${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/FieldMap_dil -r ${WD}/FieldMap_dil -w ${WD}/Magnitude_gdc_warp -o ${WD}/FieldMap_gdc
  ${FSLDIR}/bin/fslmaths ${WD}/FieldMap_gdc -mas ${WD}/Magnitude_brain_gdc ${WD}/FieldMap_gdc

  ${FSLDIR}/bin/imcp ${WD}/Magnitude_gdc ${MagnitudeOutput}
  ${FSLDIR}/bin/imcp ${WD}/Magnitude_brain_gdc ${MagnitudeBrainOutput}
  cp ${WD}/FieldMap_gdc.nii.gz ${FieldMapOutput}.nii.gz
else
  ${FSLDIR}/bin/imcp ${WD}/Magnitude ${MagnitudeOutput}
  ${FSLDIR}/bin/imcp ${WD}/Magnitude_brain ${MagnitudeBrainOutput}
  cp ${WD}/FieldMap.nii.gz ${FieldMapOutput}.nii.gz
fi

log_Msg "Field Map Preprocessing and Gradient Unwarping"
log_Msg "END"
echo " END: `date`" >> $WD/log.txt

########################################## QA STUFF ########################################## 

if [ -e $WD/qa.txt ] ; then rm -f $WD/qa.txt ; fi
echo "cd `pwd`" >> $WD/qa.txt
echo "# Check the brain extraction and distortion correction of the fieldmap magnitude image" >> $WD/qa.txt
echo "fslview ${WD}/Magnitude ${MagnitudeOutput} ${MagnitudeBrainOutput} -l Red -t 0.5" >> $WD/qa.txt
echo "# Check the range (largish values around 600 rad/s) and general smoothness/look of fieldmap (should be large in inferior/temporal areas mainly)" >> $WD/qa.txt
echo "fslview ${FieldMapOutput}" >> $WD/qa.txt

##############################################################################################

