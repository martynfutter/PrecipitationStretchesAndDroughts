#' Stretch Precipitation Time Series with Temperature Offsets and Precipitation Multipliers
#'
#' This function reads precipitation and temperature data, applies monthly offsets/multipliers,
#' then stretches precipitation based on cumulative distribution while maintaining mass balance
#'
#' @param input_file Path to input CSV file with date, precipitation, and air_temperature columns
#' @param offset_file Path to CSV file with Month, PPctChange, and Toffset columns (default: "MonthlyDeltaShifts.csv")
#' @param output_file Path to output CSV file (default: "stretched_precipitation.csv")
#' @param threshold Threshold value t (0 <= t <= 100)
#' @param stretch_factor Stretch factor s (s >= 0)
#' @param date_format Date format string (default: "%Y-%m-%d")
#' @param tolerance Convergence tolerance for sum(p') vs sum(p) (default: 0.01 = 1%)
#' @param max_iter Maximum iterations for optimization (default: 1000)
#' @return Data frame with date, original values, shifted values, and stretched precipitation

stretch_precipitation_with_offsets <- function(input_file,
                                              offset_file = "MonthlyDeltaShifts.csv",
                                              output_file = "stretched_precipitation.csv",
                                              threshold,
                                              stretch_factor,
                                              date_format = "%Y-%m-%d",
                                              tolerance = 0.01,
                                              max_iter = 1000) {
  
  # Load required library
  if (!require(lubridate)) {
    install.packages("lubridate")
    library(lubridate)
  }
  
  # Validate input parameters
  if (threshold < 0 || threshold > 100) {
    stop("Threshold must be between 0 and 100")
  }
  if (stretch_factor < 0) {
    stop("Stretch factor must be >= 0")
  }
  
  # Read input data
  cat("Reading input file:", input_file, "\n")
  data <- read.csv(input_file, stringsAsFactors = FALSE)
  
  # Make column names case-insensitive and handle typos
  names(data) <- tolower(names(data))
  
  # Check for required columns
  date_col <- which(names(data) %in% c("date", "datetime", "time"))
  precip_col <- which(names(data) %in% c("precipitation", "precip", "precipitaition", "p", "pr"))
  temp_col <- which(names(data) %in% c("air_temperature", "temperature", "temp", "airtemp", "air_temp"))
  
  if (length(date_col) == 0) {
    stop("No date column found. Expected 'date', 'datetime', or 'time'")
  }
  if (length(precip_col) == 0) {
    stop("No precipitation column found. Expected 'precipitation', 'precip', or variants")
  }
  if (length(temp_col) == 0) {
    stop("No temperature column found. Expected 'air_temperature', 'temperature', or variants")
  }
  
  # Use first matching column if multiple found
  date_col <- date_col[1]
  precip_col <- precip_col[1]
  temp_col <- temp_col[1]
  
  # Rename columns for consistency
  names(data)[date_col] <- "date"
  names(data)[precip_col] <- "precipitation"
  names(data)[temp_col] <- "air_temperature"
  
  # Try multiple date formats if default fails
  date_formats <- c(date_format, "%Y-%m-%d", "%Y/%m/%d", "%m/%d/%Y", "%d/%m/%Y", 
                   "%Y-%m-%d %H:%M:%S", "%Y/%m/%d %H:%M:%S")
  
  data$date_parsed <- NA
  for (fmt in date_formats) {
    if (all(is.na(data$date_parsed))) {
      data$date_parsed <- as.Date(data$date, format = fmt)
      if (sum(!is.na(data$date_parsed)) > 0) {
        cat("Successfully parsed dates using format:", fmt, "\n")
        break
      }
    }
  }
  
  if (all(is.na(data$date_parsed))) {
    stop("Could not parse dates. Please specify correct date_format parameter")
  }
  
  data$date <- data$date_parsed
  data$date_parsed <- NULL
  
  # Extract month from date
  data$month <- month(data$date)
  
  # Read monthly offset file
  cat("Reading monthly offset file:", offset_file, "\n")
  if (!file.exists(offset_file)) {
    stop(paste("Offset file not found:", offset_file))
  }
  
  offsets <- read.csv(offset_file, stringsAsFactors = FALSE)
  names(offsets) <- tolower(names(offsets))
  
  # Check for required columns in offset file
  if (!all(c("month", "ppctchange", "toffset") %in% names(offsets))) {
    stop("Offset file must contain 'Month', 'PPctChange', and 'Toffset' columns")
  }
  
  # Ensure we have offsets for all 12 months
  if (nrow(offsets) != 12 || !all(1:12 %in% offsets$month)) {
    stop("Offset file must contain exactly 12 rows with months 1-12")
  }
  
  # Store original values
  data$original_precipitation <- data$precipitation
  data$original_temperature <- data$air_temperature
  
  # Apply monthly offsets
  cat("\nApplying monthly offsets...\n")
  
  # Initialize shifted columns
  data$shifted_precipitation <- data$precipitation
  data$shifted_temperature <- data$air_temperature
  
  # Apply offsets month by month
  for (m in 1:12) {
    month_mask <- data$month == m
    
    # Get offsets for this month
    ppct <- offsets$ppctchange[offsets$month == m]
    toff <- offsets$toffset[offsets$month == m]
    
    if (length(ppct) == 0 || length(toff) == 0) {
      warning(paste("Missing offsets for month", m, ". Using 0."))
      ppct <- 0
      toff <- 0
    }
    
    # Apply temperature offset to all days in this month
    data$shifted_temperature[month_mask] <- data$air_temperature[month_mask] + toff
    
    # Apply precipitation multiplier only to days with precipitation > 0
    precip_mask <- month_mask & data$precipitation > 0
    if (sum(precip_mask) > 0) {
      multiplier <- (100 + ppct) / 100
      data$shifted_precipitation[precip_mask] <- data$precipitation[precip_mask] * multiplier
    }
    
    cat("Month", m, ": PPctChange =", ppct, "%, Toffset =", toff, "°C\n")
  }
  
  # Calculate totals before and after shift
  original_precip_sum <- sum(data$original_precipitation, na.rm = TRUE)
  shifted_precip_sum <- sum(data$shifted_precipitation, na.rm = TRUE)
  
  cat("\nPrecipitation shift summary:\n")
  cat("Original total:", round(original_precip_sum, 4), "\n")
  cat("Shifted total:", round(shifted_precip_sum, 4), "\n")
  cat("Change:", round(shifted_precip_sum - original_precip_sum, 4), 
      "(", round((shifted_precip_sum / original_precip_sum - 1) * 100, 2), "%)\n")
  
  cat("\nTemperature shift summary:\n")
  cat("Original mean:", round(mean(data$original_temperature, na.rm = TRUE), 2), "°C\n")
  cat("Shifted mean:", round(mean(data$shifted_temperature, na.rm = TRUE), 2), "°C\n")
  cat("Mean change:", round(mean(data$shifted_temperature - data$original_temperature, na.rm = TRUE), 2), "°C\n")
  
  # Now apply stretching to the SHIFTED precipitation
  # Use shifted_precipitation as the base for stretching
  data$precipitation <- data$shifted_precipitation
  
  # Initialize stretched values
  data$stretched_precipitation <- 0
  data$stretch_factor_applied <- 0
  data$z_value <- NA
  
  # Function to calculate stretched precipitation for given parameters
  calculate_stretch <- function(params, data_in, threshold, stretch_factor, return_data = FALSE) {
    a <- params[1]
    b <- params[2]
    c <- params[3]
    d <- params[4]
    
    # Work with a copy
    data_work <- data_in
    
    # Extract non-zero precipitation values (using shifted values)
    non_zero_mask <- data_work$precipitation > 0
    non_zero_data <- data_work[non_zero_mask, ]
    
    if (nrow(non_zero_data) == 0) {
      if (return_data) return(data_work)
      else return(0)
    }
    
    # Sort non-zero precipitation values
    sorted_precip <- sort(non_zero_data$precipitation)
    n <- length(sorted_precip)
    
    # Calculate cumulative distribution (z) for each unique value
    unique_precip <- unique(sorted_precip)
    z_values <- numeric(length(unique_precip))
    
    for (i in seq_along(unique_precip)) {
      count_below <- sum(sorted_precip <= unique_precip[i])
      z_values[i] <- ((count_below - 0.5) / n) * 100
    }
    
    # Create lookup table
    z_lookup <- data.frame(
      precipitation = unique_precip,
      z = z_values
    )
    
    # Merge z values back to non-zero data
    non_zero_data <- merge(non_zero_data, z_lookup, by = "precipitation", all.x = TRUE)
    
    # Calculate stretched precipitation
    for (i in 1:nrow(non_zero_data)) {
      z <- non_zero_data$z[i]
      p <- non_zero_data$precipitation[i]
      
      if (z >= threshold) {
        if (threshold < 100) {
          x <- (z - threshold) / (100 - threshold)
        } else {
          x <- 0
        }
        stretch_mult <- ((100 + stretch_factor) / 100) * (x^d)
        p_prime <- p * stretch_mult
        
      } else {
        if (threshold > 0) {
          x <- z / threshold
        } else {
          x <- 0
        }
        stretch_mult <- c * ((x^a) * ((1 - x)^b))
        p_prime <- p * stretch_mult
      }
      
      non_zero_data$stretched_precipitation[i] <- p_prime
      non_zero_data$stretch_factor_applied[i] <- p_prime / p
      non_zero_data$z_value[i] <- z
    }
    
    if (return_data) {
      data_work$stretched_precipitation <- 0
      data_work$stretch_factor_applied <- 0
      data_work$z_value <- NA
      
      for (i in 1:nrow(data_work)) {
        if (data_work$precipitation[i] > 0) {
          matching_row <- non_zero_data[
            abs(non_zero_data$precipitation - data_work$precipitation[i]) < 1e-10 &
            non_zero_data$date == data_work$date[i], ]
          if (nrow(matching_row) > 0) {
            data_work$stretched_precipitation[i] <- matching_row$stretched_precipitation[1]
            data_work$stretch_factor_applied[i] <- matching_row$stretch_factor_applied[1]
            data_work$z_value[i] <- matching_row$z_value[1]
          }
        }
      }
      return(data_work)
    } else {
      return(sum(non_zero_data$stretched_precipitation))
    }
  }
  
  # Objective function for optimization
  objective <- function(params, data_in, threshold, stretch_factor, target_sum) {
    params <- abs(params)
    stretched_sum <- calculate_stretch(params, data_in, threshold, stretch_factor, FALSE)
    return(abs(stretched_sum - target_sum) / target_sum)
  }
  
  # Calculate target sum (shifted precipitation sum for mass balance)
  target_sum <- sum(data$precipitation[data$precipitation > 0])
  cat("\n=== STRETCHING SHIFTED PRECIPITATION ===\n")
  cat("Target precipitation sum (shifted):", round(target_sum, 4), "\n")
  
  # Initialize parameters
  initial_params <- c(a = 1.0, b = 1.0, c = 1.0, d = 1.0)
  
  cat("\nOptimizing parameters a, b, c, d...\n")
  
  # Optimize parameters using Nelder-Mead
  opt_result <- optim(
    par = initial_params,
    fn = objective,
    data_in = data,
    threshold = threshold,
    stretch_factor = stretch_factor,
    target_sum = target_sum,
    method = "Nelder-Mead",
    control = list(
      maxit = max_iter,
      abstol = tolerance,
      reltol = tolerance
    )
  )
  
  # Extract optimized parameters
  final_params <- abs(opt_result$par)
  names(final_params) <- c("a", "b", "c", "d")
  
  cat("\nOptimized parameters:\n")
  cat("a =", round(final_params[1], 6), "\n")
  cat("b =", round(final_params[2], 6), "\n")
  cat("c =", round(final_params[3], 6), "\n")
  cat("d =", round(final_params[4], 6), "\n")
  
  # Calculate final stretched precipitation with optimized parameters
  result_data <- calculate_stretch(final_params, data, threshold, stretch_factor, TRUE)
  
  # Calculate and display convergence
  final_sum <- sum(result_data$stretched_precipitation[result_data$precipitation > 0])
  convergence_error <- abs(final_sum - target_sum) / target_sum
  
  cat("\nConvergence results:\n")
  cat("Shifted precipitation sum:", round(target_sum, 4), "\n")
  cat("Stretched precipitation sum:", round(final_sum, 4), "\n")
  cat("Relative error:", round(convergence_error * 100, 4), "%\n")
  
  if (convergence_error > tolerance) {
    warning(paste("Convergence tolerance not met. Error:", 
                 round(convergence_error * 100, 4), "%"))
  } else {
    cat("Convergence achieved within tolerance (", tolerance * 100, "%)\n", sep="")
  }
  
  # Prepare output data with all relevant columns
  output_data <- data.frame(
    date = result_data$date,
    original_precipitation = result_data$original_precipitation,
    shifted_precipitation = result_data$shifted_precipitation,
    stretched_precipitation = result_data$stretched_precipitation,
    stretch_factor = result_data$stretch_factor_applied,
    original_temperature = result_data$original_temperature,
    shifted_temperature = result_data$shifted_temperature
  )
  
  # Sort by date
  output_data <- output_data[order(output_data$date), ]
  
  # Write to CSV
  write.csv(output_data, output_file, row.names = FALSE)
  cat("\nOutput saved to:", output_file, "\n")
  
  # Create metadata file
  metadata_file <- sub("\\.csv$", "_metadata.txt", output_file)
  metadata <- c(
    paste("Precipitation Stretching with Offsets - Metadata"),
    paste("Generated:", Sys.time()),
    paste("Input file:", input_file),
    paste("Offset file:", offset_file),
    paste("Output file:", output_file),
    paste("\nMonthly Offsets Applied:"),
    paste("  Temperature offsets: Yes"),
    paste("  Precipitation multipliers: Yes"),
    paste("\nUser Parameters:"),
    paste("  Threshold (t):", threshold),
    paste("  Stretch Factor (s):", stretch_factor),
    paste("\nOptimized Parameters:"),
    paste("  a:", round(final_params[1], 6)),
    paste("  b:", round(final_params[2], 6)),
    paste("  c:", round(final_params[3], 6)),
    paste("  d:", round(final_params[4], 6)),
    paste("\nPrecipitation Results:"),
    paste("  Original total:", round(original_precip_sum, 4)),
    paste("  Shifted total:", round(shifted_precip_sum, 4)),
    paste("  Stretched total:", round(final_sum, 4)),
    paste("  Shift change:", round((shifted_precip_sum / original_precip_sum - 1) * 100, 2), "%"),
    paste("  Relative error:", round(convergence_error * 100, 4), "%"),
    paste("  Days with precipitation:", sum(result_data$original_precipitation > 0)),
    paste("  Days without precipitation:", sum(result_data$original_precipitation == 0)),
    paste("\nTemperature Results:"),
    paste("  Original mean:", round(mean(output_data$original_temperature, na.rm = TRUE), 2), "°C"),
    paste("  Shifted mean:", round(mean(output_data$shifted_temperature, na.rm = TRUE), 2), "°C"),
    paste("  Mean change:", round(mean(output_data$shifted_temperature - output_data$original_temperature, na.rm = TRUE), 2), "°C")
  )
  
  writeLines(metadata, metadata_file)
  cat("Metadata saved to:", metadata_file, "\n")
  
  # Print summary
  cat("\n=== FINAL SUMMARY ===\n")
  cat("Total days processed:", nrow(output_data), "\n")
  cat("Date range:", as.character(min(output_data$date)), "to", as.character(max(output_data$date)), "\n")
  cat("\nPrecipitation transformation:\n")
  cat("  Original → Shifted → Stretched\n")
  cat("  ", round(original_precip_sum, 2), "→", 
      round(shifted_precip_sum, 2), "→", 
      round(final_sum, 2), "\n")
  cat("\nTemperature transformation:\n")
  cat("  Original mean → Shifted mean\n")
  cat("  ", round(mean(output_data$original_temperature, na.rm = TRUE), 2), "°C →",
      round(mean(output_data$shifted_temperature, na.rm = TRUE), 2), "°C\n")
  
  # Return the result data frame
  invisible(output_data)
}

# Example usage:
# result <- stretch_precipitation_with_offsets(
#   input_file = "short.csv",
#   offset_file = "MonthlyDeltaShifts.csv",
#   output_file = "stretched_precipitation.csv",
#   threshold = 95,        # 95th percentile threshold
#   stretch_factor = 50,   # 50% stretch for extreme events
#   date_format = "%Y-%m-%d",
#   tolerance = 0.01       # 1% convergence tolerance
# )