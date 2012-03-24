# Set the context of the visual tests
set_vtest_pkg <- NULL
get_vtest_pkg <- NULL
set_vtest_path <- NULL
get_vtest_path <- NULL
set_vtest_resultdir <- NULL
get_vtest_resultdir <- NULL
set_vtest_imagedir <- NULL
get_vtest_imagedir <- NULL

get_vcontext <- NULL
set_vcontext <- NULL
init_vtestinfo <- NULL
get_vtestinfo <- NULL
append_vtestinfo <- NULL

local({
  pkg <- NULL       # The package object
  testpath <- NULL  # The path to the test (usually package/visual_test/)
  resultdir <- NULL # Where the database files are saved
  imagedir <- NULL  # Where the image files are saved

  context <- NULL  # The context of a set of tests (usually in one script)
  testinfo <- NULL # Information about each test in a context

  # These are used by the top-level vtest function
  set_vtest_pkg <<- function(value) pkg <<- value
  get_vtest_pkg <<- function() pkg
  set_vtest_path <<- function (value) testpath <<- value
  get_vtest_path <<- function() testpath
  set_vtest_resultdir <<- function (value) resultdir <<- value
  get_vtest_resultdir <<- function() resultdir
  set_vtest_imagedir <<- function (value) imagedir <<- value
  get_vtest_imagedir <<- function() imagedir

  # These are used by each test script
  get_vcontext <<- function() context
  set_vcontext <<- function(value) {
    context <<- value
  }

  # Create a zero-row data frame to hold testinfo
  init_vtestinfo <<- function() {
    cols <- c("context", "desc", "type", "width", "height", "dpi", "err",
              "hash", "order")
    testinfo <<- setNames(data.frame(t(rep(NA, length(cols)))), cols)
    testinfo <<- testinfo[-1, ]
  }

  get_vtestinfo <<- function() testinfo

  # Add information about a single test
  append_vtestinfo <<- function(context, desc, type, width, height, dpi, err, hash, order) {
    # Check that context + description aren't already used
    if (sum(context == testinfo$context & desc == testinfo$desc) != 0)
      stop(contest, ":\"", desc, "\" cannot be added to vtestinfo because it is already present.")

    testinfo <<- rbind(testinfo,
      data.frame(context = context, desc = desc, type = type, width = width,
        height = height, dpi = dpi, err = err, hash = hash,
        order = nrow(testinfo)+1, stringsAsFactors = FALSE))
  }

})


# Run visual tests
#' @export
vtest <- function(pkg = NULL, filter = "", resultdir = NULL, showhelp = TRUE) {
  pkg <- as.package(pkg)
  load_all(pkg)

  set_vtest_pkg(pkg)

  test_path <- file.path(pkg$path, "visual_test")
  if (!file.exists(test_path)) 
    return()

  set_vtest_path(test_path)

  if (is.null(resultdir))
    resultdir <- find_default_resultdir()

  imagedir <- file.path(resultdir, "images")

  set_vtest_resultdir(resultdir)
  set_vtest_imagedir(imagedir)

  if (showhelp)
    message("Saving test results to directory ", resultdir)

  if (!file.exists(resultdir)) {
    resp <- readline(paste(resultdir, "does not exist! Create? (y/n) "))
    if (tolower(resp) != "y")
      return(invisible())

    dir.create(resultdir, recursive = TRUE, showWarnings = FALSE)
  }

  if (!file.exists(imagedir)) {
    resp <- readline(paste(imagedir, "does not exist! Create? (y/n) "))
    if (tolower(resp) != "y")
      return(invisible())
    dir.create(imagedir, recursive = TRUE, showWarnings = FALSE)
  }

  init_vtestinfo()

  # Run the test scripts
  files <- dir(test_path, full.names = TRUE, include.dirs = FALSE)
  files <- files[grepl("\\.[rR]$", files)]
  files <- match_filter(files, filter)
  files <- files[order(files)]
  lapply(files, source)


#  f_quote <- ifelse(is.null(filter), '', paste('filter="', filter, '"', sep = ""))
#  if (showhelp) {
#    message("\nRun vtest_webpage(", f_quote, ") to generate web pages for viewing tests.\n",
#      "Run vdiffstat(", f_quote, ") to see what files have changed.\n",
#      "Run vdiff_webpage(", f_quote,
#      ") to generate web pages comparing results to another commit in the git repository.\n",
#      "If you have added new tests, remember to add the output files to the git repository.\n",
#      "(Hide this message with showhelp=FALSE.)")
#  }


  # ============ Hash testinfo and save to lasttest.csv ===========

  # If running the full battery of tests, then we can hash the entire test set
  # and compare it to the test set table
  testinfo_hash <- hash_testinfo(get_vtestinfo())

  # Always save results to lasttest.csv
  message("Saving test results to lasttest.csv")
  write.csv(cbind(testinfo_hash, get_vtestinfo()),
    file.path(resultdir, "lasttest.csv"), row.names = FALSE)

  # TODO: Add check that vtest is run on entire set of tests, before writing (allow a force flag?)
  # TODO: turn this into function
  # ============ Check hash of testset results ===========

  commit <- git_find_commit_hash(pkg$path)
  clean_repo <- git_check_clean(pkg$path)

  # Assume that we'll write the commit data; if certain things happen, set to FALSE
  write_commitdata <- TRUE
  # Assume that we'll write the testinfo data; if certain things happen, set to FALSE
  write_testinfo <- TRUE

  message("Hash for vtest results is ", testinfo_hash)
  message(pkg$package, " is at commit ", commit)
  if (clean_repo) {
    message("Working tree state is clean, so results can be added to database.")
  } else {
    message("Working tree state is dirty, so results cannot be added to database.")
    write_commitdata <- FALSE
    write_testinfo   <- FALSE
  }

  # Read existing commit test results
  if (file.exists(file.path(resultdir, "commits.csv")))
    commitdata <- read.csv(file.path(resultdir, "commits.csv"))
  else
    commitdata <- data.frame()

  commitmatch <- commitdata$commit == commit
  if (any(commitmatch)) {
    message("Previous results for commit ", substr(commit, 1, 6), " found: ",
      paste(commitdata$testinfo_hash[commitmatch], collapse = ", "))

    if (sum(commitmatch) > 1)
      stop("More than one matching commit in database. This indicates a problem with the database.")

    if (commitdata$testinfo_hash == testinfo_hash) {
      message("Old and current results match! Good.")
      write_commitdata <- FALSE
    } else {
      message("Old and current results do not match! This may be because of changes to R, or to other packages.")
      if (write_commitdata) {
        reply <- readline("Replace old test result data with new test result data? (y/n) ")
        if (tolower(reply) != "y")
          write_commitdata <- FALSE
        else {
          commitdata <- commitdata[-commitmatch, ]
          commitdata <- rbind(commitdata, data.frame(commit = commit,
                                                     testinfo_hash = testinfo_hash))
        }
      }
    }
  } else {
    commitdata <- rbind(commitdata, data.frame(commit = commit,
                                               testinfo_hash = testinfo_hash))

    reply <- readline("Results are new. Would you like to add them to the database? (y/n) ")
    if (tolower(reply) != "y") {
      write_commitdata <- FALSE
      write_testinfo <- FALSE
    }
  }

  if (write_commitdata) {
    message("Writing result hash to commit database.")
    write.csv(commitdata, file.path(resultdir, "commits.csv"), row.names = FALSE)
  }

  # TODO: turn this into function
  # ============== Add to the testinfo table ======================

  # Read existing test results
  if (file.exists(file.path(resultdir, "testinfo.csv")))
    testinfo_all <- read.csv(file.path(resultdir, "testinfo.csv"), stringsAsFactors = FALSE)
  else
    testinfo_all <- data.frame(testinfo_hash = character())

  # Get the old results that match the current testinfo hash (if present)
  # It would be nice to be able to use:
  #   subset(testinfo_all, testinfo_hash == testinfo_hash, select = -testinfo_hash)
  # but this case is very problematic for subset because of re-used var name and
  # because when there are no matches, subset returns a 1-row NA-filled data frame.
  testinfo_match <- testinfo_all[testinfo_all$testinfo_hash == testinfo_hash, ]
  testinfo_match <- testinfo_match[!(names(testinfo_match) %in% "testinfo_hash")]

  if (nrow(testinfo_match) > 0 ) {
    message("Existing results found for testinfo hash ", testinfo_hash)
    message("Checking existing result hash just to make sure... ", appendLF = FALSE)
    testinfo_match_hash <- hash_testinfo(testinfo_match)
    if (testinfo_match_hash != testinfo_hash)
      stop("Re-hashing old testinfo results in a different hash value: ",
           testinfo_match_hash,
           "\nThis indicates a problem with the testinfo database.")

    message("Hash matches!")
    message("No need to add new testinfo to database.")
  } else {
    message("No existing results found for testinfo hash ", testinfo_hash)
    if (write_testinfo) {
      message("Adding new testinfo to database.")

      testinfo_all <- rbind(testinfo_all, cbind(testinfo_hash, get_vtestinfo()))
      write.csv(testinfo_all, file.path(resultdir, "testinfo.csv"), row.names = FALSE)
    }
  }
}


# Start a visual test context
#' @export
vcontext <- function(context) {
  if (!is.null(get_vcontext()))
    stop("Can't open new context while current context is still open. Use end_vcontext().")

  set_vcontext(context)
  message(context, appendLF = FALSE)

  destdir <- file.path(get_vtest_path(), context)
  unlink(dir(destdir, full.names = TRUE))
  dir.create(destdir, showWarnings = FALSE)
}


# Finish a visual test context.
#' @export
end_vcontext <- function() {
  if(is.null(get_vcontext())) {
    message("No open vcontext to end.")
    return(invisible())
  }

  set_vcontext(NULL)  # Reset the context
  message("")         # Print a newline
}


# Save an individual test to file, and record information using append_vtestinfo
# This presently only works with pdf; other file types will fail
# * desc: a short description of the test
# * filename: output filename (not including extension, like ".pdf"). If NULL, use MD5
#     hash of `desc` as the filename.
# * width: width in inches
# * height: height in inches
# * dpi: pixels per inch (OK, it really should be ppi)
# * device: string with name of output device. Only "pdf" is supported now.
# * err: error status. ok, warn, or error
# * hash: a hash of the file contents
#' @export
save_vtest <- function(desc = NULL, width = 4, height = 4, dpi = 72, device = "pdf") {
  if (is.null(get_vcontext()))     stop("Must have active vcontext")
  if (is.null(desc) || desc == "") stop("desc must not be empty")

  if (device == "pdf")  dpi <- NA
  else                  stop('Only "pdf" device supported at this time')

  err <- "ok"  # Use this to track if there's a warning or error when using ggsave

  # Save the pdf to a temporary file
  temppdf <- tempfile("vtest")
  tryCatch({ ggsave(temppdf, width = width, height = height, dpi = dpi,
               device = match.fun(device), compress = FALSE) },
           warning = function(w) { err <<- "warn"; warning(w) },
           error   = function(e) { err <<- "error"; warning(e) })

  # Zero out the dates and write modified PDF file to the output dir
  cleanpdf <- tempfile("vtest_cleaned")
  zero_pdf_date(temppdf, cleanpdf)

  unlink(temppdf)  # Remove the file in the temp dir

  # Get a hash of the file contents
  filehash <- digest(cleanpdf, file = TRUE)
  if (!file.exists(file.path(get_vtest_imagedir(), filehash)))
    file.rename(cleanpdf, file.path(get_vtest_imagedir(), filehash))

  # Append the info for this test in the vis_info list
  append_vtestinfo(context = get_vcontext(), desc = desc,
    type = device, width = width, height = height, dpi = dpi,
    err = err, hash = filehash)

  message(".", appendLF = FALSE)
}


# Get a hash of a testinfo table
hash_testinfo <- function(t) {
  # Reset the row names so it hashes like the original
  rownames(t) <- NULL
  # Sort by context and then order
  t <- arrange(t, context, order)

  # Make sure number columns are treated as num instead of int (for consistent hashing)
  numcols <- sapply(t, is.numeric)
  t[numcols] <- lapply(t[numcols], as.numeric)

  digest(t)
}

