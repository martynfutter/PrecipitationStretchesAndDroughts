# ===================================================================
# Drought Simulation with Delta Shifts
# ===================================================================
# This script applies monthly delta shifts (temperature offsets and 
# precipitation percentage changes) followed by drought simulation
# (redistributing spring/summer precipitation to fall/winter).
#
# Author: Modified version with JSON metadata output
# Date: 2025
# ===================================================================

# Function to parse dates flexibly
parse_date_flexible <- function(date_strings) {
  if (!require(lubridate)) {
    install.packages("lubridate")
    library(lubridate)
  }
  
  dates <- as.Date(date_strings, format = "%Y-%m-%d")
  if (sum(is.na(dates)) > 0.5 * length(dates)) {
    dates <- parse_date_time(date_strings, 
                            orders = c("ymd", "mdy", "dmy", "ymd HMS", "mdy HMS"))
    dates <- as.Date(dates)
  }
  
  return(dates)
}

# Main function
drought_simulation_with_shifts <- function(input_file = "short.csv",
                                          output_file = "dailyWeatherScenario.csv",
                                          delta_file = "MonthlyDeltaShifts.csv",
                                          drought_factor = 0.75) {
  
  # Load required libraries
  if (!require(lubridate)) {
    install.packages("lubridate")
    library(lubridate)
  }
  if (!require(jsonlite)) {
    install.packages("jsonlite")
    library(jsonlite)
  }
  
  cat("=== DROUGHT SIMULATION WITH DELTA SHIFTS ===\n")
  cat("This function applies a two-stage transformation:\n")
  cat("  Stage 1: Monthly delta shifts (climate change projections)\n")
  cat("  Stage 2: Drought simulation (seasonal precipitation redistribution)\n\n")
  
  # Validate parameters
  if (!is.character(input_file) || !is.character(output_file) || !is.character(delta_file)) {
    stop("File paths must be character strings. 
Please ensure dates are in year-month-day format.")
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
  
  # Validate delta shifts file (case insensitive check)
  delta_names <- names(delta_shifts)
  month_col <- delta_names[grep("^month$", delta_names, ignore.case = TRUE)]
  ppct_col <- delta_names[grep("^ppctchange$", delta_names, ignore.case = TRUE)]
  toff_col <- delta_names[grep("^toff", delta_names, ignore.case = TRUE)]
  
  if (length(month_col) == 0 || length(ppct_col) == 0 || length(toff_col) == 0) {
    stop("Delta shifts file must contain 'Month', 'PPctChange', and 'Toffest' columns (case insensitive)")
  }
  
  # Rename to standard names
  names(delta_shifts)[grep("^month$", names(delta_shifts), ignore.case = TRUE)] <- "Month"
  names(delta_shifts)[grep("^ppctchange$", names(delta_shifts), ignore.case = TRUE)] <- "PPctChange"
  names(delta_shifts)[grep("^toff", names(delta_shifts), ignore.case = TRUE)] <- "Toffest"
  
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
    stop("No valid data remaining after removing invalid rows")
  }
  
  # Extract month and year from date
  data$Month <- month(data$Date)
  data$Year <- year(data$Date)
  
  # Initialize delta-shifted columns
  data$precipitation_ds <- data$precipitation
  data$air_temperature_ds <- data$air_temperature
  
  # ===================================================================
  # STEP 1: Apply monthly delta shifts
  # ===================================================================
  cat("\nApplying monthly delta shifts...\n")
  
  for (i in 1:nrow(data)) {
    current_month <- data$Month[i]
    
    month_shifts <- delta_shifts[delta_shifts$Month == current_month, ]
    
    if (nrow(month_shifts) == 0) {
      warning(paste("No delta shifts found for month", current_month, 
                   "Using original values."))
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
  # STEP 3: Create output dataframe with new column names
  # ===================================================================
  output_data <- data.frame(
    Date = data$Date,
    OriginalPrecipitation = data$precipitation,
    DeltaShiftPrecipitation = data$precipitation_ds,
    OriginalTemperature = data$air_temperature,
    DeltaShiftTemperature = data$air_temperature_ds,
    ScenarioPrecipitation = data$drought_precipitation_ds
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
  
  # ===================================================================
  # STEP 5: Create JSON metadata file
  # ===================================================================
  cat("\nCreating JSON metadata file...\n")
  
  # Read and store monthly delta shifts data
  monthly_deltas <- list()
  for (m in 1:12) {
    monthly_deltas[[paste0("Month_", m)]] <- list(
      PPctChange = delta_shifts$PPctChange[delta_shifts$Month == m],
      Toffest = delta_shifts$Toffest[delta_shifts$Month == m]
    )
  }
  
  # Calculate drought scaling factors by year (fall/winter only)
  scaling_by_year <- list()
  for (year in sort(unique(data$Year))) {
    year_mask <- data$Year == year & data$Season == "fallWinter"
    fw_factor <- mean(data$drought_scaling_factor[year_mask], na.rm = TRUE)
    
    scaling_by_year[[length(scaling_by_year) + 1]] <- list(
      year = as.integer(year),
      fall_winter_factor = round(fw_factor, 6)
    )
  }
  
  # Create comprehensive metadata structure
  metadata <- list(
    scenario_info = list(
      scenario_type = "Drought",
      scenario_name = "Drought Simulation with Delta Shifts",
      date_created = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      drought_reduction_factor = drought_factor
    ),
    input_files = list(
      input_file = input_file,
      delta_shifts_source = delta_file
    ),
    output_files = list(
      csv_file = output_file,
      metadata_file = "dailyWeatherScenario.json"
    ),
    monthly_delta_shifts_applied = monthly_deltas,
    summary_statistics = list(
      total_records_processed = nrow(output_data),
      date_range_start = as.character(min(data$Date)),
      date_range_end = as.character(max(data$Date)),
      years_processed_min = min(data$Year),
      years_processed_max = max(data$Year)
    ),
    delta_shifts_results = list(
      original_total_precipitation = round(total_original_precip, 4),
      delta_shifted_total_precipitation = round(total_ds_precip, 4),
      precipitation_change_from_delta_shifts = round(total_ds_precip - total_original_precip, 4),
      precipitation_change_percent = round((total_ds_precip - total_original_precip) / total_original_precip * 100, 2),
      original_mean_temperature = round(mean_original_temp, 4),
      delta_shifted_mean_temperature = round(mean_ds_temp, 4),
      temperature_change_from_delta_shifts = round(mean_ds_temp - mean_original_temp, 4)
    ),
    drought_simulation_results = list(
      seasonal_breakdown = list(
        spring_summer_days = spring_summer_days,
        spring_summer_precip_days = spring_summer_precip_days,
        fall_winter_days = fall_winter_days,
        fall_winter_precip_days = fall_winter_precip_days
      ),
      precipitation_totals = list(
        delta_shifted_total = round(total_ds_precip, 4),
        drought_delta_shifted_total = round(total_drought_ds_precip, 4),
        mass_balance_difference = round(mass_balance_ds, 6),
        mass_balance_preserved = mass_balance_ds <= 0.001
      ),
      scaling_factor_statistics = list(
        spring_summer_scaling_factor = round(mean(spring_factors, na.rm = TRUE), 3),
        fall_winter_scaling_factor_min = if(length(winter_factors) > 0) round(min(winter_factors, na.rm = TRUE), 3) else NA,
        fall_winter_scaling_factor_max = if(length(winter_factors) > 0) round(max(winter_factors, na.rm = TRUE), 3) else NA,
        fall_winter_scaling_factor_mean = if(length(winter_factors) > 0) round(mean(winter_factors, na.rm = TRUE), 3) else NA
      )
    ),
    drought_scaling_factors_by_year = scaling_by_year
  )
  
  # Write JSON file with pretty formatting
  json_file <- "dailyWeatherScenario.json"
  write_json(metadata, json_file, pretty = TRUE, auto_unbox = TRUE)
  cat("Metadata JSON saved to:", json_file, "\n")
  
  return(output_data)
}

# Example usage:
# Basic usage with defaults
# result <- drought_simulation_with_shifts()

# Custom parameters
# result <- drought_simulation_with_shifts(
#   input_file = "short.csv",
#   output_file = "dailyWeatherScenario.csv",
#   delta_file = "MonthlyDeltaShifts.csv",
#   drought_factor = 0.75
# )

# Run with default parameters
cat("=== DROUGHT SIMULATION WITH DELTA SHIFTS FUNCTION LOADED ===\n")
cat("To use: result <- drought_simulation_with_shifts()\n")
cat("Or with custom parameters:\n")
cat("result <- drought_simulation_with_shifts('short.csv', 'dailyWeatherScenario.csv', 'MonthlyDeltaShifts.csv', 0.75)\n")
