#
#   shopifyr: An R Interface to the Shopify API
#
#   Copyright (C) 2015 Charlie Friedemann cfriedem @ gmail.com
#   Shopify API (c) 2006-2015 Shopify Inc.
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

########### ShopifyShop constructor ###########
#' @importFrom RCurl getCurlHandle
.initialize <- function(shopURL, password, quiet = FALSE) {
    if (missing(shopURL)) stop("shopURL is required to create a ShopifyShop")
    if (missing(password)) stop("password is required to create a ShopifyShop")
    
    self$shopURL <- paste0(gsub(".myshopify.com", "", tolower(shopURL)), ".myshopify.com")
    self$password <- password
    
    # generate curl handle and header gatherer
    private$.curlHandle <- getCurlHandle(cainfo = system.file("CurlSSL", "cacert.pem", package = "RCurl"),
                                         headerfunction = private$.updateResponseHeaders,
                                         writefunction = private$.updateResponseBody,
                                         httpheader = c('Content-Type' = 'application/json',
                                                        'Accept' = 'application/json',
                                                        'X-Shopify-Access-Token' = self$password))
    
    # fetch shop information
    self$shopInfo <- try(self$getShop(), silent=TRUE)
    if (inherits(self$shopInfo, "try-error"))
        stop(paste("Error accessing Shopify : ", attr(self$shopInfo,"condition")$message))
    
    # show announcements if there are any
    if (!isTRUE(quiet))
        self$showAnnouncements()
}

########### ShopifyShop print method ###########
print.ShopifyShop <- function(...) {
    cat("--", self$shopInfo$name, "Shopify API Client --\n")
    cat("Site Domain:", self$shopInfo$domain, "\n")
    cat("Shopify Domain:", self$shopInfo$myshopify_domain, "\n")
}

########### Private ShopifyShop member functions ###########
.params <- function(params) {
    nms <- names(params)
    ret <- NULL
    for (i in 1:length(params)) {
        if (is.null(params[[i]])) 
            next
        if (!is.null(ret))
            ret <- paste0(ret, "&")
        
        prms <- sapply(as.character(params[[i]]), URLencode)
        if (length(prms) > 1)
            ret <- paste0(ret, URLencode(nms[i]), "=", paste0(prms, collapse=paste0(URLencode(nms[i]),"=")))
        else 
            ret <- paste0(ret, URLencode(nms[i]), "=", prms)
    }
    ret
}

.url <- function(...) { 
    paste0(Filter(Negate(is.null), list(...)), collapse="/") 
}

.baseUrl <- function() {
    paste0("https://", self$shopURL, "/admin/")
}

.wrap <- function(data, name, check = "id") {
    if ((length(data) != 1) || (names(data) != name)) {
        ret <- list()
        ret[[name]] <- data
    } else ret <- data
    
    if (is.character(check)) {
        missingFields <- check[which(!check %in% names(ret[[name]]))]
        if (length(missingFields) > 0)
            stop(paste(name, "missing mandatory field(s): ", paste(missingFields, collapse=", ")))
    }
    ret
}

.fetchAll <- function(slug, name, limit = 250, page, ..., verbose) {
    if (missing(name)) name <- slug
    
    if (missing(page)) {
        env <- new.env()
        
        req <- 1
        if (!missing(verbose) && verbose)
            message(paste0("Request ",req,": fetching ",name," 1 - ",limit))
        reqTime <- Sys.time()
        result <- private$.request(slug, limit=limit, page=req, ...)
        env[[paste0("r",req)]] <- result[[name]]
        while (length(result[[name]]) == limit) {
            # wait 1 second between requests
            while((Sys.time()-1) < reqTime) {}
            req <- req + 1
            if (!missing(verbose) && verbose)
                message(paste0("Request ",req,": fetching ",name," ",(req-1)*limit+1," - ",req*limit))
            reqTime <- Sys.time()
            result <- private$.request(slug, limit=limit, page=req, ...)
            env[[paste0("r",req)]] <- result[[name]]
        }
        
        # combine results
        fetched <- do.call(c, lapply(ls(env), function(nm) env[[nm]]))
    } else {
        # if page is specified, just make the request
        fetched <- private$.request(slug, limit=limit, page=page, ...)[[name]]
    }
    fetched
}

#' @importFrom RJSONIO toJSON
#' @importFrom RJSONIO isValidJSON
.encode <- function(data) {
    if (is.list(data)) {
        if (length(data) == 0)
            data <- "{}" # use '{}' not '[]' which toJSON() would give for empty list
        else
            data <- toJSON(data, digits=20)
    } else if (is.character(data)) {
        if (!isValidJSON(data, asText=TRUE)) stop("data must be valid JSON")
    } else {
        stop("data must be of type list or character")
    }
    data
}

#' @importFrom RCurl postForm
#' @importFrom RCurl getURL
#' @importFrom RCurl curlPerform
.request <- function(slug, reqType = "GET", 
                     data = NULL, 
                     ..., 
                     parse. = TRUE, 
                     type. = "json", 
                     verbose = FALSE) {
    
    # generate url and check request type
    reqURL <- paste0(private$.baseUrl(), slug, ".", type.)
    reqType <- match.arg(toupper(reqType), c("GET","POST","PUT","DELETE"))
    
    # parse url parameters
    params <- list(...)
    if (!is.null(params) && length(params) > 0)
        reqURL <- paste0(reqURL, "?", private$.params(params))
    
    # clear response buffers
    private$.clearResponseHeaders()
    private$.clearResponseBody()
    
    # send request
    if (reqType %in% c("GET", "DELETE")) {
        # GET or DELETE request
        res <- try(curlPerform(url = reqURL,
                               curl = private$.curlHandle,
                               customrequest = reqType,
                               verbose = verbose), silent=TRUE)
        
    } else if (reqType %in% c("POST","PUT")) {
        # POST or PUT request
        res <- try(curlPerform(url = reqURL,
                               curl = private$.curlHandle, 
                               postfields = private$.encode(data),
                               post = ifelse(reqType=="POST",1L,0L),
                               customrequest = reqType,
                               verbose = verbose), silent=TRUE) 
    }
    
    # check result for error
    if (inherits(res, "try-error")) {
        stop(paste("Curl error :", attr(res,"condition")$message))
    }
    
    # return response
    private$.getResponseBody(parse.)
}

#' @importFrom RCurl parseHTTPHeader
.getResponseHeaders <- function(parse = TRUE) { 
    if (isTRUE(parse))
        private$.parseResponseHeaders(private$.responseHeaders)
    else
        private$.responseHeaders
}

.updateResponseHeaders <- function(str) { 
    private$.responseHeaders <- c(private$.responseHeaders, str) 
    nchar(str, "bytes")
}

.clearResponseHeaders <- function() {
    private$.responseHeaders <- NULL
}

# the function below is a slightly modified version of RCurl::parseHttpHeader
.parseResponseHeaders <- function(lines) {
    if (length(lines) < 1) 
        return(NULL)
    if (length(lines) == 1) 
        lines <- strsplit(lines, "\r\n")[[1]]
    
    i <- grep("^HTTP[^_]", lines) # small fix to ensure no conflict with Shopify's HTTP_X_SHOPIFY header style
    status <- lines[max(i)]
    lines <- lines[seq(max(i), length(lines))]
    
    st <- private$.getHeaderStatus(status)
    if (st[["status"]] == 100) {
        if ((length(lines) - length(grep("^[[:space:]]*$", lines))) == 1) 
            return(st)
    }
    lines <- lines[-1]
    lines <- gsub("\r\n$", "", lines)
    lines <- lines[lines != ""]
    
    header <- structure(sub("[^:]+: (.*)", "\\1", lines), names = sub("([^:]+):.*", "\\1", lines))
    
    header[["status"]] <- st[["status"]]
    header[["statusMessage"]] <- st[["message"]]
    header
}

# the function below is a slightly modified version of RCurl:::getStatus
.getHeaderStatus <- function(status) {
    els <- strsplit(status, " ")[[1]]
    list(status = as.integer(els[2]), message = paste(els[-c(1,2)], collapse = " "))
}

.getResponseBody <- function(parse = TRUE) {
    if (isTRUE(parse))
        private$.parseResponseBody(paste0(private$.responseBody, collapse="")) 
    else
        paste0(private$.responseBody, collapse="")
}

.updateResponseBody <- function(str) {
    private$.responseBody <- c(private$.responseBody, str)
    nchar(str, "bytes")
}

.clearResponseBody <- function() {
    private$.responseBody <- NULL
}

#' @importFrom RJSONIO fromJSON
.parseResponseBody <- function(response) {
    if (missing(response) || is.null(response) || nchar(response) < 2)
        return(NULL)
    
    parsed <- fromJSON(response, simplify=FALSE)
    
    if (!is.null(parsed$errors))
        stop(paste(parsed$errors, collapse="; "), call.=FALSE)
    
    parsed
}

.parseShopifyTimestamp <- function(str) {
    # strings are in format like "2015-01-23T00:01:00-04:00" 
    # strip out last colon so %z works
    as.POSIXct(gsub("^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}-\\d{2}):(\\d{2})$", "\\1\\2", str), format="%FT%T%z")
}

.encodeImageFile <- function(filepath) {
    if (!file.exists(filepath))
        stop("image file does not exist")
    
    if (!requireNamespace("base64enc"))
        stop("The 'base64enc' package is required to upload images to Shopify")
    
    imgData <- base64enc::base64encode(filepath)
    image <- list(attachment = imgData, filename = basename(filepath))
    image
}
