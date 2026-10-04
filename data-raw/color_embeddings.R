## code to prepare `color_embeddings`/`color_lab` datasets goes here

#For individual embeddings
fp <- system.file("extdata", "color_embeddings_individual.csv", package="tripletTools")

tmp <- read.csv(fp, header = TRUE) #Read file
sjs <- unique(tmp$worker_id) #Get unique participants
nsj <- length(sjs) #Number of participants
o <- list() #Initialize output list

for(i in c(1:nsj)){
  o[[i]] <- subset(tmp, worker_id==sjs[i])   #Get current subject
  row.names(o[[i]]) <- o[[i]]$item #Name rows
  cnames <- grep("dim", names(tmp), value = T) #Pull out embedding columns
  o[[i]] <- o[[i]][,cnames] #Discard columns other than embedding coordinates
}

names(o) <- sjs
color_emb_ind <- o
rm(tmp, o)

usethis::use_data(color_emb_ind, overwrite = TRUE)

#For group embedding
fp <- system.file("extdata", "color_embeddings_group.csv", package="tripletTools")

tmp <- read.csv(fp, header = TRUE, row.names = 1) #First column is the item (hex color) code
color_emb_group <- tmp
rm(tmp)

usethis::use_data(color_emb_group, overwrite = TRUE)

#Reference CIE LAB coordinates for the color patches themselves (not a fitted
#embedding -- used as a comparison point for how the triplet embedding relates
#to standard, perceptually-based color space)
fp <- system.file("extdata", "color_lab.csv", package="tripletTools")
color_lab <- read.csv(fp, header = TRUE, row.names = 1)

usethis::use_data(color_lab, overwrite = TRUE)
