##################
# Load Libraries #
##################
packagelist <- c("RNeo4j", "ggplot2", "wesanderson", "igraph", "visNetwork", "scales", "plyr", "cowplot", "vegan", "reshape2")
new.packages <- packagelist[!(packagelist %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos='http://cran.us.r-project.org')
lapply(packagelist, library, character.only = TRUE)

##############################
# Run Analysis & Save Output #
##############################

# Start the connection to the graph
# If you are getting a lack of permission, disable local permission on Neo4J
graph <- startGraph("http://localhost:7474/db/data/", "neo4j", "root")

# Get list of the sample IDs
sampleidquery <- "
MATCH
	(x:SRP002523)-->(y)-[d]->(z:Phage)-->(a:Bacterial_Host)<-[e]-(b),
	(b)<--(i:PatientID)-->(y),
	(b)<--(t:TimePoint)-->(y),
	(k:Disease)-->(y)
WHERE toInt(d.Abundance) > 0
OR toInt(e.Abundance) > 0
RETURN DISTINCT
	z.Name AS from,
	a.Name AS to,
	i.Name AS PatientID,
	t.Name AS TimePoint,
	k.Name AS Diet,
	toInt(d.Abundance) AS PhageAbundance,
	toInt(e.Abundance) AS BacteriaAbundance;
"

sampletable <- as.data.frame(cypher(graph, sampleidquery))

head(sampletable)

# get subsampling depth
phageminseq <- min(ddply(sampletable, c("PatientID", "TimePoint"), summarize, sum = sum(PhageAbundance))$sum)
bacminseq <- min(ddply(sampletable, c("PatientID", "TimePoint"), summarize, sum = sum(BacteriaAbundance))$sum)

# Rarefy each sample using sequence counts
rout <- lapply(unique(sampletable$PatientID), function(i) {
	subsetdfout <- as.data.frame(sampletable[c(sampletable$PatientID %in% i),])
	outputin <- lapply(unique(subsetdfout$TimePoint), function(j) {
		subsetdfin <- subsetdfout[c(subsetdfout$TimePoint %in% j),]
		subsetdfin$PhageAbundance <- c(rrarefy(subsetdfin$PhageAbundance, sample = phageminseq))
		subsetdfin$BacteriaAbundance <- c(rrarefy(subsetdfin$BacteriaAbundance, sample = bacminseq))
		return(subsetdfin)
	})
	forresult <- as.data.frame(do.call(rbind, outputin))
	return(forresult)
})

# Finish making subsampled data frame
rdf <- as.data.frame(do.call(rbind, rout))
# Remove those without bacteria or phage nodes after subsampling
# Zero here means loss of the node
rdf <- rdf[!c(rdf$PhageAbundance == 0 | rdf$BacteriaAbundance == 0),]
# Calculate edge values from nodes
rdf$edge <- log10(rdf$PhageAbundance * rdf$BacteriaAbundance)

# Make a list of subgraphs for each of the samples
# This will be used for diversity, centrality, etc
routdiv <- lapply(unique(rdf$PatientID), function(i) {
	subsetdfout <- as.data.frame(rdf[c(rdf$PatientID %in% i),])
	outputin <- lapply(unique(subsetdfout$TimePoint), function(j) {
		subsetdfin <- subsetdfout[c(subsetdfout$TimePoint %in% j),]
		lapgraph <- graph_from_data_frame(subsetdfin[,c("to", "from")], directed = TRUE)
		E(lapgraph)$weight <- subsetdfin[,c("edge")]
		V(lapgraph)$timepoint <- j
		V(lapgraph)$patientid <- i
		diettype <- unique(subsetdfin$Diet)
		V(lapgraph)$diet <- diettype
		return(lapgraph)
	})
	return(outputin)
})

##### ALPHA DIVERSITY AND CENTRALITY #####

routcentral <- lapply(c(1:length(routdiv)), function(i) {
	listelement <- routdiv[[ i ]]
	outputin <- lapply(c(1:length(listelement)), function(j) {
		listgraph <- listelement[[ j ]]
		patient <- unique(V(listgraph)$patientid)
		tp <- unique(V(listgraph)$timepoint)
		diettype <- unique(V(listgraph)$diet)
		centraldf <- as.data.frame(alpha_centrality(listgraph, weights = E(listgraph)$weight))
		colnames(centraldf) <- "acentrality"
		pagerank <- as.data.frame(page_rank(listgraph, weights = E(listgraph)$weight, directed = FALSE)$vector)
		colnames(pagerank) <- "page_rank"
		pagerank$label <- rownames(pagerank)
		diversitydf <- as.data.frame(igraph::diversity(graph = listgraph, weights = E(listgraph)$weight))
		centraldf$label <- rownames(centraldf)
		colnames(diversitydf) <- "entropy"
		diversitydf$label <- rownames(diversitydf)
		centraldf <- merge(centraldf, diversitydf, by = "label")
		centraldf <- merge(centraldf, pagerank, by = "label")
		centraldf$subject <- patient
		centraldf$time <- tp
		centraldf$patientdiet <- diettype
		return(centraldf)
	})
	forresult <- as.data.frame(do.call(rbind, outputin))
	return(forresult)
})
rcentraldf <- as.data.frame(do.call(rbind, routcentral))
# Focus on the phages for this
rcentraldf <- rcentraldf[- grep("Bacteria", rcentraldf$label),]

# Add information for family and twins
rcentraldf$family <- gsub("[MT].*", "", rcentraldf$subject, perl = TRUE)
# Get whether they are a twin or mother
rcentraldf$person <- gsub("F\\d", "", rcentraldf$subject, perl = TRUE)

rcentraldfmothers <- rcentraldf[c(rcentraldf$person %in% "M"),]

alpha_centrality_boxplot <- ggplot(rcentraldf, aes(x = patientdiet, y = acentrality)) +
	theme_classic() +
	geom_boxplot(notch = TRUE, fill="gray") +
	ylab("Alpha Centrality")

wilcox.test(rcentraldf$acentrality ~ rcentraldf$patientdiet)

centrality_boxplot <- ggplot(rcentraldf, aes(x = patientdiet, y = page_rank)) +
	theme_classic() +
	geom_boxplot(notch = TRUE, fill="gray") +
	ylab("Alpha Centrality")

wilcox.test(rcentraldf$page_rank ~ rcentraldf$patientdiet)

centrality_boxplot <- ggplot(rcentraldf, aes(x = family, y = acentrality)) +
	theme_classic() +
	geom_boxplot(notch = TRUE, fill="gray") +
	ylab("Alpha Centrality")

pairwise.wilcox.test(rcentraldf$acentrality, rcentraldf$family)

# The obese mother has less connectivity than the
# other two mothers, which is pretty interesting.

pagerank_obesity <- ggplot(rcentraldfmothers, aes(x = patientdiet, y = page_rank)) +
	theme_classic() +
	geom_boxplot(notch = TRUE, fill="gray") +
	ylab("Alpha Centrality")

wilcox.test(rcentraldfmothers$page_rank ~ rcentraldfmothers$patientdiet)

##### Diameter #####
# This is a weighted diamter
diameterreading <- lapply(c(1:length(routdiv)), function(i) {
	listelement <- routdiv[[ i ]]
	outputin <- lapply(c(1:length(listelement)), function(j) {
		listgraph <- listelement[[ j ]]
		patient <- unique(V(listgraph)$patientid)
		tp <- unique(V(listgraph)$timepoint)
		diettype <- unique(V(listgraph)$diet)
		centraldf <- as.data.frame(diameter(listgraph, weights = E(listgraph)$weight))
		colnames(centraldf) <- "samplediamter"
		centraldf$subject <- patient
		centraldf$time <- tp
		centraldf$patientdiet <- diettype
		return(centraldf)
	})
	forresult <- as.data.frame(do.call(rbind, outputin))
	return(forresult)
})
diadf <- as.data.frame(do.call(rbind, diameterreading))

diameter_boxplot <- ggplot(diadf, aes(x = "AllSamples", y = samplediamter)) +
	theme_classic() +
	geom_jitter() +
	ylab("Weighted Diamter")

##### Beta Diversity #####
hamming_distance <- function(g1, g2) {
	intersection <- length(E(intersection(g1, g2)))
	length1 <- length(E(g1))
	length2 <- length(E(g2))
	return(1 - intersection / (length1 + length2 - intersection))
}

routham <- lapply(c(1:length(routdiv)), function(i) {
	listelement1 <- routdiv[[ i ]]
	outputin <- lapply(c(1:length(listelement1)), function(j) {
		listgraph1 <- listelement1[[ j ]]
		outdf1 <- lapply(c(1:length(routdiv)), function(k) {
			listelement2 <- routdiv[[ k ]]
				outdf2 <- lapply(c(1:length(listelement2)), function(l) {
					print(c(i,j,k,l))
					listgraph2 <- listelement2[[ l ]]
					patient1 <- unique(V(listgraph1)$patientid)
					patient2 <- unique(V(listgraph2)$patientid)
					patient1tp <- paste(unique(V(listgraph1)$patientid), unique(V(listgraph1)$timepoint), sep = "")
					patient2tp <- paste(unique(V(listgraph2)$patientid), unique(V(listgraph2)$timepoint), sep = "")
					diettype <- unique(V(listgraph1)$diet)
					hdistval <- hamming_distance(listgraph1, listgraph2)
					outdftop <- data.frame(patient1, patient2, diettype, patient1tp, patient2tp, hdistval)
					return(outdftop)
				})
			inresulttop <- as.data.frame(do.call(rbind, outdf2))
			return(inresulttop)
		})
		inresultmiddle <- as.data.frame(do.call(rbind, outdf1))
		return(inresultmiddle)
	})
	forresult <- as.data.frame(do.call(rbind, outputin))
	return(forresult)
})
routham <- as.data.frame(do.call(rbind, routham))
routhamnosame <- routham[!c(routham$hdistval == 0),]

routhamnosame$family1 <- gsub("[TM].*", "", routhamnosame$patient1, perl = TRUE)
routhamnosame$family2 <- gsub("[TM].*", "", routhamnosame$patient2, perl = TRUE)
routhamnosame$person1 <- gsub("F\\d", "", routhamnosame$patient1, perl = TRUE)
routhamnosame$person1 <- gsub("\\d", "", routhamnosame$person1, perl = TRUE)
routhamnosame$person2 <- gsub("F\\d", "", routhamnosame$patient2, perl = TRUE)
routhamnosame$person2 <- gsub("\\d", "", routhamnosame$person2, perl = TRUE)

# Look only at the twins
routhamnosame <- routhamnosame[c(routhamnosame$person1 %in% "T" & routhamnosame$person2 %in% "T"),]

routhamnosame$class <- ifelse(routhamnosame$family1 == routhamnosame$family2, "Intrafamily", "Interfamily")

intrabetadiv <- ggplot(routhamnosame, aes(x = class, y = hdistval)) +
	theme_classic() +
	geom_boxplot(notch = TRUE, fill="gray") +
	ylab("Hamming Distance")

wilcox.test(routhamnosame$hdistval ~ routhamnosame$class)

# Plot NMDS
routmatrixsub <- as.dist(dcast(routham[,c("patient1tp", "patient2tp", "hdistval")], formula = patient1tp ~ patient2tp, value.var = "hdistval")[,-1])
ORD_NMDS <- metaMDS(routmatrixsub,k=2)
ORD_FIT = data.frame(MDS1 = ORD_NMDS$points[,1], MDS2 = ORD_NMDS$points[,2])
ORD_FIT$SampleID <- rownames(ORD_FIT)

# Get metadata
routmetadata <- unique(routham[,c("patient1tp", "diettype")])
routmetadata$cutcol <- gsub("TP1", "", routmetadata$patient1tp, perl = TRUE)
routmetadata$family <- gsub("[TM].*", "", routmetadata$cutcol, perl = TRUE)
routmetadata$person <- gsub("F.", "", routmetadata$cutcol, perl = TRUE)
routmetadata$person <- gsub("\\d", "", routmetadata$person, perl = TRUE)
# Merge metadata
routmerge <- merge(ORD_FIT, routmetadata, by.x = "SampleID", by.y = "patient1tp")

routmerge <- routmerge[c(routmerge$person %in% "T"),]

plotnmds <- ggplot(routmerge, aes(x=MDS1, y=MDS2, colour=family)) +
    theme_classic() +
    geom_point() +
    scale_color_manual(values = wes_palette("Royal1")[c(1,2,4)])

# Calculate statistical significance
mod <- betadisper(routmatrixsub, routmerge[,length(routmerge)])
anova(mod)
permutest(mod, pairwise = TRUE)
mod.HSD <- TukeyHSD(mod)

moddf <- as.data.frame(mod.HSD$group)
moddf$comparison <- row.names(moddf)
limits <- aes(ymax = upr, ymin=lwr)
plotdiffs <- ggplot(moddf, aes(y=diff, x=comparison)) +
    theme_classic() +
    geom_pointrange(limits) +
    geom_hline(yintercept=0, linetype = "dashed") +
    coord_flip() +
    ylab("Differences in Mean Levels of Group") +
    xlab("")

pdf("./figures/obesity_network_difference.pdf", width = 5, height = 5)
	pagerank_obesity
dev.off()




