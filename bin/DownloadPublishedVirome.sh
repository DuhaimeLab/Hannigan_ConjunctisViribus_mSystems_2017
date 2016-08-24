#! /bin/bash
# DownloadPublishedVirome.sh
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

module load samtools/1.2

#######################
# Set the Environment #
#######################

export Output='ViromePublications'

export Metadatafile=$1
export FastqFiles=/mnt/EXT/Schloss-data/ghannig/Hannigan-2016-ConjunctisViribus/data/PublishedViromeDatasets/raw

export fastx=/home/ghannig/bin/fastq_quality_trimmer

mkdir ./data/${Output}

###################
# Set Subroutines #
###################

DownloadFromSRA () {
	line="${1}"
	echo Processing SRA Accession Number "${line}"
	mkdir ./data/${Output}/"${line}"
	shorterLine=${line:0:3}
	shortLine=${line:0:6}
	echo Looking for ${shorterLine} with ${shortLine}
	# Recursively download the contents of the 
	wget -r --no-parent -A "*" ftp://ftp-trace.ncbi.nih.gov/sra/sra-instant/reads/ByStudy/sra/${shorterLine}/${shortLine}/${line}/
	mv ./ftp-trace.ncbi.nih.gov/sra/sra-instant/reads/ByStudy/sra/${shorterLine}/${shortLine}/${line}/*/*.sra ./data/${Output}/"${line}"
	rm -r ./ftp-trace.ncbi.nih.gov
}

DownloadFromMGRAST () {
	line="${1}"
	echo Processing MG-RAST Accession Number "${line}"
	mkdir ./data/${Output}/"${line}"
	# Download the raw information for the metagenomic run from MG-RAST
	wget -O ./data/${Output}/"${line}"/tmpout.txt "http://api.metagenomics.anl.gov/1/project/mgp${line}?verbosity=full"
	# Pasre the raw metagenome information for indv sample IDs
	sed 's/mgm/\nmgm/g' ./data/${Output}/"${line}"/tmpout.txt \
		| grep mgm \
		| grep -v http \
		| sed 's/\"\].*//' \
		> ./data/${Output}/"${line}"/SampleIDs.tsv
	# Get rid of the raw metagenome information now that we are done with it
	rm ./data/${Output}/"${line}"/tmpout.txt
	# Now loop through all of the accession numbers from the metagenome library
	while read acc; do
		echo Loading MG-RAST Sample ID is "${acc}"
		# file=050.1 means the raw input that the author meant to archive
		wget -O ./data/${Output}/"${line}"/"${acc}".fa "http://api.metagenomics.anl.gov/1/download/${acc}?file=050.1"
	done < ./data/${Output}/"${line}"/SampleIDs.tsv
	# Get rid of the sample list file
	rm ./data/${Output}/"${line}"/SampleIDs.tsv
}

DownloadFromMicrobe () {
	line="${1}"
	echo Processing iMicrobe Accession Number "${line}"
	mkdir ./data/${Output}/"${line}"
	wget ftp://ftp.imicrobe.us/projects/"${line}"/samples/*/*.fasta.gz
	mv ./*.fasta.gz ./data/${Output}/"${line}"
}

runFastx () {
	${fastx} -t 33 -Q 33 -l 75 -i "${1}" -o "${2}" || exit
	rm "${1}"
}

export -f DownloadFromSRA
export -f DownloadFromMGRAST
export -f DownloadFromMicrobe
export -f runFastx

# ############################
# # Run Through the Analysis #
# ############################

while read line; do
	# Save the sixth variable, which is the archive type (e.g. SRA, MG-RAST)
	ArchiveType=$(echo "${line}" | awk '{ print $6 }')
	# Save the seventh variable, which is the archive accession number
	AccNumber=$(echo "${line}" | awk '{ print $7 }')
	echo Processing ${AccNumber} in ${ArchiveType}
	# Now download the samples based on the archive type
	if [ "${ArchiveType}" == "SRA" ]; then
		DownloadFromSRA "${AccNumber}"
	elif [ "${ArchiveType}" == "MGRAST" ]; then
		DownloadFromMGRAST "${AccNumber}"
	elif [ "${ArchiveType}" == "iMicrobe" ]; then
		DownloadFromMicrobe "${AccNumber}"
	elif [ "${ArchiveType}" == "ArchiveSystem" ]; then
		echo Skipping file header.
	else
		echo Error in parsing accession numbers!
	fi
done < ${Metadatafile}

# mkdir ./data/${Output}/raw

# # unzip the files first
# ls ./data/${Output}/*/*.sra.gz | xargs -I {} --max-procs=16 sh -c '
# 	gunzip {}
# '

# ls ./data/${Output}/*/*.sra | xargs -I {} --max-procs=16 sh -c '
# 	echo Processing file {}...
# 	fastq-dump --split-3 {} --outdir ./data/${Output}/raw
# 	gzip {}
# '

# mkdir ./data/${Output}/qualityTrimmed

# ls ${FastqFiles} | xargs -I {} --max-procs=16 sh -c '
# 	runFastx \
# 			${FastqFiles}/{} \
# 			./data/${Output}/qualityTrimmed/{}
# '

# # Remove the now empty raw directory
# rm -r ./data/${Output}/raw
