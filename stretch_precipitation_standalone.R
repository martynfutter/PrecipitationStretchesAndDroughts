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
    stop("Could not parse dates. Please use format like YYYY-MM-DD")
  })
  
  return(parsed_dates)
}

#' Calculate cumulative distribution percentiles (z)
#' Maps smallest non-zero value to z=0, largest to z=100
calculate_percentiles <- function(values) {
  n <- length(values)
  if (n == 0) return(numeric(0))
  
  ranks <- rank(values, ties.method = "average")
  percentiles <- ((ranks - 1) / (n - 1)) * 100
  
  return(percentiles)
}

#' Calculate stretch factor x and stretched precipitation p'
#' 
#' Formula (iv) for z >= t:
#'   x = (z - t) / (100 - t)
#'   p' = p_offset + (p_offset * (s/100) * x^d)
#' 
#' Formula (v) for z < t (EXPONENTIAL FORM - ALWAYS POSITIVE):
#'   x = z / t
#'   p' = p_offset × exp(-c × (x^a × (1-x)^b))
calculate_stretched_precip <- function(p_offset, z, threshold, stretch_factor, a, b, c, d) {
  if (z >= threshold) {
    # Formula (iv): For z >= t
    x <- (z - threshold) / (100 - threshold)
    p_prime <- p_offset + (p_offset * (stretch_factor / 100) * (x^d))
  } else {
    # Formula (v): For z < t (EXPONENTIAL FORM)
    x <- z / threshold
    beta_term <- x^a * (1 - x)^b
    p_prime <- p_offset * exp(-c * beta_term)
  }
  
  return(list(x = x, p_prime = p_prime))
}

#' Objective function for parameter optimization
objective_function <- function(params, precip_offset_values, percentiles, 
                               threshold, stretch_factor) {
  a <- params[1]
  b <- params[2]
  c <- params[3]
  d <- params[4]
  
  stretched_precip <- numeric(length(precip_offset_values))
  
  for (i in seq_along(precip_offset_values)) {
    z <- percentiles[i]
    p_offset <- precip_offset_values[i]
    
    result <- calculate_stretched_precip(p_offset, z, threshold, stretch_factor, a, b, c, d)
    stretched_precip[i] <- result$p_prime
  }
  
  original_sum <- sum(precip_offset_values)
  stretched_sum <- sum(stretched_precip)
  relative_error <- abs(stretched_sum - original_sum) / original_sum
  
  return(relative_error)
}

# =============================================================================
# MAIN PROCESSING FUNCTION
# =============================================================================

stretch_precipitation <- function(daily_weather_file = DAILY_WEATHER_FILE,
                                 monthly_offsets_file = MONTHLY_OFFSETS_FILE,
                                 output_file = OUTPUT_FILE,
                                 threshold = THRESHOLD,
                                 stretch_factor = STRETCH_FACTOR,
                                 initial_params = c(INITIAL_A, INITIAL_B, 
                                                   INITIAL_C, INITIAL_D),
                                 tolerance = CONVERGENCE_TOLERANCE) {
  
  cat("\n================================================================\n")
  cat("PRECIPITATION STRETCHING WITH MONTHLY OFFSETS\n")
  cat("================================================================\n\n")
  
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
  date_col <- find_column_name(weather_data, "date")
  temp_col <- find_column_name(weather_data, "temperature")
  precip_col <- find_column_name(weather_data, "precipitation")
  
  if (is.null(precip_col)) {
    precip_col <- find_column_name(weather_data, "p")
  }
  if (is.null(temp_col)) {
    temp_col <- find_column_name(weather_data, "air_temperature")
  }
  
  if (is.null(date_col)) {
    stop("Could not find 'date' column in weather file")
  }
  if (is.null(precip_col)) {
    stop("Could not find 'precipitation' or 'p' column in weather file")
  }
  if (is.null(temp_col)) {
    stop("Could not find 'temperature' column in weather file")
  }
  
  cat(paste("  Using columns: date='", date_col, "', temperature='", temp_col, 
            "', precipitation='", precip_col, "'\n", sep = ""))
  
  # Extract data
  dates <- parse_dates_flexible(weather_data[[date_col]])
  temperature <- as.numeric(weather_data[[temp_col]])
  precipitation <- as.numeric(weather_data[[precip_col]])
  
  # ---------------------------------------------------------------------------
  # Read monthly offsets file
  # ---------------------------------------------------------------------------
  cat("\nReading monthly offsets file...\n")
  
  if (!file.exists(monthly_offsets_file)) {
    stop(paste("Monthly offsets file not found:", monthly_offsets_file))
  }
  
  offsets_data <- read.csv(monthly_offsets_file, stringsAsFactors = FALSE)
  cat(paste("  Read", nrow(offsets_data), "rows from", monthly_offsets_file, "\n"))
  
  # Find columns (case-insensitive)
  month_col <- find_column_name(offsets_data, "month")
  ppct_col <- find_column_name(offsets_data, "ppctchange")
  toffset_col <- find_column_name(offsets_data, "toffset")
  
  if (is.null(month_col)) {
    stop("Could not find 'Month' column in offsets file")
  }
  if (is.null(ppct_col)) {
    stop("Could not find 'PPctChange' column in offsets file")
  }
  if (is.null(toffset_col)) {
    stop("Could not find 'TOffset' column in offsets file")
  }
  
  cat(paste("  Using columns: month='", month_col, "', ppctchange='", ppct_col, 
            "', toffset='", toffset_col, "'\n", sep = ""))
  
  # Create lookup table for offsets
  month_lookup <- data.frame(
    month = as.integer(offsets_data[[month_col]]),
    ppct_change = as.numeric(offsets_data[[ppct_col]]),
    t_offset = as.numeric(offsets_data[[toffset_col]])
  )
  
  if (nrow(month_lookup) != 12) {
    warning(paste("Expected 12 months in offsets file, found", nrow(month_lookup)))
  }
  
  cat("  Monthly offsets loaded:\n")
  for (i in 1:nrow(month_lookup)) {
    cat(sprintf("    Month %2d: PPctChange = %6.2f%%, TOffset = %6.2f°C\n",
                month_lookup$month[i], month_lookup$ppct_change[i], month_lookup$t_offset[i]))
  }
  
  # ---------------------------------------------------------------------------
  # Apply monthly offsets
  # ---------------------------------------------------------------------------
  cat("\nApplying monthly offsets to daily data...\n")
  
  # Extract month from each date
  months <- as.integer(format(dates, "%m"))
  
  # Initialize offset vectors
  p_offset <- numeric(length(precipitation))
  t_offset <- numeric(length(temperature))
  
  # Apply offsets month by month
  for (month in 1:12) {
    month_idx <- which(months == month)
    
    if (length(month_idx) > 0) {
      # Find offset values for this month
      offset_row <- which(month_lookup$month == month)
      
      if (length(offset_row) > 0) {
        ppct <- month_lookup$ppct_change[offset_row[1]]
        toff <- month_lookup$t_offset[offset_row[1]]
        
        # Apply offsets
        # p_offset = precipitation * (100 + PPctChange) / 100
        p_offset[month_idx] <- precipitation[month_idx] * (100 + ppct) / 100
        
        # t_offset = temperature + TOffset
        t_offset[month_idx] <- temperature[month_idx] + toff
      } else {
        warning(paste("No offset data found for month", month, "- using original values"))
        p_offset[month_idx] <- precipitation[month_idx]
        t_offset[month_idx] <- temperature[month_idx]
      }
    }
  }
  
  cat(paste("  Original precipitation sum:", round(sum(precipitation), 4), "\n"))
  cat(paste("  Offset precipitation sum:", round(sum(p_offset), 4), "\n"))
  cat(paste("  Original temperature mean:", round(mean(temperature, na.rm = TRUE), 2), "°C\n"))
  cat(paste("  Offset temperature mean:", round(mean(t_offset, na.rm = TRUE), 2), "°C\n"))
  
  # Validate parameters
  if (threshold < 0 || threshold > 100) {
    stop("Threshold must be between 0 and 100")
  }
  if (stretch_factor < 0) {
    stop("Stretch factor must be >= 0")
  }
  
  cat(paste("\n  User parameters:\n"))
  cat(paste("    Threshold (t) =", threshold, "\n"))
  cat(paste("    Stretch factor (s) =", stretch_factor, "\n"))
  
  # ---------------------------------------------------------------------------
  # STEP (i): Identify non-zero p_offset values
  # ---------------------------------------------------------------------------
  cat("\nSTEP (i): Identifying non-zero p_offset values for sorting...\n")
  
  non_zero_idx <- which(p_offset > 0)
  non_zero_p_offset <- p_offset[non_zero_idx]
  
  cat(paste("  Total records:", length(p_offset), "\n"))
  cat(paste("  Non-zero p_offset records:", length(non_zero_p_offset), "\n"))
  cat(paste("  Zero p_offset records:", length(p_offset) - length(non_zero_p_offset), "\n"))
  
  if (length(non_zero_p_offset) == 0) {
    stop("No non-zero p_offset values found")
  }
  
  # ---------------------------------------------------------------------------
  # STEP (ii): Calculate cumulative distribution (z)
  # ---------------------------------------------------------------------------
  cat("\nSTEP (ii): Calculating cumulative distribution percentiles (z)...\n")
  
  percentiles <- calculate_percentiles(non_zero_p_offset)
  
  cat(paste("  z range:", round(min(percentiles), 2), "to", 
            round(max(percentiles), 2), "\n"))
  cat(paste("  Smallest non-zero p_offset (z=0):", round(min(non_zero_p_offset), 4), "\n"))
  cat(paste("  Largest non-zero p_offset (z=100):", round(max(non_zero_p_offset), 4), "\n"))
  
  # ---------------------------------------------------------------------------
  # STEP (vii): Optimize parameters a, b, c, d
  # ---------------------------------------------------------------------------
  cat("\nSTEP (vii): Optimizing parameters a, b, c, d...\n")
  cat(paste("  Initial values: a =", initial_params[1], ", b =", initial_params[2],
            ", c =", initial_params[3], ", d =", initial_params[4], "\n"))
  cat(paste("  Convergence target: sum(p') within", tolerance * 100, "% of sum(p_offset)\n"))
  cat("  Using EXPONENTIAL FORM for formula (v) - guarantees non-negativity\n")
  
  opt_result <- optim(
    par = initial_params,
    fn = objective_function,
    precip_offset_values = non_zero_p_offset,
    percentiles = percentiles,
    threshold = threshold,
    stretch_factor = stretch_factor,
    method = "Nelder-Mead",
    control = list(maxit = MAX_ITERATIONS)
  )
  
  optimized_params <- opt_result$par
  final_error <- opt_result$value
  
  a <- optimized_params[1]
  b <- optimized_params[2]
  c <- optimized_params[3]
  d <- optimized_params[4]
  
  cat(paste("\n  Optimized parameters:\n"))
  cat(paste("    a =", round(a, 6), "\n"))
  cat(paste("    b =", round(b, 6), "\n"))
  cat(paste("    c =", round(c, 6), "\n"))
  cat(paste("    d =", round(d, 6), "\n"))
  cat(paste("  Final relative error:", round(final_error * 100, 4), "%\n"))
  
  if (final_error <= tolerance) {
    cat("  ✓ SUCCESS: Convergence achieved!\n")
  } else {
    cat("  ⚠ WARNING: Did not converge within tolerance\n")
  }
  
  # ---------------------------------------------------------------------------
  # STEPS (iii-vi): Calculate stretched precipitation
  # ---------------------------------------------------------------------------
  cat("\nSTEPS (iii-vi): Applying stretching formulas and calculating sums...\n")
  
  # Initialize output vectors (all zeros by default)
  z_values <- numeric(length(p_offset))
  stretch_factor_x <- numeric(length(p_offset))
  stretched_precip <- numeric(length(p_offset))
  
  # Process non-zero p_offset values
  for (i in seq_along(non_zero_idx)) {
    idx <- non_zero_idx[i]
    z <- percentiles[i]
    p_off <- p_offset[idx]
    
    z_values[idx] <- z
    
    # Apply formulas (iv) and (v)
    result <- calculate_stretched_precip(p_off, z, threshold, stretch_factor, a, b, c, d)
    stretch_factor_x[idx] <- result$x
    stretched_precip[idx] <- result$p_prime
  }
  
  # Verify non-negativity
  if (any(stretched_precip < 0)) {
    warning("Some negative stretched precipitation values detected! This should not happen with exponential form.")
  }
  
  # Calculate sums (step vi)
  p_offset_sum <- sum(p_offset)
  stretched_sum <- sum(stretched_precip)
  relative_diff <- (stretched_sum - p_offset_sum) / p_offset_sum * 100
  
  cat(paste("  sum(p_offset):", round(p_offset_sum, 4), "\n"))
  cat(paste("  sum(p'):", round(stretched_sum, 4), "\n"))
  cat(paste("  Relative difference:", round(relative_diff, 4), "%\n"))
  cat(paste("  Min stretched precipitation:", round(min(stretched_precip[stretched_precip > 0]), 6), "\n"))
  cat(paste("  Max stretched precipitation:", round(max(stretched_precip), 4), "\n"))
  
  # ---------------------------------------------------------------------------
  # OUTPUT: Save results
  # ---------------------------------------------------------------------------
  cat("\nSaving output...\n")
  
  output_data <- data.frame(
    date = dates,
    temperature = temperature,
    precipitation = precipitation,
    t_offset = t_offset,
    p_offset = p_offset,
    z = z_values,
    x = stretch_factor_x,
    stretched_precipitation = stretched_precip
  )
  
  write.csv(output_data, output_file, row.names = FALSE)
  cat(paste("  ✓ Output saved to:", output_file, "\n"))
  cat(paste("  Output columns:", paste(names(output_data), collapse = ", "), "\n"))
  
  # ---------------------------------------------------------------------------
  # SUMMARY
  # ---------------------------------------------------------------------------
  cat("\n================================================================\n")
  cat("SUMMARY\n")
  cat("================================================================\n")
  cat(paste("Daily weather file:", daily_weather_file, "\n"))
  cat(paste("Monthly offsets file:", monthly_offsets_file, "\n"))
  cat(paste("Output file:", output_file, "\n"))
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
  cat(paste("    p' = p_offset × exp(-", round(c, 4), " × (x^", round(a, 4), " × (1-x)^", round(b, 4), "))\n", sep = ""))
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
      original_sum = sum(precipitation),
      p_offset_sum = p_offset_sum,
      stretched_sum = stretched_sum,
      relative_diff = relative_diff,
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
    THRESHOLD <- as.numeric(args[1])
    STRETCH_FACTOR <- as.numeric(args[2])
    cat(paste("Command-line parameters: threshold =", THRESHOLD, 
              ", stretch_factor =", STRETCH_FACTOR, "\n"))
  }
  
  if (length(args) >= 3) DAILY_WEATHER_FILE <- args[3]
  if (length(args) >= 4) MONTHLY_OFFSETS_FILE <- args[4]
  if (length(args) >= 5) OUTPUT_FILE <- args[5]
  
  result <- stretch_precipitation(
    daily_weather_file = DAILY_WEATHER_FILE,
    monthly_offsets_file = MONTHLY_OFFSETS_FILE,
    output_file = OUTPUT_FILE,
    threshold = THRESHOLD,
    stretch_factor = STRETCH_FACTOR
  )
}

# =============================================================================
# USAGE DOCUMENTATION
# =============================================================================

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
#     daily_weather_file = "daily_weather.csv",
#     monthly_offsets_file = "monthly_delta_shifts.csv",
#     output_file = "output.csv",
#     threshold = 75,
#     stretch_factor = 20
#   )
#
# INPUT FILE 1 - DAILY WEATHER:
#   CSV with columns: date, temperature, precipitation (or p)
#   - date: YYYY-MM-DD format (or other common formats)
#   - temperature: numeric
#   - precipitation: numeric
#   - All column name comparisons are case-insensitive
#
# INPUT FILE 2 - MONTHLY OFFSETS:
#   CSV with columns: Month, PPctChange, TOffset
#   - Month: 1-12 (integer)
#   - PPctChange: Precipitation percentage change
#   - TOffset: Temperature offset in °C
#   - Should contain 12 rows (one per month)
#
# OUTPUT FILE FORMAT:
#   CSV with columns:
#   - date: original date
#   - temperature: original temperature
#   - precipitation: original precipitation (p)
#   - t_offset: temperature + TOffset
#   - p_offset: precipitation × (100 + PPctChange) / 100
#   - z: cumulative distribution percentile (0-100)
#   - x: stretch factor
#   - stretched_precipitation: stretched precipitation (p')
#
# ALGORITHM:
#   1. Apply monthly offsets: p_offset = p × (100 + PPctChange)/100
#                            t_offset = temperature + TOffset
#   (i)   Sort non-zero p_offset values in ascending order
#   (ii)  Calculate z (cumulative distribution 0-100) for each p_offset
#   (iii) Apply different formulas based on whether z >= t
#   (iv)  For z >= t: x=(z-t)/(100-t), p'=p_offset+(p_offset*(s/100)*x^d)
#   (v)   For z < t: x=z/t, p'=p_offset × exp(-c × (x^a × (1-x)^b))
#         ** EXPONENTIAL FORM guarantees p' > 0 always **
#   (vi)  Calculate sum(p') and compare to sum(p_offset)
#   (vii) Optimize a,b,c,d so sum(p') converges to sum(p_offset) within 1%
#
# FORMULA (v) NOTES:
#   The exponential form p' = p_offset × exp(-c × (x^a × (1-x)^b)) ensures:
#   - p' is ALWAYS positive (since exp(anything) > 0)
#   - p' is bounded: 0 < p' ≤ p_offset (since exp(-value) ≤ 1 for value ≥ 0)
#   - When c is positive, precipitation is reduced
#   - When c is negative, precipitation is increased (but still bounded)
#   - Maximum reduction/increase occurs when x^a × (1-x)^b is maximized
