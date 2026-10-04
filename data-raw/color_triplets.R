## code to prepare `color_triplets` dataset goes here

#Path to raw data file
fp <- system.file("extdata", "color_triplets.csv", package = "tripletTools")
#Read raw data
tmp <- read.csv(fp, header = TRUE)

sjs <- unique(tmp$worker_id) #Get unique participants
nsj <- length(sjs) #Number of participants
o <- list() #Initialize output list

for(i in c(1:nsj)){
  o[[i]] <- subset(tmp, worker_id==sjs[i])   #Get current subject
}
names(o) <- sjs
color_triplets <- o
rm(tmp, o)

usethis::use_data(color_triplets, overwrite = TRUE)
