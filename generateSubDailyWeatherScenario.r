#' Generate Subdaily Weather Scenario from Daily Shifts
#'
#' This function takes a subdaily time series and applies daily shift factors
#' from a daily weather scenario file to generate subdaily scenario data.
#'
#' @param subdaily_file Path to input subdaily CSV file (default: "short_subdaily.csv")
#' @param daily_shifts_file Path to daily shifts CSV file (default: "dailyWeatherScenario.csv")
#' @param output_csv Path to output subdaily CSV file (default: "subDailyWeatherScenario.csv")
#' @param output_json Path to output JSON metadata file (default: "subDailyWeatherScenario.json")
#' @param daily_json_file Path to daily JSON metadata file (default: "dailyWeatherScenario.json")
#' @return Data frame with subdaily scenario data

generate_subdaily_weather_scenario <- function(subdaily_file = "short_subdaily.csv",
                                              daily_shifts_file = "dailyWeatherScenario.csv",
                                              output_csv = "subDailyWeatherScenario.csv",
                                              output_json = "subDailyWeatherScenario.json",
                                              daily_json_file = "dailyWeatherScenario.json") {
  
  # Load required libraries
  if (!require(lubridate)) {
    install.packages("lubridate")
    library(lubridate)
  }
  if (!require(jsonlite)) {
    install.packages("jsonlite")
    library(jsonlite)
  }
  
  cat("=== GENERATING SUBDAILY WEATHER SCENARIO ===\n")
  
  # ===================================================================
  # STEP 1: Read input files
  # ===================================================================
  
  # Read subdaily data
  cat("\nReading subdaily file:", subdaily_file, "\n")
  if (!file.exists(subdaily_file)) {
    stop(paste("Subdaily file not found:", subdaily_file))
  }
  subdaily_data <- read.csv(subdaily_file, stringsAsFactors = FALSE)
  
  # Find columns (case insensitive)
  datetime_col <- names(subdaily_data)[grep("^datetime$", names(subdaily_data), ignore.case = TRUE)]
  precip_col <- names(subdaily_data)[grep("^precip", names(subdaily_data), ignore.case = TRUE)]
  temp_col <- names(subdaily_data)[grep("temperature|temp", names(subdaily_data), ignore.case = TRUE)]
  
  if (length(datetime_col) == 0) {
    stop("Could not find 'DateTime' column in the subdaily file")
  }
  if (length(precip_col) == 0) {
    stop("Could not find 'Precipitation' column in the subdaily file")
  }
  if (length(temp_col) == 0) {
    stop("Could not find 'Temperature' column in the subdaily file")
  }
  
  # Use first matching column
  datetime_col <- datetime_col[1]
  precip_col <- precip_col[1]
  temp_col <- temp_col[1]
  
  cat("Using subdaily columns:", datetime_col, ",", precip_col, ",", temp_col, "\n")
  
  # Read daily shifts data
  cat("Reading daily shifts file:", daily_shifts_file, "\n")
  if (!file.exists(daily_shifts_file)) {
    stop(paste("Daily shifts file not found:", daily_shifts_file))
  }
  daily_shifts <- read.csv(daily_shifts_file, stringsAsFactors = FALSE)
  
  # Verify daily shifts columns (case insensitive)
  daily_names <- tolower(names(daily_shifts))
  if (!all(c("date", "originalprecipitation", "deltashiftprecipitation", 
             "originaltemperature", "deltashifttemperature", "scenarioprecipitation") %in% daily_names)) {
    stop("Daily shifts file must contain: Date, OriginalPrecipitation, DeltaShiftPrecipitation, OriginalTemperature, DeltaShiftTemperature, ScenarioPrecipitation")
  }
  
  # Standardize column names
  names(daily_shifts) <- tolower(names(daily_shifts))
  
  # ===================================================================
  # STEP 2: Parse dates and create date lookup
  # ===================================================================
  
  # Parse subdaily datetime
  subdaily_data$DateTime <- as.POSIXct(subdaily_data[[datetime_col]], 
                                       format = "%Y-%m-%d %H:%M:%S", 
                                       tz = "UTC")
  if (all(is.na(subdaily_data$DateTime))) {
    # Try alternative format
    subdaily_data$DateTime <- as.POSIXct(subdaily_data[[datetime_col]], 
                                         format = "%Y-%m-%d %H:%M", 
                                         tz = "UTC")
  }
  if (all(is.na(subdaily_data$DateTime))) {
    stop("Could not parse DateTime column. Expected format: YYYY-MM-DD HH:MM:SS or YYYY-MM-DD HH:MM")
  }
  
  # Extract date component (YYYY-MM-DD)
  subdaily_data$Date <- as.Date(subdaily_data$DateTime)
  
  # Parse daily shifts date
  daily_shifts$date <- as.Date(daily_shifts$date)
  
  cat("Subdaily data: ", nrow(subdaily_data), "records from", 
      as.character(min(subdaily_data$Date)), "to", as.character(max(subdaily_data$Date)), "\n")
  cat("Daily shifts data:", nrow(daily_shifts), "records from", 
      as.character(min(daily_shifts$date)), "to", as.character(max(daily_shifts$date)), "\n")
  
  # ===================================================================
  # STEP 3: Create subdaily scenario by merging with daily shifts
  # ===================================================================
  
  cat("\nApplying daily shifts to subdaily data...\n")
  
  # Merge subdaily data with daily shifts based on date
  merged_data <- merge(subdaily_data, daily_shifts, 
                      by.x = "Date", by.y = "date", 
                      all.x = TRUE)
  
  # Check for unmatched dates
  unmatched <- sum(is.na(merged_data$originalprecipitation))
  if (unmatched > 0) {
    warning(paste(unmatched, "subdaily records could not be matched to daily shifts"))
  }
  
  # Sort by DateTime
  merged_data <- merged_data[order(merged_data$DateTime), ]
  
  # ===================================================================
  # STEP 4: Calculate subdaily scenario values
  # ===================================================================
  
  # Extract original subdaily values
  merged_data$OriginalPrecipitation <- as.numeric(merged_data[[precip_col]])
  merged_data$OriginalTemperature <- as.numeric(merged_data[[temp_col]])
  
  # Initialize scenario columns
  merged_data$DeltaShiftPrecipitation <- 0
  merged_data$ScenarioPrecipitation <- 0
  merged_data$DeltaShiftTemperature <- merged_data$OriginalTemperature
  
  # Calculate precipitation shifts (only when OriginalPrecipitation > 0)
  precip_mask <- merged_data$OriginalPrecipitation > 0 & 
                 !is.na(merged_data$OriginalPrecipitation) &
                 !is.na(merged_data$originalprecipitation) &
                 merged_data$originalprecipitation > 0
  
  if (sum(precip_mask, na.rm = TRUE) > 0) {
    # Calculate DeltaShiftPrecipitation
    delta_ratio <- merged_data$deltashiftprecipitation[precip_mask] / 
                   merged_data$originalprecipitation[precip_mask]
    merged_data$DeltaShiftPrecipitation[precip_mask] <- 
      merged_data$OriginalPrecipitation[precip_mask] * delta_ratio
    
    # Calculate ScenarioPrecipitation
    scenario_ratio <- merged_data$scenarioprecipitation[precip_mask] / 
                      merged_data$originalprecipitation[precip_mask]
    merged_data$ScenarioPrecipitation[precip_mask] <- 
      merged_data$OriginalPrecipitation[precip_mask] * scenario_ratio
  }
  
  # Calculate temperature shifts (for all records)
  temp_mask <- !is.na(merged_data$OriginalTemperature) &
               !is.na(merged_data$originaltemperature) &
               !is.na(merged_data$deltashifttemperature)
  
  if (sum(temp_mask, na.rm = TRUE) > 0) {
    temp_adjustment <- merged_data$deltashifttemperature[temp_mask] - 
                      merged_data$originaltemperature[temp_mask]
    merged_data$DeltaShiftTemperature[temp_mask] <- 
      merged_data$OriginalTemperature[temp_mask] + temp_adjustment
  }
  
  # ===================================================================
  # STEP 5: Create output dataframe
  # ===================================================================
  
  output_data <- data.frame(
    DateTime = merged_data$DateTime,
    OriginalPrecipitation = merged_data$OriginalPrecipitation,
    DeltaShiftPrecipitation = merged_data$DeltaShiftPrecipitation,
    OriginalTemperature = merged_data$OriginalTemperature,
    DeltaShiftTemperature = merged_data$DeltaShiftTemperature,
    ScenarioPrecipitation = merged_data$ScenarioPrecipitation
  )
  
  # Remove rows with NA DateTime
  output_data <- output_data[!is.na(output_data$DateTime), ]
  
  # Write CSV output
  write.csv(output_data, output_csv, row.names = FALSE)
  cat("\nSubdaily scenario CSV saved to:", output_csv, "\n")
  
  # ===================================================================
  # STEP 6: Calculate summary statistics
  # ===================================================================
  
  total_original_precip <- sum(output_data$OriginalPrecipitation, na.rm = TRUE)
  total_delta_precip <- sum(output_data$DeltaShiftPrecipitation, na.rm = TRUE)
  total_scenario_precip <- sum(output_data$ScenarioPrecipitation, na.rm = TRUE)
  
  mean_original_temp <- mean(output_data$OriginalTemperature, na.rm = TRUE)
  mean_delta_temp <- mean(output_data$DeltaShiftTemperature, na.rm = TRUE)
  
  precip_records_with_data <- sum(output_data$OriginalPrecipitation > 0, na.rm = TRUE)
  
  cat("\n=== SUMMARY STATISTICS ===\n")
  cat("Total subdaily records:", nrow(output_data), "\n")
  cat("Date range:", as.character(min(output_data$DateTime)), "to", 
      as.character(max(output_data$DateTime)), "\n")
  cat("\nPrecipitation:\n")
  cat("  Original total:", round(total_original_precip, 4), "\n")
  cat("  DeltaShift total:", round(total_delta_precip, 4), "\n")
  cat("  Scenario total:", round(total_scenario_precip, 4), "\n")
  cat("  Records with precipitation:", precip_records_with_data, "\n")
  cat("\nTemperature:\n")
  cat("  Original mean:", round(mean_original_temp, 2), "°C\n")
  cat("  DeltaShift mean:", round(mean_delta_temp, 2), "°C\n")
  cat("  Mean change:", round(mean_delta_temp - mean_original_temp, 2), "°C\n")
  
  # ===================================================================
  # STEP 7: Create JSON metadata
  # ===================================================================
  
  cat("\nCreating JSON metadata...\n")
  
  # Read daily JSON metadata if it exists
  daily_metadata <- list()
  if (file.exists(daily_json_file)) {
    daily_metadata <- fromJSON(daily_json_file)
    cat("Loaded metadata from:", daily_json_file, "\n")
  } else {
    warning(paste("Daily JSON file not found:", daily_json_file))
  }
  
  # Create subdaily metadata (including all info from daily metadata)
  subdaily_metadata <- daily_metadata
  
  # Add subdaily-specific information
  subdaily_metadata$subdaily_generation_info <- list(
    generated_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    subdaily_input_file = subdaily_file,
    daily_shifts_source = daily_shifts_file
  )
  
  subdaily_metadata$subdaily_output_files <- list(
    csv_file = output_csv,
    json_file = output_json
  )
  
  subdaily_metadata$subdaily_summary <- list(
    total_records = nrow(output_data),
    datetime_range_start = format(min(output_data$DateTime), "%Y-%m-%d %H:%M:%S"),
    datetime_range_end = format(max(output_data$DateTime), "%Y-%m-%d %H:%M:%S"),
    records_with_precipitation = precip_records_with_data,
    original_precipitation_total = round(total_original_precip, 4),
    deltashift_precipitation_total = round(total_delta_precip, 4),
    scenario_precipitation_total = round(total_scenario_precip, 4),
    original_temperature_mean = round(mean_original_temp, 2),
    deltashift_temperature_mean = round(mean_delta_temp, 2),
    temperature_mean_change = round(mean_delta_temp - mean_original_temp, 2)
  )
  
  # Write JSON with pretty formatting
  write_json(subdaily_metadata, output_json, pretty = TRUE, auto_unbox = TRUE)
  cat("Subdaily metadata JSON saved to:", output_json, "\n")
  
  cat("\n=== SUBDAILY WEATHER SCENARIO GENERATION COMPLETE ===\n")
  
  # Return the output data
  invisible(output_data)
}

# Example usage:
# result <- generate_subdaily_weather_scenario()
#
# Or with custom parameters:
# result <- generate_subdaily_weather_scenario(
#   subdaily_file = "short_subdaily.csv",
#   daily_shifts_file = "dailyWeatherScenario.csv",
#   output_csv = "subDailyWeatherScenario.csv",
#   output_json = "subDailyWeatherScenario.json",
#   daily_json_file = "dailyWeatherScenario.json"
# )

cat("=== SUBDAILY WEATHER SCENARIO FUNCTION LOADED ===\n")
cat("To use: result <- generate_subdaily_weather_scenario()\n")
cat("Or with custom files:\n")
cat("result <- generate_subdaily_weather_scenario('short_subdaily.csv', 'dailyWeatherScenario.csv')\n")