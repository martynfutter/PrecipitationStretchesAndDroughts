#!/usr/bin/env Rscript
################################################################################
# Standalone Precipitation Stretching Script with Monthly Offsets
# 
# This script applies monthly climate change offsets to daily weather data,
# then manipulates precipitation using a threshold-based stretching algorithm
# with optimized parameters to preserve mass balance.
#
# INPUT FILES:
#   1. Daily weather file: date, temperature, precipitation
#   2. Monthly offsets file: Month, PPctChange, TOffset
#   3. Optional JSON metadata file: same name as daily weather file, .json extension
#      (e.g., if daily_weather_file = "short.csv", looks for "short.json")
#
# USER PARAMETERS (must be specified):
#   - threshold (t): Percentile threshold, 0 <= t <= 100
#   - stretch_factor (s): Stretch factor for high values, s >= 0
#
# ESTIMATED PARAMETERS (optimized automatically):
#   - a, b, c, d: Initialized to 1.0, optimized to achieve sum(p') ≈ sum(p_offset)
#
# OUTPUT:
#   CSV file with columns: date, temperature, precipitation, t_offset, p_offset,
#                          z, x, stretched_precipitation
#   JSON metadata file: same name as output CSV, .json extension
#      - Contains all content from the optional input JSON file
#      - Plus generated metadata: input/output files, monthly offsets applied,
#        user parameters, optimized parameters, precipitation results,
#        temperature results, data summary
#
# FORMULA (v) UPDATE: Now uses exponential form to guarantee non-negativity
#   p' = p_offset × exp(-c × (x^a × (1-x)^b))
#
# Author: Generated for precipitation time series analysis
# Date: 2025-11-11
################################################################################

# =============================================================================
# CONFIGURATION SECTION
# =============================================================================

DAILY_WEATHER_FILE <- "daily_weather.csv"
MONTHLY_OFFSETS_FILE <- "monthly_delta_shifts.csv"
OUTPUT_FILE <- "stretched_precipitation_output.csv"

# User-specified parameters
THRESHOLD <- 75          # Percentile threshold (0-100)
STRETCH_FACTOR <- 20     # Stretch factor (>= 0)

# Optimization settings
INITIAL_A <- 1.0
INITIAL_B <- 1.0
INITIAL_C <- 1.0
INITIAL_D <- 1.0
CONVERGENCE_TOLERANCE <- 0.01  # 1% tolerance
MAX_ITERATIONS <- 1000

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

#' Find column name (case-insensitive)
find_column_name <- function(df, target_name) {
  col_names <- names(df)
  match_idx <- which(tolower(col_names) == tolower(target_name))
  if (length(match_idx) > 0) {
    return(col_names[match_idx[1]])
  }
  return(NULL)
}

#' Parse dates with multiple format support
parse_dates_flexible <- function(date_vector) {
  formats <- c("%Y-%m-%d", "%Y/%m/%d", "%d-%m-%Y", "%d/%m/%Y", 
               "%m-%d-%Y", "%m/%d/%Y", "%Y%m%d")
  
  for (fmt in formats) {
    parsed_dates <- tryCatch({
      as.Date(date_vector, format = fmt)
    }, error = function(e) NULL)
    
    if (!is.null(parsed_dates) && sum(!is.na(parsed_dates)) > 0) {
      return(parsed_dates)
    }
  }
  
  # Try automatic parsing as fallback
  parsed_dates <- tryCatch({
    as.Date(date_vector)
  }, error = function(e) {
    stop("Could not parse dates. Please ensure dates are in a standard format.")
  })
  
  return(parsed_dates)
}

#' Derive JSON file path from a CSV file path (replace .csv extension with .json)
csv_to_json_path <- function(csv_path) {
  sub("\\.[Cc][Ss][Vv]$", ".json", csv_path)
}

#' Recursively merge two lists; b values override a values for matching keys
merge_lists <- function(a, b) {
  for (key in names(b)) {
    if (key %in% names(a) && is.list(a[[key]]) && is.list(b[[key]])) {
      a[[key]] <- merge_lists(a[[key]], b[[key]])
    } else {
      a[[key]] <- b[[key]]
    }
  }
  a
}

# =============================================================================
# PROCESSING FUNCTION
# =============================================================================

stretch_precipitation <- function(daily_weather_file = DAILY_WEATHER_FILE,
                                 monthly_offsets_file = MONTHLY_OFFSETS_FILE,
                                 output_file = OUTPUT_FILE,
                                 threshold = THRESHOLD,
                                 stretch_factor = STRETCH_FACTOR,
                                 initial_params = c(INITIAL_A, INITIAL_B, 
                                                   INITIAL_C, INITIAL_D),
                                 tolerance = CONVERGENCE_TOLERANCE) {
  
  # Load required libraries
  if (!require(jsonlite, quietly = TRUE)) {
    install.packages("jsonlite")
    library(jsonlite)
  }

  cat("\n================================================================\n")
  cat("PRECIPITATION STRETCHING WITH MONTHLY OFFSETS\n")
  cat("================================================================\n\n")
  
  # ---------------------------------------------------------------------------
  # Read optional input JSON (same name as the daily weather CSV)
  # ---------------------------------------------------------------------------
  input_json_file <- csv_to_json_path(daily_weather_file)
  input_json_data <- list()
  
  if (file.exists(input_json_file)) {
    cat(paste("Reading input JSON file:", input_json_file, "\n"))
    input_json_data <- tryCatch(
      fromJSON(input_json_file, simplifyVector = FALSE),
      error = function(e) {
        warning(paste("Could not parse input JSON file:", input_json_file, "-", e$message))
        list()
      }
    )
    cat("  Input JSON loaded successfully.\n\n")
  } else {
    cat(paste("No input JSON file found at:", input_json_file, "(optional - skipping)\n\n"))
  }

  # ---------------------------------------------------------------------------
  # Read daily weather file
  # ---------------------------------------------------------------------------
  cat("Reading daily weather file...\n")
  
  if (!file.exists(daily_weather_file)) {
    stop(paste("Daily weather file not found:", daily_weather_file))
  }
  
  weather_data <- read.csv(daily_weather_file, stringsAsFactors = FALSE)
  cat(paste("  Read", nrow(weather_data), "rows from", daily_weather_file, "\n"))
  
  # Find columns (case-insensitive)
  date_col   <- find_column_name(weather_data, "date")
  temp_col   <- find_column_name(weather_data, "temperature")
  precip_col <- find_column_name(weather_data, "precipitation")
  
  if (is.null(precip_col)) {
    precip_col <- find_column_name(weather_data, "p")
  }
  if (is.null(temp_col)) {
    temp_col <- find_column_name(weather_data, "air_temperature")
  }
  
  if (is.null(date_col))   stop("Could not find 'date' column in weather file")
  if (is.null(precip_col)) stop("Could not find 'precipitation' or 'p' column in weather file")
  if (is.null(temp_col))   stop("Could not find 'temperature' or 'air_temperature' column in weather file")
  
  cat(paste("  Using columns: date='", date_col, "', temp='", temp_col,
            "', precip='", precip_col, "'\n", sep = ""))
  
  dates         <- parse_dates_flexible(weather_data[[date_col]])
  temperature   <- as.numeric(weather_data[[temp_col]])
  precipitation <- as.numeric(weather_data[[precip_col]])
  
  # ---------------------------------------------------------------------------
  # Read monthly offsets file
  # ---------------------------------------------------------------------------
  cat("\nReading monthly offsets file...\n")
  
  if (!file.exists(monthly_offsets_file)) {
    stop(paste("Monthly offsets file not found:", monthly_offsets_file))
  }
  
  delta_shifts <- read.csv(monthly_offsets_file, stringsAsFactors = FALSE)
  cat(paste("  Read", nrow(delta_shifts), "rows from", monthly_offsets_file, "\n"))
  
  # Find columns (case-insensitive)
  month_col      <- find_column_name(delta_shifts, "month")
  pct_change_col <- find_column_name(delta_shifts, "PPctChange")
  toffset_col    <- find_column_name(delta_shifts, "TOffset")
  
  if (is.null(month_col))      stop("Could not find 'Month' column in offsets file")
  if (is.null(pct_change_col)) stop("Could not find 'PPctChange' column in offsets file")
  if (is.null(toffset_col))    stop("Could not find 'TOffset' column in offsets file")
  
  cat(paste("  Using columns: month='", month_col, "', pct_change='", pct_change_col,
            "', toffset='", toffset_col, "'\n", sep = ""))
  
  # ---------------------------------------------------------------------------
  # Apply monthly offsets
  # ---------------------------------------------------------------------------
  cat("\nApplying monthly offsets...\n")
  
  months    <- as.integer(format(dates, "%m"))
  p_offset  <- numeric(length(precipitation))
  t_offset  <- numeric(length(temperature))
  
  for (m in 1:12) {
    month_mask <- months == m
    if (!any(month_mask)) next
    
    shift_row <- delta_shifts[delta_shifts[[month_col]] == m, ]
    if (nrow(shift_row) == 0) {
      warning(paste("No offset data found for month:", m))
      next
    }
    
    pct_change <- shift_row[[pct_change_col]][1]
    t_off      <- shift_row[[toffset_col]][1]
    
    p_offset[month_mask] <- precipitation[month_mask] * (100 + pct_change) / 100
    t_offset[month_mask] <- temperature[month_mask] + t_off
  }
  
  cat(paste("  Applied offsets to", length(precipitation), "records\n"))
  cat(paste("  Original sum(p):", round(sum(precipitation), 4), "\n"))
  cat(paste("  Offset sum(p_offset):", round(sum(p_offset), 4), "\n"))
  
  # ---------------------------------------------------------------------------
  # Calculate cumulative distribution (z values) for non-zero p_offset
  # ---------------------------------------------------------------------------
  cat("\nCalculating cumulative distribution (z values)...\n")
  
  non_zero_idx    <- which(p_offset > 0)
  n_nonzero       <- length(non_zero_idx)
  z_values        <- numeric(length(p_offset))
  stretch_factor_x <- numeric(length(p_offset))
  
  if (n_nonzero > 0) {
    sorted_idx  <- non_zero_idx[order(p_offset[non_zero_idx])]
    rank_vals   <- seq_len(n_nonzero)
    z_sorted    <- (rank_vals / n_nonzero) * 100
    
    z_values[sorted_idx] <- z_sorted
    cat(paste("  Non-zero p_offset days:", n_nonzero, "\n"))
    cat(paste("  Zero p_offset days:", length(p_offset) - n_nonzero, "\n"))
  }
  
  # ---------------------------------------------------------------------------
  # Optimization: find a, b, c, d so sum(p') ≈ sum(p_offset)
  # ---------------------------------------------------------------------------
  cat("\nOptimizing parameters a, b, c, d...\n")
  
  p_offset_sum <- sum(p_offset)
  
  compute_stretched <- function(params, p_off, z_vals, t, s) {
    a_p <- params[1]; b_p <- params[2]; c_p <- params[3]; d_p <- params[4]
    
    result <- numeric(length(p_off))
    
    for (i in seq_along(p_off)) {
      z <- z_vals[i]
      p <- p_off[i]
      
      if (p == 0) {
        result[i] <- 0
      } else if (z >= t) {
        x_val     <- (z - t) / (100 - t)
        result[i] <- p + (p * (s / 100) * x_val^d_p)
      } else {
        x_val     <- if (t > 0) z / t else 0
        result[i] <- p * exp(-c_p * (x_val^a_p * (1 - x_val)^b_p))
      }
    }
    result
  }
  
  objective <- function(params) {
    if (any(params <= 0)) return(1e10)
    p_stretched  <- compute_stretched(params, p_offset, z_values, threshold, stretch_factor)
    stretched_s  <- sum(p_stretched)
    rel_diff     <- abs((stretched_s - p_offset_sum) / p_offset_sum)
    rel_diff
  }
  
  opt_result <- optim(
    par     = initial_params,
    fn      = objective,
    method  = "Nelder-Mead",
    control = list(maxit = MAX_ITERATIONS, reltol = tolerance / 10)
  )
  
  a <- opt_result$par[1]
  b <- opt_result$par[2]
  c <- opt_result$par[3]
  d <- opt_result$par[4]
  
  final_error <- opt_result$value
  
  cat(paste("  Optimization converged with relative error:", round(final_error * 100, 4), "%\n"))
  cat(paste("  Optimized: a =", round(a, 4), ", b =", round(b, 4),
            ", c =", round(c, 4), ", d =", round(d, 4), "\n"))
  
  # ---------------------------------------------------------------------------
  # Apply final stretch
  # ---------------------------------------------------------------------------
  cat("\nApplying final stretch formula...\n")
  
  stretched_precip <- compute_stretched(c(a, b, c, d), p_offset, z_values,
                                        threshold, stretch_factor)
  
  # Assign x values for output
  for (i in seq_along(p_offset)) {
    z <- z_values[i]
    if (p_offset[i] == 0) {
      stretch_factor_x[i] <- 0
    } else if (z >= threshold) {
      stretch_factor_x[i] <- (z - threshold) / (100 - threshold)
    } else {
      stretch_factor_x[i] <- if (threshold > 0) z / threshold else 0
    }
  }
  
  if (any(stretched_precip[stretched_precip > 0] <= 0)) {
    warning("Negative or zero stretched precipitation detected. This should not happen with exponential form.")
  }
  
  # Calculate sums (step vi)
  stretched_sum <- sum(stretched_precip)
  relative_diff <- (stretched_sum - p_offset_sum) / p_offset_sum * 100
  
  cat(paste("  sum(p_offset):", round(p_offset_sum, 4), "\n"))
  cat(paste("  sum(p'):", round(stretched_sum, 4), "\n"))
  cat(paste("  Relative difference:", round(relative_diff, 4), "%\n"))
  cat(paste("  Min stretched precipitation:", round(min(stretched_precip[stretched_precip > 0]), 6), "\n"))
  cat(paste("  Max stretched precipitation:", round(max(stretched_precip), 4), "\n"))
  
  # ---------------------------------------------------------------------------
  # OUTPUT: Save CSV results
  # ---------------------------------------------------------------------------
  cat("\nSaving output...\n")
  
  output_data <- data.frame(
    date                    = dates,
    temperature             = temperature,
    precipitation           = precipitation,
    t_offset                = t_offset,
    p_offset                = p_offset,
    z                       = z_values,
    x                       = stretch_factor_x,
    stretched_precipitation = stretched_precip
  )
  
  write.csv(output_data, output_file, row.names = FALSE)
  cat(paste("  ✓ Output CSV saved to:", output_file, "\n"))
  cat(paste("  Output columns:", paste(names(output_data), collapse = ", "), "\n"))
  
  # ---------------------------------------------------------------------------
  # OUTPUT: Save JSON metadata
  # ---------------------------------------------------------------------------
  output_json_file <- csv_to_json_path(output_file)
  
  cat(paste("\nGenerating JSON metadata:", output_json_file, "\n"))
  
  # Build monthly offsets list (matching example structure)
  monthly_offsets_list <- list()
  for (m in 1:12) {
    key      <- paste0("Month_", m)
    row_m    <- delta_shifts[delta_shifts[[month_col]] == m, ]
    if (nrow(row_m) > 0) {
      monthly_offsets_list[[key]] <- list(
        PPctChange = row_m[[pct_change_col]][1],
        Toffset    = row_m[[toffset_col]][1]
      )
    }
  }
  
  # Build the generated metadata sections
  generated_metadata <- list(
    scenario_info = list(
      date_created = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
    ),
    input_files = list(
      input_file                 = daily_weather_file,
      monthly_delta_shifts_source = monthly_offsets_file
    ),
    output_files = list(
      csv_file      = output_file,
      metadata_file = output_json_file
    ),
    monthly_offsets_applied = monthly_offsets_list,
    user_parameters = list(
      threshold      = threshold,
      stretch_factor = stretch_factor,
      date_format    = "%Y-%m-%d",
      tolerance      = tolerance,
      max_iterations = MAX_ITERATIONS
    ),
    optimized_parameters = list(
      a = round(a, 4),
      b = round(b, 4),
      c = round(c, 4),
      d = round(d, 4)
    ),
    precipitation_results = list(
      original_total             = round(sum(precipitation), 2),
      shifted_total              = round(p_offset_sum, 4),
      stretched_total            = round(stretched_sum, 4),
      shift_change_percent       = round((p_offset_sum - sum(precipitation)) /
                                         sum(precipitation) * 100, 2),
      convergence_error_percent  = round(final_error * 100, 4),
      days_with_precipitation    = sum(precipitation > 0),
      days_without_precipitation = sum(precipitation == 0)
    ),
    temperature_results = list(
      original_mean = round(mean(temperature, na.rm = TRUE), 2),
      shifted_mean  = round(mean(t_offset, na.rm = TRUE), 2),
      mean_change   = round(mean(t_offset - temperature, na.rm = TRUE), 2)
    ),
    data_summary = list(
      total_days_processed = nrow(output_data),
      date_range_start     = format(min(dates), "%Y-%m-%d"),
      date_range_end       = format(max(dates), "%Y-%m-%d")
    )
  )
  
  # Merge: start with the input JSON content, then apply generated metadata on top.
  # This preserves any extra fields from the input JSON (e.g. scenario_name,
  # stretch_value inside scenario_info) while always writing fresh computed values.
  output_metadata <- merge_lists(input_json_data, generated_metadata)
  
  write_json(output_metadata, output_json_file, pretty = TRUE, auto_unbox = TRUE)
  cat(paste("  ✓ JSON metadata saved to:", output_json_file, "\n"))
  
  # ---------------------------------------------------------------------------
  # SUMMARY
  # ---------------------------------------------------------------------------
  cat("\n================================================================\n")
  cat("SUMMARY\n")
  cat("================================================================\n")
  cat(paste("Daily weather file:", daily_weather_file, "\n"))
  cat(paste("Monthly offsets file:", monthly_offsets_file, "\n"))
  cat(paste("Output file:", output_file, "\n"))
  cat(paste("JSON metadata file:", output_json_file, "\n"))
  cat(paste("Date range:", min(dates), "to", max(dates), "\n"))
  cat(paste("Total records:", nrow(output_data), "\n"))
  cat(paste("Non-zero p_offset days:", length(non_zero_idx), "\n\n"))
  
  cat("USER PARAMETERS:\n")
  cat(paste("  Threshold (t):", threshold, "%\n"))
  cat(paste("  Stretch factor (s):", stretch_factor, "%\n\n"))
  
  cat("OPTIMIZED PARAMETERS:\n")
  cat(paste("  a =", round(a, 6), "\n"))
  cat(paste("  b =", round(b, 6), "\n"))
  cat(paste("  c =", round(c, 6), "\n"))
  cat(paste("  d =", round(d, 6), "\n\n"))
  
  cat("PRECIPITATION TOTALS:\n")
  cat(paste("  Original sum(p):", round(sum(precipitation), 4), "\n"))
  cat(paste("  Offset sum(p_offset):", round(p_offset_sum, 4), "\n"))
  cat(paste("  Stretched sum(p'):", round(stretched_sum, 4), "\n"))
  cat(paste("  Difference p' vs p_offset:", round(relative_diff, 4), "%\n\n"))
  
  cat("TEMPERATURE:\n")
  cat(paste("  Original mean:", round(mean(temperature, na.rm = TRUE), 2), "°C\n"))
  cat(paste("  Offset mean:", round(mean(t_offset, na.rm = TRUE), 2), "°C\n"))
  cat(paste("  Mean change:", round(mean(t_offset - temperature, na.rm = TRUE), 2), "°C\n\n"))
  
  cat("FORMULAS APPLIED:\n")
  cat(paste("  For z >= ", threshold, " (formula iv):\n", sep = ""))
  cat(paste("    x = (z - ", threshold, ") / (100 - ", threshold, ")\n", sep = ""))
  cat(paste("    p' = p_offset + (p_offset × (", stretch_factor, "/100) × x^", round(d, 4), ")\n\n", sep = ""))
  cat(paste("  For z < ", threshold, " (formula v - EXPONENTIAL FORM):\n", sep = ""))
  cat(paste("    x = z / ", threshold, "\n", sep = ""))
  cat(paste("    p' = p_offset × exp(-", round(c, 4), " × (x^", round(a, 4),
            " × (1-x)^", round(b, 4), "))\n", sep = ""))
  cat(paste("    This form GUARANTEES p' > 0 for all parameter values\n\n"))
  
  cat("NOTE: For days with zero p_offset, z=0, x=0, and stretched_precipitation=0\n")
  cat("================================================================\n\n")
  
  # Return results invisibly
  invisible(list(
    data = output_data,
    parameters = list(
      threshold = threshold,
      stretch_factor = stretch_factor,
      a = a, b = b, c = c, d = d
    ),
    statistics = list(
      original_sum      = sum(precipitation),
      p_offset_sum      = p_offset_sum,
      stretched_sum     = stretched_sum,
      relative_diff     = relative_diff,
      convergence_error = final_error
    )
  ))
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) >= 2) {
    THRESHOLD      <- as.numeric(args[1])
    STRETCH_FACTOR <- as.numeric(args[2])
    cat(paste("Command-line parameters: threshold =", THRESHOLD, 
              ", stretch_factor =", STRETCH_FACTOR, "\n"))
  }
  
  if (length(args) >= 3) DAILY_WEATHER_FILE   <- args[3]
  if (length(args) >= 4) MONTHLY_OFFSETS_FILE <- args[4]
  if (length(args) >= 5) OUTPUT_FILE          <- args[5]
  
  result <- stretch_precipitation(
    daily_weather_file   = DAILY_WEATHER_FILE,
    monthly_offsets_file = MONTHLY_OFFSETS_FILE,
    output_file          = OUTPUT_FILE,
    threshold            = THRESHOLD,
    stretch_factor       = STRETCH_FACTOR
  )
}

# =============================================================================
# USAGE DOCUMENTATION
# =============================================================================
#
# USAGE OPTION 1: Modify CONFIGURATION SECTION and run
#   Rscript stretch_precipitation_standalone.R
#
# USAGE OPTION 2: Command line with parameters
#   Rscript stretch_precipitation_standalone.R <threshold> <stretch_factor> [daily_file] [offsets_file] [output]
#   Example: Rscript stretch_precipitation_standalone.R 75 20 daily_weather.csv monthly_delta_shifts.csv output.csv
#
# USAGE OPTION 3: Source and call as function
#   source("stretch_precipitation_standalone.R")
#   result <- stretch_precipitation(
#     daily_weather_file   = "daily_weather.csv",
#     monthly_offsets_file = "monthly_delta_shifts.csv",
#     output_file          = "output.csv",
#     threshold            = 75,
#     stretch_factor       = 20
#   )
#
# JSON BEHAVIOUR:
#   - If a file named <daily_weather_file_basename>.json exists alongside the
#     input CSV, its contents are loaded and carried into the output JSON.
#     Fields such as scenario_info.scenario_name and scenario_info.stretch_value
#     that are defined in the input JSON will be preserved in the output JSON.
#   - The output JSON is always written to <output_file_basename>.json.
#   - Generated sections (input_files, output_files, monthly_offsets_applied,
#     user_parameters, optimized_parameters, precipitation_results,
#     temperature_results, data_summary, scenario_info.date_created) are
#     computed fresh and override any matching keys from the input JSON.
