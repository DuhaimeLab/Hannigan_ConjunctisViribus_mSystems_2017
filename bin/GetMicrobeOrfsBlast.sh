#! /bin/bash
# GetMicrobeOrfsBlast.sh
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

# Set the variables to be used in this script
export WorkingDirectory=${4}
export Output='tmp'

export InteractionReference=/scratch/pschloss_flux/ghannig/git/Hannigan-2016-ConjunctisViribus/data/PhageInteractionReference.tsv

export Reference=/scratch/pschloss_flux/ghannig/reference/Uniprot/Uniprot-BacteriaAndVirusNoBlock.fa

export GitBin=/scratch/pschloss_flux/ghannig/git/OpenMetagenomeToolkit/
export StudyBin=/scratch/pschloss_flux/ghannig/git/Hannigan-2016-ConjunctisViribus/bin/
export SchlossBin=/scratch/pschloss_flux/ghannig/bin/
export BlastPath=/scratch/pschloss_flux/ghannig/bin/ncbi-blast-2.3.0+/bin/

export PhageOrfs=${1}
export BacteriaOrfs=${2}
export OutputFile=${3}

# Make the output directory and move to the working directory
echo Creating output directory...
cd "${WorkingDirectory}" || exit
mkdir ./${Output}

GetOrfUniprotHits () {
	# 1 = UniprotFasta
	# 2 = Phage Orfs
	# 3 = Bacteria Orfs

	echo Making blast database...
	${BlastPath}makeblastdb \
		-dbtype prot \
		-in "${1}" \
		-out ./${Output}/UniprotSubsetDatabase

	# Use blast to get hits of ORFs to Uniprot genes
	echo Running Phage ORFs...
	${BlastPath}blastx \
    	-query "${2}" \
    	-out ./${Output}/PhageBlast.txt \
    	-db ./${Output}/UniprotSubsetDatabase \
    	-evalue 1e10 \
    	-num_threads 8 \
    	-outfmt 6

	echo Running Bacteria ORFs...
	${BlastPath}blastx \
    	-query "${3}" \
    	-out ./${Output}/BacteriaBlast.txt \
    	-db ./${Output}/UniprotSubsetDatabase \
    	-evalue 1e10 \
    	-num_threads 8 \
    	-outfmt 6
}

OrfInteractionPairs () {
	# 1 = Phage Blast Results
	# 2 = Bacterial Blast Results
	# 3 = Interaction Reference

	# Reverse the interaction reference for awk
	awk \
		'{ print $2"\t"$1 }' \
		"${3}" \
		> "${3}".inverse

	cat \
		"${3}" \
		"${3}".inverse \
		> ./${Output}/TotalInteractionRef.tsv

	# Get only the ORF IDs and corresponding interactions
	# Column 1 is the ORF ID, two is Uniprot ID
	cut -f 1,2 "${1}" | sed 's/\S\+|\(\S\+\)|\S\+$/\1/' > ./${Output}/PhageBlastIdReference.tsv
	cut -f 1,2 "${2}" | sed 's/\S\+|\(\S\+\)|\S\+$/\1/' > ./${Output}/BacteriaBlastIdReference.tsv

	# Convert bacterial file to reference
	awk \
		'NR == FNR {a[$2] = $1; next} $1 in a { print $1"\t"$2"\t"a[$1] }' \
		./${Output}/PhageBlastIdReference.tsv \
		./${Output}/TotalInteractionRef.tsv \
		> ./${Output}/tmpMerge.tsv

	awk \
		'NR == FNR {a[$2] = $1; next} $2 in a { print $1"\t"$2"\t"$3"\t"a[$2] }' \
		./${Output}/BacteriaBlastIdReference.tsv \
		./${Output}/tmpMerge.tsv \
		| cut -f 3,4 \
		> "${OutputFile}"

	# This output can be used for input into perl script for adding
	# to the graph database.
}

export -f GetOrfUniprotHits
export -f OrfInteractionPairs

GetOrfUniprotHits \
	${Reference} \
	"${PhageOrfs}" \
	"${BacteriaOrfs}"

OrfInteractionPairs \
	./${Output}/PhageBlast.txt \
	./${Output}/BacteriaBlast.txt \
	./${Output}/ParsedInteractionRef.tsv

