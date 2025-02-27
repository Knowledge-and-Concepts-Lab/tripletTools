## code to prepare `cfd_triplets` dataset goes here

#Path to raw data file
fp <- system.file("extdata", "cfd36_triplets_individual.csv", package = "tripletTools")
#Read raw data
tmp <- read.csv(fp, header = T)

sjs <- unique(tmp$worker_id) #Get unique participants
nsj <- length(sjs) #Number of participants
o <- list() #Initialize output list

for(i in c(1:nsj)){
  o[[i]] <- subset(tmp, worker_id==sjs[i])   #Get current subject
}
names(o) <- sjs
cfd_triplets <- o
rm(tmp, o)

usethis::use_data(cfd_triplets, overwrite = TRUE)
