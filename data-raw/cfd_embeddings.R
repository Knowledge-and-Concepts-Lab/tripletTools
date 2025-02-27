## code to prepare `cfd_embeddings` dataset.

fp <- system.file("extdata", "cfd36_embeddings_individual.csv", package="tripletTools")

tmp <- read.csv(fp, header = T) #Read file
sjs <- unique(tmp$worker_id) #Get unique participants
nsj <- length(sjs) #Number of participants
o <- list() #Initialize output list

for(i in c(1:nsj)){
  o[[i]] <- subset(tmp, worker_id==sjs[i])   #Get current subject
  row.names(o[[i]]) <- o[[i]]$file #Name rows
  cnames <- grep("dim", names(tmp), value = T) #Pull out embedding columns
  o[[i]] <- o[[i]][,cnames] #Discard columns other than embedding coordinates
}

names(o) <- sjs
cfd_embeddings <- o
rm(tmp, o)

usethis::use_data(cfd_embeddings, overwrite = TRUE)
