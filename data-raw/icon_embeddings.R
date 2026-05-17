## code to prepare `icon_embeddings` dataset.

#For individual embeddings
fp <- system.file("extdata", "icon_embeddings_individual.csv", package="tripletTools")

tmp <- read.csv(fp, header = TRUE) #Read file
sjs <- unique(tmp$worker_id) #Get unique participants
sjs <- sjs[sjs != "group"] #Exclude group-level embedding
nsj <- length(sjs) #Number of participants
o <- list() #Initialize output list

for(i in c(1:nsj)){
  o[[i]] <- subset(tmp, worker_id==sjs[i])   #Get current subject
  row.names(o[[i]]) <- o[[i]]$item #Name rows
  cnames <- grep("dim", names(tmp), value = T) #Pull out embedding columns
  o[[i]] <- o[[i]][,cnames] #Discard columns other than embedding coordinates
}

names(o) <- sjs
icon_emb_ind <- o
rm(tmp, o)

usethis::use_data(icon_emb_ind, overwrite = TRUE)

#For group embedding
fp <- system.file("extdata", "icon_embeddings_group.csv", package="tripletTools")

icon_emb_group <- read.csv(fp, header = TRUE)

usethis::use_data(icon_emb_group, overwrite = TRUE)

#Item information
fp <- system.file("extdata", "icon_items.csv", package="tripletTools")
icon_items <- read.csv(fp, header = TRUE)

usethis::use_data(icon_items, overwrite = TRUE)

