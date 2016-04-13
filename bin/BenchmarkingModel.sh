#! /bin/bash
# BenchmarkingModel.sh
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

#PBS -N BenchmarkingModel
#PBS -A pschloss_flux
#PBS -q flux
#PBS -l qos=flux
#PBS -l nodes=1:ppn=24,mem=124GB
#PBS -l walltime=100:00:00
#PBS -j oe
#PBS -V

#######################
# Set the Environment #
#######################

export WorkingDirectory=/scratch/pschloss_flux/ghannig/git/Hannigan-2016-ConjunctisViribus/data
export Output='BenchmarkingSet'
export BinPath=/scratch/pschloss_flux/ghannig/git/Hannigan-2016-ConjunctisViribus/bin/
export GitBin=/scratch/pschloss_flux/ghannig/git/OpenMetagenomeToolkit/bin/

export PhageGenomeRef=/scratch/pschloss_flux/ghannig/git/Hannigan-2016-ConjunctisViribus/data/ValidationSet/ValidationPhageNoBlockNoSpace.fa
export BacteriaGenomeRef=/scratch/pschloss_flux/ghannig/git/Hannigan-2016-ConjunctisViribus/data/ValidationSet/ValidationBacteriaNoBlockNoSpace.fa

cd ${WorkingDirectory} || exit
mkdir ./${Output}

###################
# Set Subroutines #
###################

PredictOrfs () {
	# 1 = Contig Fasta File for Prodigal
	# 2 = Output File Name

	bash ${BinPath}ProdigalWrapperLargeFiles.sh \
		"${1}" \
		./${Output}/tmp-genes.fa

    # Remove the block formatting
	perl \
	${GitBin}remove_block_fasta_format.pl \
		./${Output}/tmp-genes.fa \
		"${2}"

	sed -i 's/\*//g' "${2}"
	sed -i 's/\/n//g' "${2}"
}

FormatNames () {
	# 1 = Input file with names to be formatted
	# 2 = Output file name

	# Perl here because the regex are easierls
	perl -pe 's/ENA\S+\.\d_//g' "${1}" \
		| perl -pe 's/\,_\S+//g' \
		| perl -pe 's/_complete\S+//g' \
		| perl -pe 's/_chromosome\S+//g' \
		> "${2}"
}

# Export the subroutines
export -f PredictOrfs
export -f FormatNames

# ######################
# # Run CRISPR scripts #
# ######################

# # Use a tmp directory
# mkdir ./${Output}/tmp

# echo Extracting CRISPRs...
# bash ${BinPath}RunPilerCr.sh \
# 	${BacteriaGenomeRef} \
# 	./${Output}/tmp/BenchmarkCrisprs.txt \
# 	|| exit

# echo Getting CRISPR pairs...
# bash ${BinPath}GetCrisprPhagePairs.sh \
# 	./${Output}/tmp/BenchmarkCrisprs.txt \
# 	${PhageGenomeRef} \
# 	./${Output}/BenchmarkCrisprs.tsv \
# 	|| exit

# rm ./${Output}/tmp/*

# # Format the output
# bash FormatNames \
# 	./${Output}/BenchmarkCrisprs.tsv \
# 	./${Output}/BenchmarkCrisprsFormat.tsv

# #####################
# # Run BLAST scripts #
# #####################

# echo Getting prophages by blast...
# bash ${BinPath}GetProphagesByBlast.sh \
# 	${PhageGenomeRef} \
# 	${BacteriaGenomeRef} \
# 	./${Output}/BenchmarkProphages.tsv \
# 	${WorkingDirectory} \
# 	|| exit

# # Format the output
# bash FormatNames \
# 	./${Output}/BenchmarkProphages.tsv \
# 	./${Output}/BenchmarkProphagesFormat.tsv

# ################
# # Predict ORFs #
# ################

# echo Predicting ORFs...

# PredictOrfs \
# 	${PhageGenomeRef} \
# 	./${Output}/PhageReferenceOrfs.fa \
# 	|| exit

# PredictOrfs \
# 	${BacteriaGenomeRef} \
# 	./${Output}/BacteriaReferenceOrfs.fa \
# 	|| exit

# ####################
# # Run Pfam scripts #
# ####################

# echo Getting PFAM interactions...

# bash ${BinPath}PfamDomainInteractPrediction.sh \
# 	./${Output}/PhageReferenceOrfs.fa \
# 	./${Output}/BacteriaReferenceOrfs.fa \
# 	./${Output}/PfamInteractions.tsv \
# 	|| exit

# # Format the output
# bash FormatNames \
# 	./${Output}/PfamInteractions.tsv \
# 	./${Output}/PfamInteractionsFormat.tsv

#######################
# Run Uniprot scripts #
#######################

echo Getting Uniprot interactions...

bash ${BinPath}GetMicrobeOrfsBlast.sh \
	./${Output}/PhageReferenceOrfs.fa \
	./${Output}/BacteriaReferenceOrfs.fa \
	./${Output}/BenchmarkUniprotResults.tsv \
	${WorkingDirectory} \
	|| exit
