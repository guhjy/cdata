LightTests
================

``` r
library("cdata")
```

    ## Loading required package: wrapr

``` r
runTests <- function() {
  d <- data.frame(AUC = 0.6, R2 = 0.2)
  res1 <- unpivot_to_blocks(d,
                           nameForNewKeyColumn = 'meas',
                           nameForNewValueColumn = 'val',
                           columnsToTakeFrom = c('AUC', 'R2'))
  res1 <- res1[order(res1$meas), , drop=FALSE]
  testthat::expect_equivalent(data.frame(meas = c('AUC', 'R2'),
                                         val = c(0.6, 0.2),
                                         stringsAsFactors = FALSE),
                              res1)
  
  d <- data.frame(meas = c('AUC', 'R2'),
                  val = c(0.6, 0.2))
  res2 <- pivot_to_rowrecs(d,
                          columnToTakeKeysFrom = 'meas',
                          columnToTakeValuesFrom = 'val',
                          rowKeyColumns = c())
  res2 <- res2[, c("AUC", "R2"), drop = FALSE]
  testthat::expect_equivalent(data.frame(AUC = 0.6,
                                         R2 = 0.2,
                                         stringsAsFactors = FALSE),
                              res2)
  
  d <- data.frame(key = c('a', 'a'),
                  meas = c('AUC', 'R2'),
                  val = c(0.6, 0.2))
  res3 <- pivot_to_rowrecs(d,
                          columnToTakeKeysFrom = 'meas',
                          columnToTakeValuesFrom = 'val',
                          rowKeyColumns = c('key'))
  res3 <- res3[, c("key", "AUC", "R2"), drop = FALSE]
  testthat::expect_equivalent(data.frame(key = 'a',
                                         AUC = 0.6,
                                         R2 = 0.2,
                                         stringsAsFactors = FALSE),
                              res3)
  #list(res1 = res1, res2 = res2, res3 = res3)
}

runTests()

db <- DBI::dbConnect(RSQLite::SQLite(), 
                     ":memory:")
winvector_temp_db_handle <- list(db = db)
runTests()
winvector_temp_db_handle <- NULL
DBI::dbDisconnect(db)


winvector_temp_db_handle <- NULL
runTests()


db <- DBI::dbConnect(RPostgres::Postgres(),
                     host = 'localhost',
                     port = 5432,
                     user = 'postgres',
                     password = 'pg')
winvector_temp_db_handle <- list(db = db)
runTests()
winvector_temp_db_handle <- NULL
DBI::dbDisconnect(db)

db <- sparklyr::spark_connect(version='2.2.0', 
                                   master = "local")
```

    ## Warning in yaml.load(readLines(con), error.label = error.label, ...): R
    ## expressions in yaml.load will not be auto-evaluated by default in the near
    ## future

    ## Warning in yaml.load(readLines(con), error.label = error.label, ...): R
    ## expressions in yaml.load will not be auto-evaluated by default in the near
    ## future

    ## Warning in yaml.load(readLines(con), error.label = error.label, ...): R
    ## expressions in yaml.load will not be auto-evaluated by default in the near
    ## future

``` r
winvector_temp_db_handle <- list(db = db)
runTests()
winvector_temp_db_handle <- NULL
sparklyr::spark_disconnect(db)
```
