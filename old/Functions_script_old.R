###############################################################################
# Define functions to be used for simulations
# Alex Lampert
#
# (1) psm()
#     Purpose: matches units using propensity score matching
#     
#     Arguments: 
#         X - design matrix, n X p
#         Y - outcome vector, p X 1
#         t - treatment assignment vector, p X 1
#         replacement - default is FALSE [optional]
#         k - number of nearest neighbors, default is 1 [optional]
#         cal - caliper option, default is FALSE [optional]
#         method - method to estimate propensity scores, options include:
#               logistic (default)
#               ensemble
#
#     Returns: 
#         1. estimated treatment effect
#         2. ASAM (average std diff)
#     
###############################################################################

library(MatchIt)

# propensity score matching
psm = function(X, Y, t, which.betas=c(1,2,3,4,5,6,7,8,9,10), true.pscores, k=1, method="logit") {
  
  # assemble dataframe 
  data = as.data.frame(cbind(t, Y, X))
  
  # formula
  betas = which.betas + 2 # X matrix begins in column 3 (X matrix doesn't include column of 1s)
  xnam = paste0("V", betas)
  (fmla.ps = as.formula(paste("V1 ~ ", paste(xnam, collapse= "+"))))
  (fmla.reg = as.formula(paste("V2 ~ V1 +", paste(xnam, collapse= "+"))))
  
  # match using logistic regression
  if (method == "logit") {
    
    #########################
    ### PS MATCHING + OLS ###
    #########################
    
    # unmatched treatment effect
    unmatched.delta = mean(Y[t==1]) - mean(Y[t==0]) 
    
    # test whether unmatched treatment effect significant
    unmatched.delta.p = t.test(Y[t==1], Y[t==0], conf.level=0.95)$p.value
    
    # match 
    out = matchit(fmla.ps, data=data, ratio=k)
    
    # add match flag to data
    data$w.m = out$weights
    
    # regression adjustment with matches
    lm = lm(fmla.reg, data=data, weights=w.m)
    delta = as.numeric(coef(lm)[2])
    
    ##########################
    ### PS WEIGHTING + OLS ###
    ##########################
    
    psw.true = cbind(Y, t)
    data$w.true = ifelse(psw.true[,2]==1, 1/true.pscores, 1/(1-true.pscores)) # true pscores
    
    # weighted delta (true weights)
    lm = lm(fmla.reg, data=data, weights=w.true)
    true.wgtd.delta = as.numeric(coef(lm)[2])
    
    # estimate pscores using logistic regression
    out.psw = glm(fmla.ps, data=data, family=binomial())
    est.pscores = predict(out.psw, type = "response")
    psw = cbind(t, est.pscores)
    
    # ATE weights:
    #   treatment weight = 1 / p
    #   control weight = 1 / (1-p)
    w.est = ifelse(psw[,1]==1, 1/psw[,2], 1/(1-psw[,2])) # estimated pscores
    
    # regression adjustment with weights
    lm = lm(fmla.reg, data=data, weights=w.est)
    wgtd.delta = as.numeric(coef(lm)[2])
    
    
    ################
    ### OLS only ###
    ################
    
    # regression without any data pre-processing
    lm = lm(fmla.reg, data=data)
    reg.delta = as.numeric(coef(lm)[2])
    
    # ridge penalization
    X = as.matrix(cbind(t, X))
    Y = as.matrix(Y)
    lambdas = 10^seq(3, -2, by = -.1)
    cv = cv.glmnet(X, Y, alpha = 1, lambda = lambdas)  
    m = glmnet(X, Y, alpha = 1, lambda = cv$lambda.min)
    ridge.delta = m$beta[1]
    
  }
  
  return(list(unmatched.delta=unmatched.delta, reg.delta=reg.delta, ridge.delta=ridge.delta,
              matched.delta=delta, wgtd.delta=wgtd.delta, true.wgtd.delta=true.wgtd.delta))
  
}
