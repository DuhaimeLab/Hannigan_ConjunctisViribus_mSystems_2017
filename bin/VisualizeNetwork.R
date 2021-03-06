# VisualizeNetwork.R
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

##################
# Load Libraries #
##################
packagelist <- c("RNeo4j", "ggplot2", "wesanderson", "igraph", "visNetwork", "scales", "plyr", "cowplot", "reshape2")
new.packages <- packagelist[!(packagelist %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos='http://cran.us.r-project.org')
lapply(packagelist, library, character.only = TRUE)
library("ggraph")
library("grid")
library("stringr")

suppressMessages(c(
library("RNeo4j"),
library("ggplot2"),
library("C50"),
library("caret"),
library("wesanderson"),
library("plotROC"),
library("cowplot")
))

###################
# Set Subroutines #
###################

importgraphtodataframe <- function (
graphconnection=graph,
cypherquery=query,
filter=0) {
  write("Retrieving Cypher Query Results", stderr())
  # Use cypher to get the edges
  edges <- cypher(graphconnection, cypherquery)
  # Filter out nodes with fewer edges than specified
  if (filter > 0) {
    # Remove the edges to singleton nodes
    singlenodes <- ddply(edges, c("to"), summarize, length=length(to))
    # # Subset because the it is not visible with all small clusters
    # singlenodesremoved <- singlenodes[c(singlenodes$length > filter),]
    multipleedge <- edges[c(which(edges$to %in% singlenodesremoved$to)),]
  } else {
    multipleedge <- edges
  }
  # Set nodes
  nodes <- data.frame(id=unique(c(multipleedge$from, multipleedge$to)))
  nodes$label <- nodes$id
  return(list(nodes, multipleedge))
}

plotnetwork <- function (nodeframe=nodeout, edgeframe=edgeout) {
  write("Preparing Data for Plotting", stderr())
  # Pull out the data for clustering
  ig <- graph_from_data_frame(edgeout, directed=F)
  # Set plot paramters
  V(ig)$label <- ifelse(grepl("Bacteria", nodeout$id),
    "Bacteria",
    "Phage")
  V(ig)$type <- ifelse(grepl("Bacteria", nodeout$id),
    TRUE,
    FALSE)
  # Create the plot
  fres <- ggraph(ig, 'igraph', algorithm = 'bipartite') + 
        geom_edge_link0(edge_alpha = 0.0065) +
        geom_node_point(aes(color = label), size = 1.5, show.legend = FALSE) +
        ggforce::theme_no_axes() +
        scale_color_manual(values = wes_palette("Royal1")[c(2,4)]) +
        coord_flip() +
        annotate("text", x = 475, y = 0.85, label = "Phage", size = 6, color = wes_palette("Royal1")[c(4)]) +
        annotate("text", x = 25, y = 0.17, label = "Bacteria", size = 6, color = wes_palette("Royal1")[c(2)]) +
        theme_graph(border = FALSE)

  return(fres)
}

wplotnetwork <- function (nodeframe=nodeout, edgeframe=edgeout) {
  write("Preparing Data for Plotting", stderr())
  # Pull out the data for clustering
  ig <- graph_from_data_frame(edgeout, directed=F)
  # Set plot paramters
  V(ig)$label <- ifelse(grepl("Bacteria", nodeout$id),
    "Bacteria",
    "Phage")
  V(ig)$type <- ifelse(grepl("Bacteria", nodeout$id),
    TRUE,
    FALSE)
  V(ig)$weights <- nodeout$avg
  # Create the plot
  fres <- ggraph(ig, 'igraph', algorithm = 'bipartite') + 
        geom_edge_link0(edge_alpha = 0.01) +
        geom_node_point(aes(color = label, size = weights)) +
        ggforce::theme_no_axes() +
        scale_color_manual(values = wes_palette("Royal1")[c(2,4)]) +
        coord_flip() +
        theme(legend.position = "none")

  return(fres)
}

graphDiameter <- function (nodeframe=nodeout, edgeframe=edgeout) {
  write("Calculating Graph Diameter", stderr())  
  # Pull out the data for clustering
  ig <- graph_from_data_frame(edgeframe, directed=F)
  connectionresult <- diameter(ig, directed=F)
  vert <- vcount(ig)
  edge <- ecount(ig)
  finaldf <- t(as.data.frame(c(connectionresult, vert, edge)))
  rownames(finaldf) <- NULL
  colnames(finaldf) <- c("Diameter", "Vertices", "Edges")

  return(finaldf)
}

connectionstrength <- function (nodeframe=nodeout, edgeframe=edgeout) {
  write("Testing Connection Strength", stderr())  
  # Pull out the data for clustering
  ig <- graph_from_data_frame(edgeframe, directed=F)
  connectionresult <- is.connected(ig, mode="strong")
  if (!connectionresult) {
    connectionresult <- is.connected(ig, mode="weak")
      if (connectionresult) {
      result <- "RESULT: Graph is weakly connected."
    } else {
      result <- "RESULT: Graph is not weakly or strongly connected."
    }
  } else {
    result <- "RESULT: Graph is strongly connected."
  }
  return(result)
}

##############################
# Run Analysis & Save Output #
##############################

# Start the connection to the graph
# If you are getting a lack of permission, disable local permission on Neo4J
graph <- startGraph("http://localhost:7474/db/data/", "neo4j", "root")

# Use Cypher query to get a table of the table edges
query <- "
MATCH (n)-[r]->(m)
WHERE r.Prediction = 'Interacts'
RETURN n.Name AS from, m.Species AS to;
"

graphoutputlist <- importgraphtodataframe()
nodeout <- as.data.frame(graphoutputlist[1])
edgeout <- as.data.frame(graphoutputlist[2])
head(nodeout)
head(edgeout)

totalnetwork <- plotnetwork()

# Test connection strength of the network
write(connectionstrength(), stderr())

totalstats <- as.data.frame(graphDiameter())
totalstats$class <- "Total"

# Collect some stats for the data table
phagenodes <- length(grep("Phage", nodeout[,1]))
bactnodes <- length(grep("Bacteria", nodeout[,1]))
totaledges <- length(edgeout[,1])
nestats <- data.frame(cats = c("PhageNodes", "BacteriaNodes", "Edges"), values = c(phagenodes, bactnodes, totaledges))

# Diet subgraph
query <- "
MATCH
  (x:SRP002424)-->(y)-[d]->(z:Phage)-->(a:Bacterial_Host)<-[e]-(b),
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

graphoutputlist <- importgraphtodataframe()
nodeout <- as.data.frame(graphoutputlist[1])
edgeout <- as.data.frame(graphoutputlist[2])
# nodeout$order <- str_pad(row.names(nodeout), 4, pad = 0)
# pabund <- ddply(edgeout[,c(1,6)], "from", summarize, avg = median(PhageAbundance))
# babund <- ddply(edgeout[,c(2,7)], "to", summarize, avg = median(BacteriaAbundance))
# colnames(babund) <- c("from", "avg")
# rabund <- rbind(pabund, babund)
# nodeout <- merge(nodeout, rabund, by.x = "label", by.y = "from")
# nodeout <- nodeout[c(order(nodeout$order)),]
head(nodeout)
head(edgeout)

dietstats <- as.data.frame(graphDiameter())
dietstats$class <- "DietStudy"

dietnetwork <- plotnetwork()

# Twin subgraph
query <- "
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

graphoutputlist <- importgraphtodataframe()
nodeout <- as.data.frame(graphoutputlist[1])
edgeout <- as.data.frame(graphoutputlist[2])
# nodeout$order <- str_pad(row.names(nodeout), 4, pad = 0)
# pabund <- ddply(edgeout[,c(1,6)], "from", summarize, avg = median(PhageAbundance))
# babund <- ddply(edgeout[,c(2,7)], "to", summarize, avg = median(BacteriaAbundance))
# colnames(babund) <- c("from", "avg")
# rabund <- rbind(pabund, babund)
# nodeout <- merge(nodeout, rabund, by.x = "label", by.y = "from")
# nodeout <- nodeout[c(order(nodeout$order)),]
head(nodeout)
head(edgeout)

twinstats <- as.data.frame(graphDiameter())
twinstats$class <- "TwinStudy"

twinnetwork <- plotnetwork()

# Skin subgraph
# Import graphs into a list
skinsites <- c("Ax", "Ac", "Pa", "Tw", "Um", "Fh", "Ra")
# Start list
graphdf <- data.frame()

for (i in skinsites) {
  print(i)
  filename <- paste("./data/skingraph-", i, ".Rdata", sep = "")
  load(file = filename)
  graphdf <- rbind(graphdf, sampletable)
  rm(sampletable)
}

rm(i)

edgeout <- unique(graphdf[c(1:2)])

nodeout <- data.frame(id=unique(c(edgeout$from, edgeout$to)))
nodeout$label <- nodeout$id

# nodeout$order <- str_pad(row.names(nodeout), 4, pad = 0)
# pabund <- ddply(edgeout[,c(1,6)], "from", summarize, avg = median(PhageAbundance))
# babund <- ddply(edgeout[,c(2,7)], "to", summarize, avg = median(BacteriaAbundance))
# colnames(babund) <- c("from", "avg")
# rabund <- rbind(pabund, babund)
# nodeout <- merge(nodeout, rabund, by.x = "label", by.y = "from")
# nodeout <- nodeout[c(order(nodeout$order)),]
head(nodeout)
head(edgeout)

skinstats <- as.data.frame(graphDiameter())
skinstats$class <- "SkinStudy"

allstats <- rbind(totalstats, dietstats, twinstats, skinstats)
mstat <- melt(allstats)

legend <- get_legend(
  ggplot(mstat, aes(x = class, y = value, fill = class, group = class)) +
    theme_classic() +
    geom_bar(stat = "identity") +
    scale_fill_manual(values = wes_palette("Darjeeling"), name = "Study")
  )

so <- c("Total", "SkinStudy", "TwinStudy", "DietStudy")

mstat <- mstat[order(ordered(mstat$class, levels = so), decreasing = TRUE),]
mstat$class <- factor(mstat$class, levels = mstat$class)

counter <- 1
graphlist <- lapply(unique(mstat$variable), function(i) {
  print(counter)
  oplot <- ggplot(mstat[c(mstat$variable %in% i),], aes(x = class, y = value, fill = class, group = class)) +
    theme_classic() +
    geom_bar(stat = "identity") +
    theme(
        axis.line.x = element_line(colour = "black"),
        axis.line.y = element_line(colour = "black"),
        axis.title.y=element_blank(),
        axis.ticks.y=element_blank(),
        legend.position = "none"
    ) +
    scale_fill_manual(values = wes_palette("Darjeeling")) +
    ylab(i) +
    coord_flip()
    if (counter == 1) {
      oplot <- oplot
    } else {
      oplot <- oplot + theme(axis.text.y=element_text(colour = "white"))
    }
  # Double arrow for outer variable scope
  counter <<- counter + 1
  return(oplot)
})

baseplot <- plot_grid(plotlist = graphlist, nrow = 1, labels = LETTERS[5:7])
baseplot
withlegend <- plot_grid(
  baseplot,
  legend,
  nrow = 1,
  rel_widths = c(5, .75))

skinnetwork <- plotnetwork()

threeplot <- plot_grid(
  dietnetwork,
  twinnetwork,
  skinnetwork,
  ncol = 1,
  labels = c("B", "C", "D"))

almostplot <- plot_grid(totalnetwork, baseplot, ncol = 2, rel_widths = c(2,1), labels = c("A"))

finalplot <- plot_grid(almostplot, withlegend, nrow = 2, rel_heights = c(2,1))

write.table(allstats, file = "./rtables/genfigurestats.tsv", quote = FALSE, sep = "\t", row.names = FALSE, col.names = TRUE)
write.table(nestats, file = "./rtables/nestats.tsv", quote = FALSE, sep = "\t", row.names = FALSE, col.names = TRUE)

############# Add Prediction Model Stats #############
load(file="./data/rfinteractionmodel.RData")
load(file = "./data/exclusionplot.RData")

# I am not including a probability threshold here since this is not one ROC curve,
# but rather the average multiple generated ROC curves.
roclobster <- ggplot(outmodel$pred, aes(d = obs, m = NotInteracts)) +
  geom_roc(n.cuts = 0, color = wes_palette("Royal1")[2]) +
  style_roc() +
  theme(
    axis.line.x = element_line(colour = "black"),
    axis.line.y = element_line(colour = "black")
  ) +
  geom_segment(aes(x = 0, y = 0, xend = 1, yend = 1), linetype=2, colour=wes_palette("Royal1")[1])

vardf <- data.frame(varImp(outmodel$finalModel))
vardf$categories <- rownames(vardf)

vardf <- vardf[order(vardf$Overall, decreasing = TRUE),]
vardf$categories <- factor(vardf$categories, levels = vardf$categories)

importanceplot <- ggplot(vardf, aes(x=categories, y=Overall)) +
  theme_classic() +
  theme(
    axis.line.x = element_line(colour = "black"),
    axis.line.y = element_line(colour = "black")
  ) +
  geom_bar(stat="identity", fill=wes_palette("Royal1")[1]) +
  xlab("Categories") +
  ylab("Importance Score")

plothorz <- plot_grid(importanceplot, excludedgraph, ncol = 1, labels = c("B", "C"))
wgraph <- plot_grid(plothorz, totalnetwork, ncol = 2, labels = c("", "D"))
wroc <- plot_grid(roclobster, wgraph, ncol = 2, labels = c("A"))
baseplot <- plot_grid(plotlist = graphlist, nrow = 1, labels = LETTERS[5:7])
finalp <- plot_grid(wroc, baseplot, ncol = 1, rel_heights = c(2, 1))

pdf(file="./figures/rocCurves.pdf",
width=12,
height=10)
  finalp
dev.off()

modelper <- outmodel$results[(order(outmodel$results$ROC, decreasing = TRUE)),][1,]
write.table(modelper, file = "./rtables/genmodelper.tsv", quote = FALSE, sep = "\t", row.names = FALSE, col.names = TRUE)
