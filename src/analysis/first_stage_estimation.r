# In the file "first_stage_estimation.r", we regress the expropriation risk
# in the country on log mortality.



#
# The file requires to be called with a model specification as the argument,
# a corresponding json-file must exist in PATH_IN_MODEL_SPECS. That file
# needs to define a dictionary with keys:
#     
#     INSTD - the dependent variable (in the first stage)
#     INSTS - the instrument
#     KEEP_CONDITION - any sampling restrictions
#     DUMMIES - additional dummy variables to be used as controls
# 
# The r-file loops over various specifications with geographic controls /
# restrictions as defined in PATH_IN_MODEL_SPECS/geography.json. Finally,
# it stores a dataframe with estimation results.


rm(list=ls())
options(digits=3)

source("src/library/R/project_paths.r")
source(paste(PATH_IN_MODEL_CODE, "functions.r", sep="/"))

# Load required libraries.
library(foreign, lib=PATH_OUT_LIBRARY_R)
library(rjson, lib=PATH_OUT_LIBRARY_R)
library(sandwich, lib=PATH_OUT_LIBRARY_R)
library(zoo, lib=PATH_OUT_LIBRARY_R)
library(lmtest, lib=PATH_OUT_LIBRARY_R)
library(car, lib=PATH_OUT_LIBRARY_R)
library(aod, lib=PATH_OUT_LIBRARY_R)

# Load model and geographic specification.
model_name <- commandArgs(trailingOnly = TRUE)
model_json <- paste(model_name, "json", sep=".")
model <- fromJSON(file=paste(PATH_IN_MODEL_SPECS, model_json, sep="/"))
geography <- fromJSON(file=paste(PATH_IN_MODEL_SPECS, "geography.json", sep="/"))

# Initilize output dataframe for results.
results = data.frame(matrix(nrow = 7, ncol = 7))
row.names(results) <- c(
    "Log mortality($\\beta$)",
    "~~ \\{homoscedastic standard errors\\}",
    "~~ (heteroscedastic standard errors)",
    "~~ (heteroscedastic-clustered SE)",
    "p-value of log mortality",
    "p-value of indicators",
    "p-value of controls"
)

# Loop over geographical specifications.
for (i in 1:7) {

    # Load data
    data <- read.table(
        file = paste(PATH_OUT_DATA, "ajrcomment_all.txt", sep="/"),
        header = TRUE
    )

    # Implement model-specific restrictions.
    if (model$KEEP_CONDITION != "") {
        data <- subset(data, eval(parse(text = model$KEEP_CONDITION)))    
    }

    # Implement geographical constraints.
    GEO_COND <- paste("GEO_KEEP_CONDITION_", i, sep="")
    if (geography[[GEO_COND]] != "") {
        data <- subset(data, eval(parse(text = geography[[GEO_COND]])))
    }
    GEO_CONTROLS <- paste("GEO_CONTROLS_", i, sep="")

    # Set up variables for regression.
    y <- model$INSTD
    x <- model$INSTS
    dummies <- model$DUMMIES
    geo_controls <- geography[[GEO_CONTROLS]]

    # Set up regression formula.
    reg_formula <- as.formula(paste(y, " ~ ", x, dummies, geo_controls, sep=""))
    reg <- lm(reg_formula, data)

    # Store regression output that is the same across models.
    results[i, 1] = reg$coef[[2]] 
    results[i, 2] = sqrt(diag(vcov(reg))[2])
    results[i, 3] = summaryw(reg)[[1]][2,2]
    results[i, 4] = clx(fm = reg, dfcw = 1, cluster = data[ ,x])[[1]][2,2]
    
    # p-value of log mortality, based on the appropriate standard errors.
    if (model_name == "baseline" | model_name == "addindic") {
        results[i, 5] = clx(fm = reg, dfcw = 1, cluster = data[ ,x])[[1]][2,4]
    } else {
        results[i, 5] = summaryw(reg)[[1]][2,4]
    }
    # p-value of indicators.
    if (model_name == "addindic" | model_name == "rmconj_addindic" | model_name == "newdata") {
        results[i, 6] = wald.test(
            b = reg$coef,
            Sigma = clx(fm = reg, dfcw = 1, cluster = data[ ,x])[[2]], 
            Terms = 3:length(reg$coef), 
            df = reg$df
        )[[6]][[2]][4]        
    }
    # p-value of geographic controls.
    if (i != 1 & i != 3) {
        results[i, 7] = wald.test(
            b = reg$coef,
            Sigma = summaryw(reg)[[2]], 
            Terms = (length(reg$coef) - 1):length(reg$coef), 
            df = reg$df
        )[[6]][[2]][4]
    }
}

# Save data to disk.
write.table(
    results, 
    file = paste(
        PATH_OUT_ANALYSIS, 
        paste("first_stage_estimation_", model_name, ".txt", sep=""),
        sep = "/"
    )
)
