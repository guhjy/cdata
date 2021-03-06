
# Contributed by John Mount jmount@win-vector.com , ownership assigned to Win-Vector LLC.
# Win-Vector LLC currently distributes this code without intellectual property indemnification, warranty, claim of fitness of purpose, or any other guarantee under a GPL3 license.

#' @importFrom wrapr %.>% let mapsyms
NULL


isSpark <- function(db) {
  if(is.null(db)) {
    return(FALSE)
  }
  length(intersect(c("spark_connection", "spark_shell_connection"),
            class(db)))>0
}

#' List columns of a table
#'
#' @param my_db DBI database connection
#' @param tableName character name of table
#' @return list of column names
#'
#' @examples
#'
#' my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' DBI::dbWriteTable(my_db,
#'                   'd',
#'                   data.frame(AUC = 0.6, R2 = 0.2, nope = -5),
#'                   overwrite = TRUE,
#'                   temporary = TRUE)
#' cols(my_db, 'd')
#' cT <- build_unpivot_control(
#'   nameForNewKeyColumn= 'meas',
#'   nameForNewValueColumn= 'val',
#'   columnsToTakeFrom= setdiff(cols(my_db, 'd'), "nope"))
#' print(cT)
#' tab <- rowrecs_to_blocks_q('d', cT, my_db = my_db)
#' qlook(my_db, tab)
#' DBI::dbDisconnect(my_db)
#'
#' @export
#'
cols <- function(my_db, tableName) {
  # comment out block fails intermitnently, and sometimes gives wrong results
  # filed as: https://github.com/tidyverse/dplyr/issues/3204
  # tryCatch(
  #   return(DBI::dbListFields(my_db, tableName)),
  #   error = function(e) { NULL })
  # below is going to have issues to to R-column name conversion!
  q <- paste0("SELECT * FROM ",
              DBI::dbQuoteIdentifier(my_db, tableName),
              " LIMIT 1")
  v <- DBI::dbGetQuery(my_db, q)
  colnames(v)
}

#' Quick look at remote data
#'
#' @param my_db DBI database handle
#' @param tableName name of table to look at
#' @param displayRows number of rows to sample
#' @param countRows logical, if TRUE return row count.
#' @return str-line view of data
#'
#' @examples
#'
#' my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' DBI::dbWriteTable(my_db,
#'                   'd',
#'                   data.frame(AUC = 0.6, R2 = 0.2),
#'                   overwrite = TRUE,
#'                   temporary = TRUE)
#' qlook(my_db, 'd')
#' DBI::dbDisconnect(my_db)
#'
#' @export
#'
qlook <- function(my_db, tableName,
                  displayRows = 10,
                  countRows = TRUE) {
  h <- DBI::dbGetQuery(my_db,
                       paste0("SELECT * FROM ",
                              DBI::dbQuoteIdentifier(my_db, tableName),
                              " LIMIT ", displayRows))
  cat(paste('table',
            DBI::dbQuoteIdentifier(my_db, tableName),
            paste(class(my_db), collapse = ' '),
            '\n'))
  if(countRows) {
    nrow <- DBI::dbGetQuery(my_db,
                            paste0("SELECT COUNT(1) FROM ",
                                   DBI::dbQuoteIdentifier(my_db, tableName)))[1,1, drop=TRUE]
    cat(paste(" nrow:", nrow, '\n'))
    if(nrow>displayRows) {
      cat(" NOTE: \"obs\" below is count of sample, not number of rows of data.\n")
    }
  } else {
    cat(" NOTE: \"obs\" below is count of sample, not number of rows of data.\n")
  }
  utils::str(h)
  invisible(NULL)
}



# confirm control table has uniqueness
checkControlTable <- function(controlTable, strict) {
  if(!is.data.frame(controlTable)) {
    return("control table must be a data.frame")
  }
  if(nrow(controlTable)<1) {
    return("control table must have at least 1 row")
  }
  if(ncol(controlTable)<1) {
    return("control table must have at least 1 column")
  }
  classes <- vapply(controlTable, class, character(1))
  if(!all(classes=='character')) {
    return("all control table columns must be character")
  }
  toCheck <- list(
    "column names" = colnames(controlTable),
    "group ids" = controlTable[, 1, drop=TRUE]
  )
  for(ci in names(toCheck)) {
    vals <- toCheck[[ci]]
    if(any(is.na(vals))) {
      return(paste("all control table", ci, "must not be NA"))
    }
    if(length(unique(vals))!=length(vals)) {
      return(paste("all control table", ci, "must be distinct"))
    }
    if(strict) {
      if(length(grep(".", vals, fixed=TRUE))>0) {
        return(paste("all control table", ci ,"must '.'-free"))
      }
      if(!all(vals==make.names(vals))) {
        return(paste("all control table", ci ,"must be valid R variable names"))
      }
    }
  }
  return(NULL) # good
}



#' Build a moveValuesToColumns*() control table that specifies a un-pivot (or "shred").
#'
#' Some discussion and examples can be found here:
#' \url{https://winvector.github.io/FluidData/FluidData.html} and
#' here \url{https://github.com/WinVector/cdata}.
#'
#' @param nameForNewKeyColumn character name of column to write new keys in.
#' @param nameForNewValueColumn character name of column to write new values in.
#' @param columnsToTakeFrom character array names of columns to take values from.
#' @param ... not used, force later args to be by name
#' @return control table
#'
#' @seealso \code{\link{rowrecs_to_blocks_q}}, \code{\link{rowrecs_to_blocks}}
#'
#' @examples
#'
#' build_unpivot_control("measurmentType", "measurmentValue", c("c1", "c2"))
#'
#' @export
build_unpivot_control <- function(nameForNewKeyColumn,
                                  nameForNewValueColumn,
                                  columnsToTakeFrom,
                                  ...) {
  if(length(list(...))>0) {
    stop("cdata::build_unpivot_control unexpected arguments.")
  }
  controlTable <- data.frame(x = as.character(columnsToTakeFrom),
                             y = as.character(columnsToTakeFrom),
                             stringsAsFactors = FALSE)
  colnames(controlTable) <- c(nameForNewKeyColumn, nameForNewValueColumn)
  controlTable
}




#' Map a set of columns to rows (query based, take name of table).
#'
#' Transform data facts from columns into additional rows using SQL
#' and controlTable.
#'
#' This is using the theory of "fluid data"n
#' (\url{https://github.com/WinVector/cdata}), which includes the
#' principle that each data cell has coordinates independent of the
#' storage details and storage detail dependent coordinates (usually
#' row-id, column-id, and group-id) can be re-derived at will (the
#' other principle is that there may not be "one true preferred data
#' shape" and many re-shapings of data may be needed to match data to
#' different algorithms and methods).
#'
#' The controlTable defines the names of each data element in the two notations:
#' the notation of the tall table (which is row oriented)
#' and the notation of the wide table (which is column oriented).
#' controlTable[ , 1] (the group label) cross colnames(controlTable)
#' (the column labels) are names of data cells in the long form.
#' controlTable[ , 2:ncol(controlTable)] (column labels)
#' are names of data cells in the wide form.
#' To get behavior similar to tidyr::gather/spread one builds the control table
#' by running an appropiate query over the data.
#'
#' Some discussion and examples can be found here:
#' \url{https://winvector.github.io/FluidData/FluidData.html} and
#' here \url{https://github.com/WinVector/cdata}.
#'
#' @param wideTable name of table containing data to be mapped (db/Spark data)
#' @param controlTable table specifying mapping (local data frame)
#' @param my_db db handle
#' @param ... force later arguments to be by name.
#' @param columnsToCopy character list of column names to copy
#' @param tempNameGenerator a tempNameGenerator from cdata::makeTempNameGenerator()
#' @param strict logical, if TRUE check control table contents for uniqueness
#' @param checkNames logical, if TRUE check names
#' @param showQuery if TRUE print query
#' @param defaultValue if not NULL literal to use for non-match values.
#' @param temporary logical, if TRUE make result temporary.
#' @param resultName character, name for result table.
#' @return long table built by mapping wideTable to one row per group
#'
#' @seealso \code{\link{build_unpivot_control}}, \code{\link{blocks_to_rowrecs_q}}
#'
#' @examples
#'
#' my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'
#' # un-pivot example
#' d <- data.frame(AUC = 0.6, R2 = 0.2)
#' DBI::dbWriteTable(my_db,
#'                   'd',
#'                   d,
#'                   overwrite = TRUE,
#'                   temporary = TRUE)
#' cT <- build_unpivot_control(nameForNewKeyColumn= 'meas',
#'                                nameForNewValueColumn= 'val',
#'                                columnsToTakeFrom= c('AUC', 'R2'))
#' tab <- rowrecs_to_blocks_q('d', cT, my_db = my_db)
#' qlook(my_db, tab)
#' DBI::dbDisconnect(my_db)
#'
#' @export
#'
rowrecs_to_blocks_q <- function(wideTable,
                                controlTable,
                                my_db,
                                ...,
                                columnsToCopy = NULL,
                                tempNameGenerator = makeTempNameGenerator('mvtrq'),
                                strict = FALSE,
                                checkNames = TRUE,
                                showQuery = FALSE,
                                defaultValue = NULL,
                                temporary = FALSE,
                                resultName = NULL) {
  if(length(list(...))>0) {
    stop("cdata::rowrecs_to_blocks_q unexpected arguments.")
  }
  if(length(columnsToCopy)>0) {
    if(!is.character(columnsToCopy)) {
      stop("rowrecs_to_blocks_q: columnsToCopy must be character")
    }
  }
  if((!is.character(wideTable))||(length(wideTable)!=1)) {
    stop("rowrecs_to_blocks_q: wideTable must be the name of a remote table")
  }
  controlTable <- as.data.frame(controlTable)
  cCheck <- checkControlTable(controlTable, strict)
  if(!is.null(cCheck)) {
    stop(paste("cdata::rowrecs_to_blocks_q", cCheck))
  }
  if(checkNames) {
    interiorCells <- as.vector(as.matrix(controlTable[,2:ncol(controlTable)]))
    interiorCells <- interiorCells[!is.na(interiorCells)]
    wideTableColnames <- cols(my_db, wideTable)
    badCells <- setdiff(interiorCells, wideTableColnames)
    if(length(badCells)>0) {
      stop(paste("cdata::rowrecs_to_blocks_q: control table entries that are not wideTable column names:",
                 paste(badCells, collapse = ', ')))
    }
  }
  ctabName <- tempNameGenerator()
  rownames(controlTable) <- NULL # just in case
  if(!isSpark(my_db)) {
    DBI::dbWriteTable(my_db,
                      ctabName,
                      controlTable,
                      overwrite = TRUE,
                      temporary = TRUE)
  } else {
    DBI::dbWriteTable(my_db,
                      ctabName,
                      controlTable,
                      temporary = TRUE)
  }
  if(is.null(resultName)) {
    resName <- tempNameGenerator()
  } else {
    resName = resultName
  }
  missingCaseTerm = "NULL"
  if(!is.null(defaultValue)) {
    if(is.numeric(defaultValue)) {
      missingCaseTerm <- as.character(defaultValue)
    } else {
      missingCaseTerm <- DBI::dbQuoteString(paste(as.character(defaultValue),
                                                  collapse = ' '))
    }
  }
  casestmts <- lapply(2:ncol(controlTable),
                      function(j) {
                        whens <- lapply(seq_len(nrow(controlTable)),
                                        function(i) {
                                          cij <- controlTable[i,j,drop=TRUE]
                                          if(is.null(cij) || is.na(cij)) {
                                            return(NULL)
                                          }
                                          paste0(' WHEN b.',
                                                 DBI::dbQuoteIdentifier(my_db, colnames(controlTable)[1]),
                                                 ' = ',
                                                 DBI::dbQuoteString(my_db, controlTable[i,1,drop=TRUE]),
                                                 ' THEN a.',
                                                 DBI::dbQuoteIdentifier(my_db, cij))
                                        })
                        whens <- as.character(Filter(function(x) { !is.null(x) },
                                                     whens))
                        if(length(whens)<=0) {
                          return(NULL)
                        }
                        casestmt <- paste0('CASE ',
                                           paste(whens, collapse = ' '),
                                           ' ELSE ',
                                           missingCaseTerm,
                                           ' END AS ',
                                           DBI::dbQuoteIdentifier(my_db, colnames(controlTable)[j]))
                      })
  casestmts <- as.character(Filter(function(x) { !is.null(x) },
                                   casestmts))
  copystmts <- NULL
  if(length(columnsToCopy)>0) {
    copystmts <- paste0('a.', DBI::dbQuoteIdentifier(my_db, columnsToCopy))
  }
  groupstmt <- paste0('b.', DBI::dbQuoteIdentifier(my_db, colnames(controlTable)[1]))
  # deliberate cross join
  qs <-  paste0(" SELECT ",
                paste(c(copystmts, groupstmt, casestmts), collapse = ', '),
                ' FROM ',
                DBI::dbQuoteIdentifier(my_db, wideTable),
                ' a CROSS JOIN ',
                DBI::dbQuoteIdentifier(my_db, ctabName),
                ' b ')
  q <-  paste0("CREATE ",
               ifelse(temporary, "TEMPORARY", ""),
               " TABLE ",
               DBI::dbQuoteIdentifier(my_db, resName),
               " AS ",
               qs)
  if(showQuery) {
    print(q)
  }
  tryCatch(
    # sparklyr didn't implement dbExecute(), so using dbGetQuery()
    DBI::dbGetQuery(my_db, q),
    warning = function(w) { NULL })
  resName
}


#' Map a set of columns to rows (takes a \code{data.frame}).
#'
#' Transform data facts from columns into additional rows controlTable.
#'
#' This is using the theory of "fluid data"n
#' (\url{https://github.com/WinVector/cdata}), which includes the
#' principle that each data cell has coordinates independent of the
#' storage details and storage detail dependent coordinates (usually
#' row-id, column-id, and group-id) can be re-derived at will (the
#' other principle is that there may not be "one true preferred data
#' shape" and many re-shapings of data may be needed to match data to
#' different algorithms and methods).
#'
#' The controlTable defines the names of each data element in the two notations:
#' the notation of the tall table (which is row oriented)
#' and the notation of the wide table (which is column oriented).
#' controlTable[ , 1] (the group label) cross colnames(controlTable)
#' (the column labels) are names of data cells in the long form.
#' controlTable[ , 2:ncol(controlTable)] (column labels)
#' are names of data cells in the wide form.
#' To get behavior similar to tidyr::gather/spread one builds the control table
#' by running an appropiate query over the data.
#'
#' Some discussion and examples can be found here:
#' \url{https://winvector.github.io/FluidData/FluidData.html} and
#' here \url{https://github.com/WinVector/cdata}.
#'
#' @param wideTable data.frame containing data to be mapped (in-memory data.frame).
#' @param controlTable table specifying mapping (local data frame).
#' @param ... force later arguments to be by name.
#' @param columnsToCopy character list of column names to copy
#' @param strict logical, if TRUE check control table contents for uniqueness
#' @param checkNames logical, if TRUE check names
#' @param showQuery if TRUE print query
#' @param defaultValue if not NULL literal to use for non-match values.
#' @param env environment to look for "winvector_temp_db_handle" in.
#' @return long table built by mapping wideTable to one row per group
#'
#' @seealso \code{\link{build_unpivot_control}}, \code{\link{blocks_to_rowrecs_q}}
#'
#' @examples
#'
#' # un-pivot example
#' d <- data.frame(AUC = 0.6, R2 = 0.2)
#' cT <- build_unpivot_control(nameForNewKeyColumn= 'meas',
#'                                nameForNewValueColumn= 'val',
#'                                columnsToTakeFrom= c('AUC', 'R2'))
#' tab <- rowrecs_to_blocks(d, cT)
#'
#'
#' @export
#'
rowrecs_to_blocks <- function(wideTable,
                              controlTable,
                              ...,
                              columnsToCopy = NULL,
                              strict = FALSE,
                              checkNames = TRUE,
                              showQuery = FALSE,
                              defaultValue = NULL,
                              env = parent.frame()) {
  if(length(list(...))>0) {
    stop("cdata::rowrecs_to_blocks unexpected arguments.")
  }
  wtname <- "cata_wide_tmp"
  need_close <- FALSE
  db_handle <- base::mget("winvector_temp_db_handle",
                          envir = env,
                          ifnotfound = list(NULL),
                          inherits = TRUE)[[1]]
  if(is.null(db_handle)) {
    my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    need_close = TRUE
  } else {
    my_db <- db_handle$db
  }
  rownames(wideTable) <- NULL # just in case
  if(!isSpark(my_db)) {
    DBI::dbWriteTable(my_db,
                      wtname,
                      wideTable,
                      overwrite = TRUE,
                      temporary = TRUE)
  } else {
    DBI::dbWriteTable(my_db,
                      wtname,
                      wideTable,
                      temporary = TRUE)
  }
  resName <- rowrecs_to_blocks_q(wideTable = wtname,
                                 controlTable = controlTable,
                                 my_db = my_db,
                                 columnsToCopy = columnsToCopy,
                                 tempNameGenerator = makeTempNameGenerator('mvtrq'),
                                 strict = strict,
                                 checkNames = checkNames,
                                 showQuery = showQuery,
                                 defaultValue = defaultValue)
  resData <- DBI::dbGetQuery(my_db, paste("SELECT * FROM", resName))
  x <- DBI::dbExecute(my_db, paste("DROP TABLE", wtname))
  x <- DBI::dbExecute(my_db, paste("DROP TABLE", resName))
  if(need_close) {
    DBI::dbDisconnect(my_db)
  }
  resData
}



#' Build a moveValuesToColumns*() control table that specifies a pivot (query based, takes name of table).
#'
#' Some discussion and examples can be found here: \url{https://winvector.github.io/FluidData/FluidData.html}.
#'
#' @param tableName Name of table to scan for new column names.
#' @param columnToTakeKeysFrom character name of column build new column names from.
#' @param columnToTakeValuesFrom character name of column to get values from.
#' @param my_db db handle
#' @param ... not used, force later args to be by name
#' @param prefix column name prefix (only used when sep is not NULL)
#' @param sep separator to build complex column names.
#' @return control table
#'
#' @seealso \code{\link{blocks_to_rowrecs_q}}
#'
#' @examples
#'
#' my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' d <- data.frame(measType = c("wt", "ht"),
#'                 measValue = c(150, 6),
#'                 stringsAsFactors = FALSE)
#' DBI::dbWriteTable(my_db,
#'                   'd',
#'                   d,
#'                   overwrite = TRUE,
#'                   temporary = TRUE)
#' build_pivot_control_q('d', 'measType', 'measValue',
#'                                  my_db = my_db,
#'                                  sep = '_')
#' DBI::dbDisconnect(my_db)
#'
#' @export
build_pivot_control_q <- function(tableName,
                                  columnToTakeKeysFrom,
                                  columnToTakeValuesFrom,
                                  my_db,
                                  ...,
                                  prefix = columnToTakeKeysFrom,
                                  sep = NULL) {
  if(length(list(...))>0) {
    stop("cdata::build_pivot_control_q unexpected arguments.")
  }
  q <- paste0("SELECT ",
              DBI::dbQuoteIdentifier(my_db, columnToTakeKeysFrom),
              " FROM ",
              DBI::dbQuoteIdentifier(my_db, tableName),
              " GROUP BY ",
              DBI::dbQuoteIdentifier(my_db, columnToTakeKeysFrom))
  controlTable <- DBI::dbGetQuery(my_db, q)
  controlTable[[columnToTakeKeysFrom]] <- as.character(controlTable[[columnToTakeKeysFrom]])
  controlTable[[columnToTakeValuesFrom]] <- controlTable[[columnToTakeKeysFrom]]
  if(!is.null(sep)) {
    controlTable[[columnToTakeValuesFrom]] <- paste(prefix,
                                                    controlTable[[columnToTakeValuesFrom]],
                                                    sep=sep)
  }
  controlTable
}



#' Build a moveValuesToColumns*() control table that specifies a pivot from a \code{data.frame}.
#'
#' Some discussion and examples can be found here: \url{https://winvector.github.io/FluidData/FluidData.html}.
#'
#' @param table data.frame to scan for new column names (in-memory data.frame).
#' @param columnToTakeKeysFrom character name of column build new column names from.
#' @param columnToTakeValuesFrom character name of column to get values from.
#' @param ... not used, force later args to be by name
#' @param prefix column name prefix (only used when sep is not NULL)
#' @param sep separator to build complex column names.
#' @param env environment to look for "winvector_temp_db_handle" in.
#' @return control table
#'
#' @seealso \code{\link{blocks_to_rowrecs_q}}
#'
#' @examples
#'
#' d <- data.frame(measType = c("wt", "ht"),
#'                 measValue = c(150, 6),
#'                 stringsAsFactors = FALSE)
#' build_pivot_control(d,
#'                         'measType', 'measValue',
#'                         sep = '_')
#'
#' @export
build_pivot_control <- function(table,
                                columnToTakeKeysFrom,
                                columnToTakeValuesFrom,
                                ...,
                                prefix = columnToTakeKeysFrom,
                                sep = NULL,
                                env = parent.frame()) {
  if(length(list(...))>0) {
    stop("cdata::build_pivot_control unexpected arguments.")
  }
  need_close <- FALSE
  db_handle <- base::mget("winvector_temp_db_handle",
                          envir = env,
                          ifnotfound = list(NULL),
                          inherits = TRUE)[[1]]
  if(is.null(db_handle)) {
    my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    need_close = TRUE
  } else {
    my_db <- db_handle$db
  }
  ptabtmpnam <- "cdata_build_pc_tmp"
  rownames(table) <- NULL # just in case
  if(!isSpark(my_db)) {
    DBI::dbWriteTable(my_db,
                      ptabtmpnam,
                      table,
                      overwrite = TRUE,
                      temporary = TRUE)
  } else {
    DBI::dbWriteTable(my_db,
                      ptabtmpnam,
                      table,
                      temporary = TRUE)
  }
  res <- build_pivot_control_q(tableName = ptabtmpnam,
                               columnToTakeKeysFrom = columnToTakeKeysFrom,
                               columnToTakeValuesFrom = columnToTakeValuesFrom,
                               my_db = my_db,
                               prefix = prefix,
                               sep = sep)
  x <- DBI::dbExecute(my_db, paste("DROP TABLE", ptabtmpnam))
  if(need_close) {
    DBI::dbDisconnect(my_db)
  }
  res
}



#' Map sets rows to columns (query based, take name of table).
#'
#' Transform data facts from rows into additional columns using SQL
#' and controlTable.
#'
#' This is using the theory of "fluid data"n
#' (\url{https://github.com/WinVector/cdata}), which includes the
#' principle that each data cell has coordinates independent of the
#' storage details and storage detail dependent coordinates (usually
#' row-id, column-id, and group-id) can be re-derived at will (the
#' other principle is that there may not be "one true preferred data
#' shape" and many re-shapings of data may be needed to match data to
#' different algorithms and methods).
#'
#' The controlTable defines the names of each data element in the two notations:
#' the notation of the tall table (which is row oriented)
#' and the notation of the wide table (which is column oriented).
#' controlTable[ , 1] (the group label) cross colnames(controlTable)
#' (the column labels) are names of data cells in the long form.
#' controlTable[ , 2:ncol(controlTable)] (column labels)
#' are names of data cells in the wide form.
#' To get behavior similar to tidyr::gather/spread one builds the control table
#' by running an appropiate query over the data.
#'
#' Some discussion and examples can be found here:
#' \url{https://winvector.github.io/FluidData/FluidData.html} and
#' here \url{https://github.com/WinVector/cdata}.
#'
#' @param tallTable name of table containing data to be mapped (db/Spark data)
#' @param keyColumns character list of column defining row groups
#' @param controlTable table specifying mapping (local data frame)
#' @param my_db db handle
#' @param ... force later arguments to be by name.
#' @param columnsToCopy character list of column names to copy
#' @param tempNameGenerator a tempNameGenerator from cdata::makeTempNameGenerator()
#' @param strict logical, if TRUE check control table contents for uniqueness
#' @param checkNames logical, if TRUE check names
#' @param showQuery if TRUE print query
#' @param defaultValue if not NULL literal to use for non-match values.
#' @param dropDups logical if TRUE supress duplicate columns (duplicate determined by name, not content).
#' @param temporary logical, if TRUE make result temporary.
#' @param resultName character, name for result table.
#' @return wide table built by mapping key-grouped tallTable rows to one row per group
#'
#' @seealso \code{\link{rowrecs_to_blocks_q}}, \code{\link{build_pivot_control_q}}
#'
#' @examples
#'
#' my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' # pivot example
#' d <- data.frame(meas = c('AUC', 'R2'), val = c(0.6, 0.2))
#' DBI::dbWriteTable(my_db,
#'                   'd',
#'                   d,
#'                   temporary = TRUE)
#' cT <- build_pivot_control_q('d',
#'                                        columnToTakeKeysFrom= 'meas',
#'                                        columnToTakeValuesFrom= 'val',
#'                                        my_db = my_db)
#' tab <- blocks_to_rowrecs_q('d',
#'                                      keyColumns = NULL,
#'                                      controlTable = cT,
#'                                      my_db = my_db)
#' qlook(my_db, tab)
#' DBI::dbDisconnect(my_db)
#'
#' @export
#'
blocks_to_rowrecs_q <- function(tallTable,
                                keyColumns,
                                controlTable,
                                my_db,
                                ...,
                                columnsToCopy = NULL,
                                tempNameGenerator = makeTempNameGenerator('mvtcq'),
                                strict = FALSE,
                                checkNames = TRUE,
                                showQuery = FALSE,
                                defaultValue = NULL,
                                dropDups = FALSE,
                                temporary = FALSE,
                                resultName = NULL) {
  if(length(list(...))>0) {
    stop("cdata::blocks_to_rowrecs_q unexpected arguments.")
  }
  if(length(keyColumns)>0) {
    if(!is.character(keyColumns)) {
      stop("blocks_to_rowrecs_q: keyColumns must be character")
    }
  }
  if(length(columnsToCopy)>0) {
    if(!is.character(columnsToCopy)) {
      stop("blocks_to_rowrecs_q: columnsToCopy must be character")
    }
  }
  if((!is.character(tallTable))||(length(tallTable)!=1)) {
    stop("blocks_to_rowrecs_q: tallTable must be the name of a remote table")
  }
  controlTable <- as.data.frame(controlTable)
  cCheck <- checkControlTable(controlTable, strict)
  if(!is.null(cCheck)) {
    stop(paste("cdata::blocks_to_rowrecs_q", cCheck))
  }
  if(checkNames) {
    tallTableColnames <- cols(my_db, tallTable)
    badCells <- setdiff(colnames(controlTable), tallTableColnames)
    if(length(badCells)>0) {
      stop(paste("cdata::blocks_to_rowrecs_q: control table column names that are not tallTable column names:",
                 paste(badCells, collapse = ', ')))
    }
  }
  ctabName <- tempNameGenerator()
  rownames(controlTable) <- NULL # just in case
  if(!isSpark(my_db)) {
    DBI::dbWriteTable(my_db,
                      ctabName,
                      controlTable,
                      overwrite = TRUE,
                      temporary = TRUE)
  } else {
    DBI::dbWriteTable(my_db,
                      ctabName,
                      controlTable,
                      temporary = TRUE)
  }
  if(is.null(resultName)) {
    resName <- tempNameGenerator()
  } else {
    resName = resultName
  }
  missingCaseTerm = "NULL"
  if(!is.null(defaultValue)) {
    if(is.numeric(defaultValue)) {
      missingCaseTerm <- as.character(defaultValue)
    } else {
      missingCaseTerm <- DBI::dbQuoteString(paste(as.character(defaultValue),
                                                  collapse = ' '))
    }
  }
  collectstmts <- vector(mode = 'list',
                         length = nrow(controlTable) * (ncol(controlTable)-1))
  collectN <- 1
  saw <- list()
  for(i in seq_len(nrow(controlTable))) {
    for(j in 2:ncol(controlTable)) {
      cij <- controlTable[i,j,drop=TRUE]
      if((!is.null(cij))&&(!is.na(cij))) {
        if(dropDups && (cij %in% names(saw))) {
          cij <- NA
        }
      }
      if((!is.null(cij))&&(!is.na(cij))) {
        collectstmts[[collectN]] <- paste0("MAX( CASE WHEN ", # pseudo aggregator
                                           "a.",
                                           DBI::dbQuoteIdentifier(my_db, colnames(controlTable)[[1]]),
                                           " = ",
                                           DBI::dbQuoteString(my_db, controlTable[i,1,drop=TRUE]),
                                           " THEN a.",
                                           DBI::dbQuoteIdentifier(my_db, colnames(controlTable)[[j]]),
                                           " ELSE ",
                                           missingCaseTerm,
                                           " END ) ",
                                           DBI::dbQuoteIdentifier(my_db, cij))
        saw[[cij]] <- TRUE
      }
      collectN <- collectN + 1
    }
  }
  # turn non-nulls into an array
  collectstmts <- as.character(Filter(function(x) { !is.null(x) },
                                      collectstmts))
  # pseudo-aggregators for columns we are copying
  # paste works on vectors in alligned fashion (not as a cross-product)
  copystmts <- NULL
  if(length(columnsToCopy)>0) {
    copystmts <- paste0('MAX(a.',
                        DBI::dbQuoteIdentifier(my_db, columnsToCopy),
                        ') ',
                        DBI::dbQuoteIdentifier(my_db, columnsToCopy))
  }
  groupterms <- NULL
  groupstmts <- NULL
  if(length(keyColumns)>0) {
    groupterms <- paste0('a.', DBI::dbQuoteIdentifier(my_db, keyColumns))
    groupstmts <- paste0('a.',
                         DBI::dbQuoteIdentifier(my_db, keyColumns),
                         ' ',
                         DBI::dbQuoteIdentifier(my_db, keyColumns))
  }
  # deliberate cross join
  qs <-  paste0(" SELECT ",
                paste(c(groupstmts, copystmts, collectstmts), collapse = ', '),
                ' FROM ',
                DBI::dbQuoteIdentifier(my_db, tallTable),
                ' a ')
  if(length(groupstmts)>0) {
    qs <- paste0(qs,
                 'GROUP BY ',
                 paste(groupterms, collapse = ', '))
  }
  q <-  paste0("CREATE ",
               ifelse(temporary, "TEMPORARY", ""),
               " TABLE ",
               DBI::dbQuoteIdentifier(my_db, resName),
               " AS ",
               qs)
  if(showQuery) {
    print(q)
  }
  tryCatch(
    # sparklyr didn't implement dbExecute(), so using dbGetQuery()
    DBI::dbGetQuery(my_db, q),
    warning = function(w) { NULL })
  resName
}


#' Map sets rows to columns (takes a \code{data.frame}).
#'
#' Transform data facts from rows into additional columns using controlTable.
#'
#' This is using the theory of "fluid data"n
#' (\url{https://github.com/WinVector/cdata}), which includes the
#' principle that each data cell has coordinates independent of the
#' storage details and storage detail dependent coordinates (usually
#' row-id, column-id, and group-id) can be re-derived at will (the
#' other principle is that there may not be "one true preferred data
#' shape" and many re-shapings of data may be needed to match data to
#' different algorithms and methods).
#'
#' The controlTable defines the names of each data element in the two notations:
#' the notation of the tall table (which is row oriented)
#' and the notation of the wide table (which is column oriented).
#' controlTable[ , 1] (the group label) cross colnames(controlTable)
#' (the column labels) are names of data cells in the long form.
#' controlTable[ , 2:ncol(controlTable)] (column labels)
#' are names of data cells in the wide form.
#' To get behavior similar to tidyr::gather/spread one builds the control table
#' by running an appropiate query over the data.
#'
#' Some discussion and examples can be found here:
#' \url{https://winvector.github.io/FluidData/FluidData.html} and
#' here \url{https://github.com/WinVector/cdata}.
#'
#' @param tallTable data.frame containing data to be mapped (in-memory data.frame).
#' @param keyColumns character list of column defining row groups
#' @param controlTable table specifying mapping (local data frame)
#' @param ... force later arguments to be by name.
#' @param columnsToCopy character list of column names to copy
#' @param strict logical, if TRUE check control table contents for uniqueness
#' @param checkNames logical, if TRUE check names
#' @param showQuery if TRUE print query
#' @param defaultValue if not NULL literal to use for non-match values.
#' @param dropDups logical if TRUE supress duplicate columns (duplicate determined by name, not content).
#' @param env environment to look for "winvector_temp_db_handle" in.
#' @return wide table built by mapping key-grouped tallTable rows to one row per group
#'
#' @seealso \code{\link{rowrecs_to_blocks_q}}, \code{\link{build_pivot_control}}
#'
#' @examples
#'
#' # pivot example
#' d <- data.frame(meas = c('AUC', 'R2'), val = c(0.6, 0.2))
#'
#' cT <- build_pivot_control(d,
#'                               columnToTakeKeysFrom= 'meas',
#'                               columnToTakeValuesFrom= 'val')
#' blocks_to_rowrecs(d,
#'                      keyColumns = NULL,
#'                      controlTable = cT)
#'
#' @export
#'
blocks_to_rowrecs <- function(tallTable,
                              keyColumns,
                              controlTable,
                              ...,
                              columnsToCopy = NULL,
                              strict = FALSE,
                              checkNames = TRUE,
                              showQuery = FALSE,
                              defaultValue = NULL,
                              dropDups = FALSE,
                              env = parent.frame()) {
  if(length(list(...))>0) {
    stop("cdata::blocks_to_rowrecs unexpected arguments.")
  }
  need_close <- FALSE
  db_handle <- base::mget("winvector_temp_db_handle",
                          envir = env,
                          ifnotfound = list(NULL),
                          inherits = TRUE)[[1]]
  if(is.null(db_handle)) {
    my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    need_close = TRUE
  } else {
    my_db <- db_handle$db
  }
  talltbltmpnam <- "cdata_tall_tmp"
  rownames(tallTable) <- NULL # just in case
  if(!isSpark(my_db)) {
    DBI::dbWriteTable(my_db,
                      talltbltmpnam,
                      tallTable,
                      temporary = TRUE,
                      overwrite = TRUE)
  } else {
    DBI::dbWriteTable(my_db,
                      talltbltmpnam,
                      tallTable,
                      temporary = TRUE)
  }
  resName <- blocks_to_rowrecs_q(tallTable = talltbltmpnam,
                                 keyColumns = keyColumns,
                                 controlTable = controlTable,
                                 my_db = my_db,
                                 columnsToCopy = columnsToCopy,
                                 tempNameGenerator = makeTempNameGenerator('mvtcq'),
                                 strict = strict,
                                 checkNames = checkNames,
                                 showQuery = showQuery,
                                 defaultValue = defaultValue,
                                 dropDups = dropDups)
  resData <- DBI::dbGetQuery(my_db, paste("SELECT * FROM", resName))
  x <- DBI::dbExecute(my_db, paste("DROP TABLE", talltbltmpnam))
  x <- DBI::dbExecute(my_db, paste("DROP TABLE", resName))
  if(need_close) {
    DBI::dbDisconnect(my_db)
  }
  resData
}



