#!/bin/sh

# notes to self:
# need to update file paths in Template fsf and path to MNI152 standard brain

rootPath="/Users/eebiggs/Desktop/QAQC_Barcelona"
subj=(1001 1002 1004 1019 1021 2002 2022 2023 2028 2029 3005 3006 3010 3011 3016)

#Loop through subjects
for i in ${subj[@]}; do
	
	
	
	# Make preprocessed subdirectory
	mkdir -p "${rootPath}/derivatives/Preprocessed/sub-${i}/"
	# Copy FEAT template .fsf file
	cp "Template_Preprocessing.fsf" "${rootPath}/derivatives/Preprocessed/sub-${i}/sub-${i}_preprocessing.fsf"
	cd "${rootPath}/derivatives/Preprocessed/sub-${i}/"
	
	# Update participant number in template
	sed -i "" "s/sub-1001/sub-${i}/g" sub-${i}_preprocessing.fsf

	# T1 PROCESSING
	# Check for T1, if normal T1 not available then use BRAVO
	T1="${rootPath}/sub-${i}/ses-baseline/anat/sub-${i}_ses-baseline_T1w.nii.gz"
	if [ ! -f "${T1}" ]; then
		T1="${rootPath}/sub-${i}/ses-baseline/anat/sub-${i}_ses-baseline_acq-BRAVO_T1w.nii.gz"
	fi
	echo "T1 file: ${T1}"
	
	# T1 preprocessing
	fsl_anat --noseg --nosubcortseg -o "T1" -i ${T1}
	
	
	
	# FUNC PROCESSING
	# For now using only Rest 1, but need to adapt for any func input
	rest1="${rootPath}/sub-${i}/ses-baseline/func/sub-${i}_ses-baseline_task-rest_run-1_bold.nii.gz"
	
	# Check number of volumes
	nvols=`fslnvols ${rest1}`
	# Update FEAT template to correct number of volumes
	sed -i "" "s/set fmri(npts) 257/set fmri(npts) ${nvols}/" sub-${i}_preprocessing.fsf
	
	# Other parameters that would be better to read from the .json
	# Repetition time
	# Stanford: "RepetitionTime": 1.5
	# Cinci: "RepetitionTime": 1.5
	# Toronto: "RepetitionTime": 1.5
	tr="1.5"
	sed -i "" "s/set fmri(tr) 1.500000/set fmri(npts) ${tr}/" sub-${i}_preprocessing.fsf
	
	# Echo spacing
	# Stanford: "EffectiveEchoSpacing": 0.000608 divided by "ParallelReductionFactorInPlane": 2 (which is a field that doesn't always exist)
	# Cinci: "EstimatedEffectiveEchoSpacing": 0.000513575
	# Toronto: "EffectiveEchoSpacing": 0.000529996
	dwell="0.6"
	sed -i "" "s/set fmri(dwell) 0.6/set fmri(dwell) ${dwell}/" sub-${i}_preprocessing.fsf
	
	# Echo time
	# Stanford: "EchoTime": 0.03,
	# Cinci: "EchoTime": 0.035
	# Toronto: "EchoTime": 0.03
	te="30"
	sed -i "" "s/set fmri(te) 30/set fmri(te) ${te}/" sub-${i}_preprocessing.fsf
	
	
	
	# Fieldmap preprocessing for STANFORD data
	if [ ${i:0:1} == 1 ]; then
		
		# Check for B0 and magnitude
		fm="${rootPath}/sub-${i}/ses-baseline/fmap/sub-${i}_ses-baseline_fieldmap.nii.gz"
		mag="${rootPath}/sub-${i}/ses-baseline/fmap/sub-${i}_ses-baseline_magnitude.nii.gz"
		
		# If both files are found
		if [ -f ${fm} && -f ${mag} ]; then

			# convert fieldmap from Hz to rad/s
			fslmaths ${fm} -mul 6.28 "tmp_fieldmap_rad.nii.gz"
			# Mask magnitude image
			bet ${mag} "sub-${i}_ses-baseline_magnitude_preprocessed.nii.gz"
			# Smooth, despike, and median filter fieldmap
			fugue --loadfmap="tmp_fieldmap_rad.nii.gz" -m -s 1 --despike --savefmap="sub-${i}_ses-baseline_fieldmap_preprocessed.nii.gz"
		
		else
		
			echo "No fieldmap found for sub-${i}"
			# Update FEAT template to ignore unwarping
			sed -i "" "s/set fmri(regunwarp_yn) 1/set fmri(regunwarp_yn) 0/" sub-${i}_preprocessing.fsf
			continue
		
		fi
	fi
	
	
	
	# No unwarping for CINCI data
	if [ ${i:0:1} == 2 ]; then
		sed -i "" "s/set fmri(regunwarp_yn) 1/set fmri(regunwarp_yn) 0/" sub-${i}_preprocessing.fsf
	fi
	
	
	
	# Fieldmap preprocessing for TORONTO data
	if [ ${i:0:1} == 3 ]; then
		
		# Check for B0 and magnitude
		phase="${rootPath}/sub-${i}/fmap/sub-${i}_phasediff.nii.gz"
		mag="${rootPath}/sub-${i}/fmap/sub-${i}_magnitude1.nii.gz"
		
		# If both files are found
		if [ -f ${phase} && -f ${mag} ]; then
			
			# BET magnitude image
			bet ${mag} "sub-${i}_ses-baseline_magnitude_desc-preproc.nii.gz"
			# Prepare Siemens fieldmap (NB: echo time difference confirmed as 2.46 by EB)
			fsl_prepare_fieldmap "SIEMENS" ${phase} "sub-${i}_ses-baseline_magnitude_desc-preproc.nii.gz" "sub-${i}_ses-baseline_fieldmap.nii.gz" 2.46
			# Smooth, despike, and median filter fieldmap
			fugue --loadfmap="sub-${i}_ses-baseline_fieldmap.nii.gz" -m -s 1 --despike --savefmap="sub-${i}_ses-baseline_fieldmap_desc-preproc.nii.gz"
			# Set unwarping direction to y- (Stanford has y direction)
			sed -i "" "s/set fmri(unwarp_dir) y/set fmri(unwarp_dir) y-/" sub-${i}_preprocessing.fsf
			
		else
			
			echo "No fieldmap found for sub-${i}"
			# Update FEAT template to ignore unwarping
			sed -i "" "s/set fmri(regunwarp_yn) 1/set fmri(regunwarp_yn) 0/" sub-${i}_preprocessing.fsf
			continue
		
		fi
	
	fi
	
	
	
	# RUN FEAT PREPROCESSING
	feat sub-${i}_preprocessing.fsf
	
	
	
	# PREPROCESSED DATA QUALITY CHECK
	func_preproc="./sub-${i}.feat/filtered_func_data.nii.gz"
	
	# Calculate tSNR preprocessed data
	fslmaths ${func_preproc} -Tmean "tmp_mean.nii.gz"
	fslmaths ${func_preproc} -Tstd "tmp_std.nii.gz"
	fslmaths "tmp_mean.nii.gz" -div "tmp_std.nii.gz" "sub-${i}_ses-baseline_task-rest_run-1_desc-preproc_tSNR.nii.gz"
	rm tmp*.nii.gz
	
	# Transform to MNI
	applywarp --ref="/Users/eebiggs/fsl/data/standard/MNI152_T1_2mm_brain.nii.gz" \
		--in="sub-${i}_ses-baseline_task-rest_run-1_desc-preproc_tSNR.nii.gz" \
		--out="sub-${i}_ses-baseline_task-rest_run-1_space-MNI152_desc-preproc_tSNR.nii.gz" \
		--warp="./sub-${i}.feat/reg/highres2standard_warp.nii.gz" \
		--premat="./sub-${i}.feat/reg/example_func2highres.mat"
	
	# Calculate SFS preprocessed data
	# CSF mask, inverse transformed to native space and binarized
	flirt -in "TPM_CSF_mask_2mm.nii.gz" -ref ${func_preproc} -applyxfm \
		-init "./sub-${i}.feat/reg/standard2example_func.mat" \
		-out "sub-${i}_ses-baseline_space-native_label-TPM_CSF_mask.nii.gz"
	fslmaths "sub-${i}_ses-baseline_space-native_label-TPM_CSF_mask.nii.gz" -bin "sub-${i}_ses-baseline_space-native_label-TPM_CSF_mask.nii.gz"

	# (mean/global mean)
	global_mean=`fslstats ${func_preproc} -M`
	fslmaths ${func_preproc} -Tmean -div ${global_mean} tmp1
	# (std/CSF std)
	csf_std=`fslstats -K "sub-${i}_ses-baseline_space-native_label-TPM_CSF_mask.nii.gz" ${func_preproc} -S`
	fslmaths ${func_preproc} -Tstd -div ${csf_std} tmp2
	# (mean/global mean) X (std/CSF std)
	fslmaths tmp1 -mul tmp2 "sub-${i}_ses-baseline_task-rest_run-1_desc-preproc_SFS.nii.gz"
	rm tmp*.nii.gz
	
	# Transform to MNI
	applywarp --ref="/Users/eebiggs/fsl/data/standard/MNI152_T1_2mm_brain.nii.gz" \
		--in="sub-${i}_ses-baseline_task-rest_run-1_desc-preproc_SFS.nii.gz" \
		--out="sub-${i}_ses-baseline_task-rest_run-1_space-MNI152_desc-preproc_SFS.nii.gz" \
		--warp="./sub-${i}.feat/reg/highres2standard_warp.nii.gz" \
		--premat="./sub-${i}.feat/reg/example_func2highres.mat"

done