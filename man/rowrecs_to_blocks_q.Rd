% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/RowsColsQ.R
\name{rowrecs_to_blocks_q}
\alias{rowrecs_to_blocks_q}
\title{Map a set of columns to rows (query based, take name of table).}
\usage{
rowrecs_to_blocks_q(wideTable, controlTable, my_db, ..., columnsToCopy = NULL,
  tempNameGenerator = makeTempNameGenerator("mvtrq"), strict = FALSE,
  checkNames = TRUE, showQuery = FALSE, defaultValue = NULL,
  temporary = FALSE, resultName = NULL)
}
\arguments{
\item{wideTable}{name of table containing data to be mapped (db/Spark data)}

\item{controlTable}{table specifying mapping (local data frame)}

\item{my_db}{db handle}

\item{...}{force later arguments to be by name.}

\item{columnsToCopy}{character list of column names to copy}

\item{tempNameGenerator}{a tempNameGenerator from cdata::makeTempNameGenerator()}

\item{strict}{logical, if TRUE check control table contents for uniqueness}

\item{checkNames}{logical, if TRUE check names}

\item{showQuery}{if TRUE print query}

\item{defaultValue}{if not NULL literal to use for non-match values.}

\item{temporary}{logical, if TRUE make result temporary.}

\item{resultName}{character, name for result table.}
}
\value{
long table built by mapping wideTable to one row per group
}
\description{
Transform data facts from columns into additional rows using SQL
and controlTable.
}
\details{
This is using the theory of "fluid data"n
(\url{https://github.com/WinVector/cdata}), which includes the
principle that each data cell has coordinates independent of the
storage details and storage detail dependent coordinates (usually
row-id, column-id, and group-id) can be re-derived at will (the
other principle is that there may not be "one true preferred data
shape" and many re-shapings of data may be needed to match data to
different algorithms and methods).

The controlTable defines the names of each data element in the two notations:
the notation of the tall table (which is row oriented)
and the notation of the wide table (which is column oriented).
controlTable[ , 1] (the group label) cross colnames(controlTable)
(the column labels) are names of data cells in the long form.
controlTable[ , 2:ncol(controlTable)] (column labels)
are names of data cells in the wide form.
To get behavior similar to tidyr::gather/spread one builds the control table
by running an appropiate query over the data.

Some discussion and examples can be found here:
\url{https://winvector.github.io/FluidData/FluidData.html} and
here \url{https://github.com/WinVector/cdata}.
}
\examples{

my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")

# un-pivot example
d <- data.frame(AUC = 0.6, R2 = 0.2)
DBI::dbWriteTable(my_db,
                  'd',
                  d,
                  overwrite = TRUE,
                  temporary = TRUE)
cT <- build_unpivot_control(nameForNewKeyColumn= 'meas',
                               nameForNewValueColumn= 'val',
                               columnsToTakeFrom= c('AUC', 'R2'))
tab <- rowrecs_to_blocks_q('d', cT, my_db = my_db)
qlook(my_db, tab)
DBI::dbDisconnect(my_db)

}
\seealso{
\code{\link{build_unpivot_control}}, \code{\link{blocks_to_rowrecs_q}}
}
