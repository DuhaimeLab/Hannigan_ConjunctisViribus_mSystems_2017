#! /bin/bash
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

# Run the perl script to create the benchmarking database
perl BenchmarkDatabaseCreation.pl \
	-c ../data/RunPhageBacteriaModel/BenchmarkCrisprsFormat.tsv \
	-b ../data/RunPhageBacteriaModel/BenchmarkProphagesFormatFlip.tsv \
	-p ../data/RunPhageBacteriaModel/PfamInteractionsFormatScoredFlip.tsv \
	-x ../data/RunPhageBacteriaModel/MatchesByBlastxFormatFlip.tsv \
	-v

perl ./Metadata2graph.pl \
	-s ../data/RunPhageBacteriaModel/ContigRelAbundForNetwork.tsv \
	-m ../data/ExampleMetadata.tsv
