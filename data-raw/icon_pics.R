## code to prepare `icon_pics` dataset goes here

#require(png)

fp <- system.file("extdata", package = "tripletTools")

fnames <- list.files(path = paste0(fp, "/stimuli/"), pattern = ".png")

nfiles <- length(fnames)

icon_pics <- list()

for(i in c(1:nfiles)) icon_pics[[i]] <- png::readPNG(paste0(fp,"/stimuli/", fnames[i]))

names(icon_pics) <- gsub(".png", "", fnames)

usethis::use_data(icon_pics, overwrite = TRUE)
