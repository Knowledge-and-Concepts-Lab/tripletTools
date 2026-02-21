function(x, y, nhopcl = 3, niter = 100){
  #Hold-out cross-validaton accuracy for binomial classifier
  #x: Matrix/data frame of predictors
  #y: Vector of binomila labels
  #nhopcl: Number of holdouts per class
  #niter: Number of iterations to run
  #returns: Vector of hold-out accuracies (proportion correct)
  ########

  o <- rep(NA, times = niter)
  for(i in c(1:niter)){
    s <- balanced.split(y)
    trn <- s[[1]]
    tst <- s[[2]]

    xtrn <- x[trn,]
    ytrn <- y[trn]

    xtst <- x[tst,]
    ytst <- y[tst]

    result <- test.binomial.classifier(xtrn, ytrn, xtst, ytst)
    o[i] <- result[1]
  }
  o
}
