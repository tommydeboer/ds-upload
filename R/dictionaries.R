#' Download all released data dictionaries
#'
#' @param dict_name used for beta dictionaries
#' @param dict_version dictionary version
#' @param dict_kind dictionary kind (possible kinds are 'core' or 'outcome')
#'
#' @importFrom purrr pmap
#' @importFrom dplyr select %>%
#' @importFrom utils download.file packageVersion
#'
#' @noRd
du.dict.download <- function(dict_name, dict_version, dict_kind) {
  message("######################################################")
  message("  Start download dictionaries")
  message("------------------------------------------------------")

  dir.create(dict_kind)

  if (!missing(dict_name)) {
    api_url <- paste0(ds_upload.globals$api_dict_beta_url, "dictionaries/", dict_name)
  } else {
    api_url <- paste0(
      ds_upload.globals$api_dict_released_url, "dictionaries/",
      dict_kind, "/", dict_version, "?ref=", dict_kind, "-", dict_version
    )
  }

  dictionaries <- du.get.response.as.dataframe(api_url)

  dictionaries %>%
    select("name", "download_url") %>%
    pmap(function(name, download_url) {
      message(paste0("* Download: [ ", name, " ]"))
      download.file(url = download_url, destfile = paste0(dict_kind, "/", name), mode = "wb", method = "libcurl", quiet = TRUE)
    })

  message("  Successfully downloaded dictionaries")
}



#' Retrieve the released dictionaries from 'ds-dictionaries' to match against
#'
#' @param api_url url to retrieve the tables from
#' @param dict_version model version of the data
#' @param dict_name dictionary name can be 'kind' or a random name
#' @param data_version data version if used to create the tables
#'
#' @importFrom dplyr select
#' @importFrom purrr pmap
#' @importFrom fs path_ext_remove
#'
#' @return dictionaries list of tables
#'
#' @noRd
du.dict.retrieve.tables <- function(api_url, dict_name, dict_version, data_version) {
  beta <- TRUE
  api_url_path <- paste0(api_url, "dictionaries/", dict_name)

  if (!missing(dict_version) && !missing(data_version)) {
    message(" * Check released dictionaries")
    api_url_path <- paste0(api_url, "dictionaries/", dict_name, "/", dict_version, "?ref=", dict_name, "-", dict_version)
    beta <- FALSE
  }

  dictionaries <- du.get.response.as.dataframe(api_url_path)

  if (any(names(dictionaries) == "message")) {
    stop(paste0("There are no dictionaries avialable in the folder: [ ", dict_name, " ]"))
  }
  
  tables <- dictionaries %>%
    select("name") %>%
    pmap(function(name) {
      if (!beta) {
        canonical_table_name <- strsplit(name, "_")
        table <- paste0(data_version, "_", canonical_table_name[[1]][3], "_rep")
      } else {
        table <- path_ext_remove(name)
      }
      return(data.frame(table = table, file_name = name))
    })

  return(tables)
}

#' Get the possible dictionary versions from Github
#'
#' @param dict_kind dictionary kind (can be 'core' or 'outcome')
#' @param dict_version dictionary version (can be 'x_x')
#'
#' @noRd
du.populate.dict.versions <- function(dict_kind, dict_version) {
  versions <- du.get.response.as.dataframe(ds_upload.globals$api_dict_released_tags_url)
  
  versions <- versions %>% 
    select("ref") %>%
    pmap(function(ref) {
      if(grepl(dict_kind, ref, fixed = TRUE)) {
        without_prefix <- substr(ref, 11, nchar(ref))
        return(substr(without_prefix, nchar(dict_kind)+2, nchar(without_prefix)))
      }
    })
  
  versions = versions[-which(sapply(versions, is.null))]
  
  if (dict_kind == du.enum.dict.kind()$CORE) {
    ds_upload.globals$dictionaries_core <- versions
  } else if (dict_kind == du.enum.dict.kind()$OUTCOME) {
    ds_upload.globals$dictionaries_outcome <- versions
  } else if (dict_kind == du.enum.dict.kind()$CHEMICALS) {
    ds_upload.globals$dictionaries_chemicals <- versions
  } else if (dict_kind == du.enum.dict.kind()$OUTCOME_ATH) {
    ds_upload.globals$dictionaries_outcome_ath <- versions
  }else {
    stop("Dictionary not supported.")
  }
}

#'
#' Retrieve the right file from download directory
#'
#' @param dict_table a specific table that you want to check
#' @param dict_kind can be 'core' or 'outcome'
#'
#' @importFrom readxl read_xlsx
#'
#' @return a raw version of the dictionary
#'
#' @noRd
du.retrieve.dictionaries <- function(dict_table, dict_kind) {
  dict_file_list <- list.files(paste0(getwd(), "/", dict_kind))

  if (!missing(dict_table)) {
    dict_file_list <- dict_file_list[grep(dict_table, dict_file_list)]
  }

  raw_dict <- list()
  for (file_name in dict_file_list) {
    raw_dict <- rbind(raw_dict, read_xlsx(path = paste0(dict_kind, "/", file_name), sheet = 1))
  }
  return(as.data.frame(raw_dict))
}

#' Get the full dictionary with mapped categories
#' 
#' @param dict_table a specific table that you want to check
#' @param dict_kind can be 'core' or 'outcome'
#'
#' @importFrom readxl read_xlsx excel_sheets
#' @importFrom dplyr %>% nest_join mutate rename bind_rows
#' @importFrom tibble as_tibble
#'
#' @noRd
du.retrieve.full.dict <- function(dict_table, dict_kind) {
  name <- variable <- label <- NULL
  
  dict_file_list <- list.files(paste0(getwd(), "/", dict_kind))
  filename <- dict_file_list[grep(dict_table, dict_file_list)]
  
  filepath <- paste0(getwd(), "/", dict_kind, "/", filename)
  vars <- read_xlsx(path = filepath, sheet = 1) %>% as_tibble()
  if (length(excel_sheets(filepath)) == 2) {
    cats <- read_xlsx(path = filepath, sheet = 2) %>% as_tibble()
    cats <- cats %>%
      rename(value = name, name = variable) %>%
      mutate(name = as.character(name), label = as.character(label))
    vars <- nest_join(vars, cats, by = "name")
  } 
  vars %>% bind_rows()
}
