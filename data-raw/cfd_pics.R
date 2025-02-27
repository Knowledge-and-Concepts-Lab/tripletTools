## code to prepare `cfd_pics` dataset goes here

#require(png)

fp <- system.file("extdata", package = "tripletTools")

fnames <- list.files(path = paste0(fp, "/stimuli/"), pattern = ".png")

nfiles <- length(fnames)

cfd_pics <- list()

for(i in c(1:nfiles)) cfd_pics[[i]] <- png::readPNG(paste0(fp,"/stimuli/", fnames[i]))

names(cfd_pics) <- gsub(".png", "", fnames)

usethis::use_data(cfd_pics, overwrite = TRUE)
