#' Simulate Spring/Summer Droughts with Monthly Delta Shifts
#'
#' This function applies monthly precipitation and temperature shifts before
#' simulating droughts by reducing precipitation in spring/summer (March-August)
#' and redistributing it to fall/winter (September-February).
#'
#' @param input_file Path to input CSV file (default: "short.csv")
#' @param output_file Path to output CSV file (default: "drought_delta_shifted.csv")
#' @param delta_file Path to monthly delta shifts CSV (default: "MonthlyDeltaShifts.csv")
#' @param drought_factor Fraction of spring/summer precipitation to retain (default: 0.75)
#' @return A data frame with original, delta-shifted, and drought-adjusted values
#'
drought_simulation_with_shifts <- function(input_file = "short.csv", 
                                          output_file = "drought_delta_shifted.csv",
                                          delta_file = "MonthlyDeltaShifts.csv",
                                          drought_factor = 0.75) {
  
  # Load required libraries
  if (!require(lubridate)) {
    install.packages("lubridate")
    library(lubridate)
  }
  
  # Helper function for flexible date parsing
  parse_date_flexible <- function(date_string) {
    formats <- c("%Y-%m-%d", "%Y/%m/%d", "%Y.%m.%d", "%Y %m %d", 
                 "%Y-%m-%d %H:%M:%S", "%Y/%m/%d %H:%M:%S")
    
    for (fmt in formats) {
      result <- tryCatch(as.Date(date_string, format = fmt), 
                        error = function(e) NULL, 
                        warning = function(w) NULL)
      if (!is.null(result) && !all(is.na(result))) {
        return(result)
      }
    }
    
    result <- tryCatch(ymd(date_string), 
                      error = function(e) NULL, 
                      warning = function(w) NULL)
    if (!is.null(result) && !all(is.na(result))) {
      return(result)
    }
    
    stop("Could not parse dates. Please ensure dates are in year-month-day format.")
  }
  
  # Validate drought factor
  if (drought_factor < 0 || drought_factor > 1) {
    stop("drought_factor must be between 0 and 1")
  }
  
  # Check input files exist
  if (!file.exists(input_file)) {
    stop(paste("Input file not found:", input_file))
  }
  if (!file.exists(delta_file)) {
    stop(paste("Delta shifts file not found:", delta_file))
  }
  
  # Read the input file
  cat("Reading input file:", input_file, "\n")
  data <- read.csv(input_file, stringsAsFactors = FALSE)
  
  if (nrow(data) == 0) {
    stop("Input file is empty")
  }
  
  # Find columns (case insensitive)
  date_col <- names(data)[grep("^date$", names(data), ignore.case = TRUE)]
  precip_col <- names(data)[grep("^precip", names(data), ignore.case = TRUE)]
  temp_col <- names(data)[grep("temperature|temp", names(data), ignore.case = TRUE)]
  
  if (length(date_col) == 0) {
    stop("Could not find 'date' column in the input file")
  }
  if (length(precip_col) == 0) {
    stop("Could not find 'precipitation' column in the input file")
  }
  if (length(temp_col) == 0) {
    stop("Could not find 'temperature' column in the input file")
  }
  
  date_col <- date_col[1]
  precip_col <- precip_col[1]
  temp_col <- temp_col[1]
  
  cat("Using columns:", date_col, ",", precip_col, ", and", temp_col, "\n")
  
  # Read monthly delta shifts
  cat("Reading monthly delta shifts from:", delta_file, "\n")
  delta_shifts <- read.csv(delta_file, stringsAsFactors = FALSE)
  
  # Validate delta shifts file
  if (!all(c("Month", "PPctChange", "Toffest") %in% names(delta_shifts))) {
    stop("Delta shifts file must contain 'Month', 'PPctChange', and 'Toffest' columns")
  }
  
  # Parse dates and values
  data$Date <- parse_date_flexible(data[[date_col]])
  data$precipitation <- as.numeric(data[[precip_col]])
  data$air_temperature <- as.numeric(data[[temp_col]])
  
  # Remove rows with invalid data
  invalid_dates <- is.na(data$Date)
  invalid_precip <- is.na(data$precipitation)
  invalid_temp <- is.na(data$air_temperature)
  
  if (sum(invalid_dates) > 0) {
    cat("Warning: Removing", sum(invalid_dates), "rows with invalid dates\n")
  }
  if (sum(invalid_precip) > 0) {
    cat("Warning: Removing", sum(invalid_precip), "rows with invalid precipitation\n")
  }
  if (sum(invalid_temp) > 0) {
    cat("Warning: Removing", sum(invalid_temp), "rows with invalid temperature\n")
  }
  
  data <- data[!invalid_dates & !invalid_precip & !invalid_temp, ]
  
  if (nrow(data) == 0) {
    stop("No valid data found after parsing")
  }
  
  # Sort by date
  data <- data[order(data$Date), ]
  
  # Extract year and month
  data$Year <- year(data$Date)
  data$Month <- month(data$Date)
  
  # ===================================================================
  # STEP 1: Apply monthly delta shifts
  # ===================================================================
  cat("\nApplying monthly delta shifts...\n")
  
  data$precipitation_ds <- data$precipitation
  data$air_temperature_ds <- data$air_temperature
  
  for (i in 1:nrow(data)) {
    current_month <- data$Month[i]
    
    # Get shifts for this month
    month_shifts <- delta_shifts[delta_shifts$Month == current_month, ]
    
    if (nrow(month_shifts) == 0) {
      warning(paste("No delta shifts found for month", current_month, ". Using original values."))
      next
    }
    
    pct_change <- month_shifts$PPctChange[1]
    temp_offset <- month_shifts$Toffest[1]
    
    # Apply precipitation multiplier only for days with precipitation > 0
    if (data$precipitation[i] > 0) {
      data$precipitation_ds[i] <- data$precipitation[i] * (100 + pct_change) / 100
    }
    
    # Apply temperature offset to all days
    data$air_temperature_ds[i] <- data$air_temperature[i] + temp_offset
  }
  
  cat("Delta shifts applied successfully.\n")
  cat("Original total precipitation:", round(sum(data$precipitation, na.rm = TRUE), 4), "\n")
  cat("Delta-shifted total precipitation:", round(sum(data$precipitation_ds, na.rm = TRUE), 4), "\n")
  cat("Original mean temperature:", round(mean(data$air_temperature, na.rm = TRUE), 4), "\n")
  cat("Delta-shifted mean temperature:", round(mean(data$air_temperature_ds, na.rm = TRUE), 4), "\n")
  
  # ===================================================================
  # STEP 2: Apply drought simulation to delta-shifted precipitation
  # ===================================================================
  cat("\nApplying drought simulation to delta-shifted precipitation...\n")
  
  # Assign seasons
  data$Season <- ifelse(data$Month %in% 3:8, "springSummer", "fallWinter")
  
  # Assign season year
  data$SeasonYear <- ifelse(data$Season == "fallWinter" & data$Month %in% 1:2, 
                           data$Year - 1, 
                           data$Year)
  
  # Calculate seasonal precipitation totals using delta-shifted values
  seasonal_totals <- aggregate(precipitation_ds ~ SeasonYear + Season, 
                              data = data, FUN = sum, na.rm = TRUE)
  
  # Reshape to get spring/summer and fall/winter totals
  seasonal_wide <- reshape(seasonal_totals, 
                          idvar = "SeasonYear", 
                          timevar = "Season", 
                          direction = "wide")
  
  # Rename columns
  if ("precipitation_ds.springSummer" %in% names(seasonal_wide)) {
    names(seasonal_wide)[names(seasonal_wide) == "precipitation_ds.springSummer"] <- "springSummer_total"
  } else {
    seasonal_wide$springSummer_total <- 0
  }
  
  if ("precipitation_ds.fallWinter" %in% names(seasonal_wide)) {
    names(seasonal_wide)[names(seasonal_wide) == "precipitation_ds.fallWinter"] <- "fallWinter_total"
  } else {
    seasonal_wide$fallWinter_total <- 0
  }
  
  seasonal_wide[is.na(seasonal_wide)] <- 0
  
  # Calculate precipitation to shift
  seasonal_wide$p2shift <- seasonal_wide$springSummer_total * (1 - drought_factor)
  
  # Initialize drought-adjusted columns
  data$drought_precipitation_ds <- data$precipitation_ds
  data$drought_scaling_factor <- 1.0
  
  # Process each season year
  for (year in unique(seasonal_wide$SeasonYear)) {
    year_data <- seasonal_wide[seasonal_wide$SeasonYear == year, ]
    
    if (nrow(year_data) == 0) next
    
    p2shift <- year_data$p2shift
    fallWinter_total <- year_data$fallWinter_total
    springSummer_total <- year_data$springSummer_total
    
    # Reduce spring/summer precipitation
    spring_summer_mask <- data$SeasonYear == year & data$Season == "springSummer"
    if (sum(spring_summer_mask) > 0) {
      data$drought_precipitation_ds[spring_summer_mask] <- 
        data$precipitation_ds[spring_summer_mask] * drought_factor
      data$drought_scaling_factor[spring_summer_mask] <- drought_factor
    }
    
    # Redistribute to fall/winter days with precipitation
    fall_winter_mask <- data$SeasonYear == year & 
                        data$Season == "fallWinter" & 
                        data$precipitation_ds > 0
    
    if (sum(fall_winter_mask) > 0 && fallWinter_total > 0 && p2shift > 0) {
      fall_winter_indices <- which(fall_winter_mask)
      
      for (i in fall_winter_indices) {
        day_proportion <- data$precipitation_ds[i] / fallWinter_total
        added_amount <- p2shift * day_proportion
        data$drought_precipitation_ds[i] <- data$precipitation_ds[i] + added_amount
        data$drought_scaling_factor[i] <- data$drought_precipitation_ds[i] / data$precipitation_ds[i]
      }
    }
  }
  
  cat("Drought simulation applied successfully.\n")
  
  # ===================================================================
  # STEP 3: Create output dataframe
  # ===================================================================
  output_data <- data.frame(
    date = data$Date,
    precipitation = data$precipitation,
    air_temperature = data$air_temperature,
    precipitation_ds = data$precipitation_ds,
    drought_precipitation_ds = data$drought_precipitation_ds,
    air_temperature_ds = data$air_temperature_ds
  )
  
  # Write output file
  write.csv(output_data, output_file, row.names = FALSE)
  
  # ===================================================================
  # STEP 4: Calculate and display summary statistics
  # ===================================================================
  total_original_precip <- sum(data$precipitation, na.rm = TRUE)
  total_ds_precip <- sum(data$precipitation_ds, na.rm = TRUE)
  total_drought_ds_precip <- sum(data$drought_precipitation_ds, na.rm = TRUE)
  
  mean_original_temp <- mean(data$air_temperature, na.rm = TRUE)
  mean_ds_temp <- mean(data$air_temperature_ds, na.rm = TRUE)
  
  mass_balance_ds <- abs(total_ds_precip - total_drought_ds_precip)
  
  spring_summer_days <- sum(data$Season == "springSummer")
  fall_winter_days <- sum(data$Season == "fallWinter")
  spring_summer_precip_days <- sum(data$Season == "springSummer" & data$precipitation_ds > 0)
  fall_winter_precip_days <- sum(data$Season == "fallWinter" & data$precipitation_ds > 0)
  
  cat("\n=== DROUGHT SIMULATION WITH DELTA SHIFTS SUMMARY ===\n")
  cat("Input file:", input_file, "\n")
  cat("Delta shifts file:", delta_file, "\n")
  cat("Output file:", output_file, "\n")
  cat("Drought reduction factor:", drought_factor, "\n")
  cat("Total records processed:", nrow(output_data), "\n")
  cat("Date range:", as.character(min(data$Date)), "to", as.character(max(data$Date)), "\n")
  cat("Years processed:", min(data$Year), "to", max(data$Year), "\n")
  
  cat("\n=== DELTA SHIFTS APPLIED ===\n")
  cat("Original total precipitation:", round(total_original_precip, 4), "\n")
  cat("Delta-shifted total precipitation:", round(total_ds_precip, 4), "\n")
  cat("Precipitation change from delta shifts:", round(total_ds_precip - total_original_precip, 4), 
      "(", round((total_ds_precip - total_original_precip) / total_original_precip * 100, 2), "%)\n")
  cat("\nOriginal mean temperature:", round(mean_original_temp, 4), "°C\n")
  cat("Delta-shifted mean temperature:", round(mean_ds_temp, 4), "°C\n")
  cat("Temperature change from delta shifts:", round(mean_ds_temp - mean_original_temp, 4), "°C\n")
  
  cat("\n=== DROUGHT SIMULATION RESULTS ===\n")
  cat("Seasonal breakdown:\n")
  cat("  Spring/summer days:", spring_summer_days, "(with precip:", spring_summer_precip_days, ")\n")
  cat("  Fall/winter days:", fall_winter_days, "(with precip:", fall_winter_precip_days, ")\n")
  
  cat("\nPrecipitation after drought simulation:\n")
  cat("  Delta-shifted total:", round(total_ds_precip, 4), "\n")
  cat("  Drought+delta-shifted total:", round(total_drought_ds_precip, 4), "\n")
  cat("  Mass balance difference:", round(mass_balance_ds, 6), "\n")
  
  if (mass_balance_ds > 0.001) {
    cat("  Warning: Mass balance error detected.\n")
  } else {
    cat("  Mass balance preserved successfully.\n")
  }
  
  # Scaling factor statistics
  spring_factors <- data$drought_scaling_factor[data$Season == "springSummer"]
  winter_factors <- data$drought_scaling_factor[data$Season == "fallWinter" & data$precipitation_ds > 0]
  
  cat("\nDrought scaling factor statistics:\n")
  cat("  Spring/summer scaling factor:", round(mean(spring_factors, na.rm = TRUE), 3), "\n")
  if (length(winter_factors) > 0) {
    cat("  Fall/winter scaling factors - Min:", round(min(winter_factors, na.rm = TRUE), 3),
        "Max:", round(max(winter_factors, na.rm = TRUE), 3),
        "Mean:", round(mean(winter_factors, na.rm = TRUE), 3), "\n")
  }
  
  cat("\nOutput saved successfully to:", output_file, "\n")
  
  return(output_data)
}

# Example usage:
# Basic usage with defaults
# result <- drought_simulation_with_shifts()

# Custom parameters
# result <- drought_simulation_with_shifts(
#   input_file = "short.csv",
#   output_file = "drought_delta_shifted.csv",
#   delta_file = "MonthlyDeltaShifts.csv",
#   drought_factor = 0.75
# )

# Run with default parameters
cat("=== DROUGHT SIMULATION WITH DELTA SHIFTS FUNCTION LOADED ===\n")
cat("To use: result <- drought_simulation_with_shifts()\n")
cat("Or with custom parameters:\n")
cat("result <- drought_simulation_with_shifts('short.csv', 'output.csv', 'MonthlyDeltaShifts.csv', 0.75)\n")