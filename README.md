# Climate Scenario Generation Tools

R scripts for generating future climate scenarios by modifying precipitation and temperature data at daily and subdaily time scales through monthly delta shifts combined with either drought simulation or precipitation stretching.

---

## Table of Contents

- [Overview](#overview)
- [Repository Contents](#repository-contents)
- [Daily Scenario Generation](#daily-scenario-generation)
  - [SimulateDailyDrought.r](#simulatedailydroughtr)
  - [StretchDailyPrecipitation.r](#stretchdailyprecipitationr)
- [Subdaily Scenario Generation](#subdaily-scenario-generation)
  - [generateSubDailyWeatherScenario.r](#generatesubdailyweatherscenarior)
- [Input Data Files](#input-data-files)
- [Output File Structure](#output-file-structure)
- [Complete Workflow Examples](#complete-workflow-examples)
- [Requirements](#requirements)
- [License](#license)

---

## Overview

This repository provides tools for generating climate scenarios at both daily and subdaily time scales. The workflow consists of two stages:

1. **Daily Scenario Generation**: Apply monthly delta shifts and either drought simulation or extreme event stretching to daily weather data
2. **Subdaily Scenario Generation**: Apply the daily scenario transformations to subdaily (hourly or sub-hourly) weather data

All transformations preserve mass balance and provide comprehensive metadata tracking.

---

## Repository Contents

### R Scripts

- **`SimulateDailyDrought.r`**: Generates daily drought scenarios with climate change projections
- **`StretchDailyPrecipitation.r`**: Generates daily extreme precipitation scenarios with climate change projections
- **`generateSubDailyWeatherScenario.r`**: Applies daily scenario transformations to subdaily time series

### Data Files

- **`short.csv`**: Example daily weather data (30 years, 1991-2020)
- **`MonthlyDeltaShifts.csv`**: Example monthly climate change projections
- **`exampleFiles/`**: Directory containing example outputs

---

## Daily Scenario Generation

### SimulateDailyDrought.r

Combines monthly delta shifts (climate change projections) with drought simulation in a two-stage transformation process.

#### Description

This script performs a two-stage transformation:
1. **Stage 1 - Delta Shifts**: Applies monthly precipitation percentage changes and temperature offsets to simulate climate change projections
2. **Stage 2 - Drought Simulation**: Reduces spring/summer (March-August) precipitation and redistributes it proportionally to fall/winter (September-February) days with precipitation

#### Parameters

```r
drought_simulation_with_shifts(
  input_file = "short.csv",              # Input daily weather data
  output_file = "dailyWeatherScenario.csv",  # Output CSV file
  delta_file = "MonthlyDeltaShifts.csv",     # Monthly delta shifts
  drought_factor = 0.75                   # Proportion to retain (0.75 = 25% reduction)
)
```

#### Input File Formats

**Main input file (e.g., short.csv):**
- `date`: Date in YYYY-MM-DD format
- `precipitation` (or `precipitaition`): Precipitation values (mm)
- `air_temperature` (or `temperature`): Temperature values (°C)

**Delta shifts file (MonthlyDeltaShifts.csv):**
- `Month`: Integer 1-12 representing calendar months
- `PPctChange`: Precipitation percent change (e.g., 10 for +10%, -15 for -15%)
- `Toffset`: Temperature offset in °C (e.g., 2.5 for +2.5°C increase)

#### Usage Example

```r
# Source the script
source("SimulateDailyDrought.r")

# Basic usage with defaults
result <- drought_simulation_with_shifts()

# Custom severe drought scenario
result <- drought_simulation_with_shifts(
  input_file = "short.csv",
  output_file = "severe_drought_scenario.csv",
  delta_file = "MonthlyDeltaShifts.csv",
  drought_factor = 0.5  # 50% spring/summer reduction
)
```

#### Methodology

- **Seasons**: Spring/summer (March-August), Fall/winter (September-February)
- **Season Year**: For Jan-Feb, assigned to previous calendar year for continuity
- **Delta shifts**: Applied monthly; precipitation multiplier only on days with precipitation > 0; temperature offset on all days
- **Drought simulation**: Reduces spring/summer precipitation by `(1 - drought_factor)` and redistributes proportionally to fall/winter days with precipitation
- **Mass balance**: Preserved within each season year to ensure `sum(ScenarioPrecipitation) = sum(DeltaShiftPrecipitation)`

---

### StretchDailyPrecipitation.r

Applies monthly delta shifts and then stretches extreme precipitation events using an optimized sigmoid function while maintaining mass balance.

#### Description

This script performs a two-stage transformation:
1. **Stage 1 - Delta Shifts**: Applies monthly precipitation percentage changes and temperature offsets
2. **Stage 2 - Precipitation Stretching**: Stretches precipitation above a threshold percentile using a sigmoid-based function with four optimized parameters (a, b, c, d) to maintain mass balance

#### Parameters

```r
stretch_precipitation_with_offsets(
  input_file = "short.csv",              # Input daily weather data
  offset_file = "MonthlyDeltaShifts.csv",    # Monthly delta shifts
  output_file = "dailyWeatherScenario.csv",  # Output CSV file
  threshold = 95,                        # Threshold percentile (0-100)
  stretch_factor = 50,                   # Maximum stretch percentage
  scenario_name = "Default Scenario",    # Scenario name for metadata
  date_format = "%Y-%m-%d",              # Date parsing format
  tolerance = 0.01,                      # Convergence tolerance (1%)
  max_iter = 1000                        # Maximum optimization iterations
)
```

#### Usage Example

```r
# Source the script
source("StretchDailyPrecipitation.r")

# Extreme precipitation intensification scenario
result <- stretch_precipitation_with_offsets(
  input_file = "short.csv",
  threshold = 95,          # 95th percentile threshold
  stretch_factor = 50,     # 50% stretch for extreme events
  scenario_name = "RCP 8.5 - 2050"
)

# Moderate extreme event scenario
result <- stretch_precipitation_with_offsets(
  input_file = "short.csv",
  output_file = "moderate_extreme_scenario.csv",
  threshold = 90,          # 90th percentile
  stretch_factor = 25,     # 25% maximum stretch
  scenario_name = "RCP 4.5 - 2050"
)
```

#### Methodology

- **Delta shifts**: Applied first to modify baseline climate
- **Cumulative distribution**: Calculated for precipitation values (z-values 0-100)
- **Sigmoid stretch function**: Smooth transition using optimized parameters
- **Mass balance**: Iterative optimization ensures `sum(ScenarioPrecipitation) = sum(DeltaShiftPrecipitation)` within tolerance
- **Optimization**: Nelder-Mead method adjusts parameters a, b, c, d to achieve mass balance

---

## Subdaily Scenario Generation

### generateSubDailyWeatherScenario.r

Takes a subdaily time series and applies daily scenario transformations to create subdaily climate scenarios.

#### Description

This script applies the transformations from a daily weather scenario to subdaily (hourly or sub-hourly) weather data. It:
1. Reads subdaily weather data with DateTime stamps
2. Reads daily weather scenario data (from SimulateDailyDrought.r or StretchDailyPrecipitation.r)
3. Matches subdaily records to daily scenarios by date
4. Applies proportional transformations to subdaily precipitation and temperature
5. Generates subdaily scenario output with comprehensive metadata

#### Parameters

```r
generate_subdaily_weather_scenario(
  subdaily_file = "short_subdaily.csv",          # Input subdaily data
  daily_shifts_file = "dailyWeatherScenario.csv",    # Daily scenario from previous step
  output_csv = "subDailyWeatherScenario.csv",    # Output subdaily CSV
  output_json = "subDailyWeatherScenario.json",  # Output metadata JSON
  daily_json_file = "dailyWeatherScenario.json"  # Daily scenario metadata
)
```

#### Input File Format

**Subdaily input file (e.g., short_subdaily.csv):**
- `DateTime`: Timestamp in `YYYY-MM-DD HH:MM:SS` or `YYYY-MM-DD HH:MM` format
- `Precipitation`: Subdaily precipitation values (mm)
- `Temperature`: Subdaily temperature values (°C)

**Daily scenario file (from previous step):**
- `Date`: Date in YYYY-MM-DD format
- `OriginalPrecipitation`: Original daily precipitation
- `DeltaShiftPrecipitation`: Delta-shifted daily precipitation
- `OriginalTemperature`: Original daily temperature
- `DeltaShiftTemperature`: Delta-shifted daily temperature
- `ScenarioPrecipitation`: Final scenario daily precipitation (drought-adjusted OR stretched)

#### Usage Example

```r
# Source the script
source("generateSubDailyWeatherScenario.r")

# Basic usage with defaults
result <- generate_subdaily_weather_scenario()

# Custom parameters
result <- generate_subdaily_weather_scenario(
  subdaily_file = "hourly_weather.csv",
  daily_shifts_file = "dailyWeatherScenario.csv",
  output_csv = "hourlyWeatherScenario.csv",
  output_json = "hourlyWeatherScenario.json",
  daily_json_file = "dailyWeatherScenario.json"
)
```

#### Methodology

The subdaily scenario generation applies the daily transformations proportionally:

**For Precipitation:**
- Extracts the date from each subdaily timestamp
- Matches to corresponding daily scenario
- For subdaily timesteps with precipitation > 0:
  - Calculates daily ratio: `daily_delta_ratio = DailyDeltaShift / DailyOriginal`
  - Applies to subdaily: `SubdailyDeltaShift = SubdailyOriginal × daily_delta_ratio`
  - Calculates scenario ratio: `daily_scenario_ratio = DailyScenario / DailyOriginal`
  - Applies to subdaily: `SubdailyScenario = SubdailyOriginal × daily_scenario_ratio`

**For Temperature:**
- Calculates daily temperature adjustment: `adjustment = DailyDeltaShift - DailyOriginal`
- Applies same adjustment to all subdaily timesteps on that date:
  - `SubdailyDeltaShift = SubdailyOriginal + adjustment`

This approach ensures that:
- Subdaily patterns are preserved (e.g., diurnal temperature cycles, precipitation timing)
- Daily totals match the daily scenario
- All transformations applied at the daily scale propagate to subdaily data

#### Output Columns

**CSV Output:**
- `DateTime`: Subdaily timestamp
- `OriginalPrecipitation`: Original subdaily precipitation
- `DeltaShiftPrecipitation`: Delta-shifted subdaily precipitation
- `OriginalTemperature`: Original subdaily temperature
- `DeltaShiftTemperature`: Delta-shifted subdaily temperature
- `ScenarioPrecipitation`: Final scenario subdaily precipitation

**JSON Metadata:**
- Inherits all metadata from the daily scenario (scenario type, parameters, delta shifts)
- Adds subdaily-specific information:
  - Total subdaily records processed
  - DateTime range
  - Precipitation and temperature summaries
  - Input/output file references

---

## Input Data Files

### short.csv

Example climate data file containing daily precipitation and temperature observations.

**Format:**
- `date`: Date in YYYY-MM-DD format
- `precipitaition`: Daily precipitation values (note: spelling variation in column name)
- `air_temperature`: Daily air temperature values in °C

**Data Range:** Contains 10,958 rows of daily observations spanning 30 years (1991-2020)

### MonthlyDeltaShifts.csv

Example monthly climate change delta values for precipitation and temperature adjustments.

**Format:**
- `Month`: Integer 1-12 (January through December)
- `PPctChange`: Precipitation percent change for each month
- `Toffset`: Temperature offset in °C for each month

**Example values:**
```
Month,PPctChange,Toffset
1,10,1
2,10,1
3,5,1
4,5,1
5,5,1
6,-10,1
7,-10,1
8,-10,1
9,0,1
10,0,1
11,10,1
12,10,1
```

---

## Output File Structure

### Daily Scenario Outputs

**CSV Output Columns:**
1. `Date`: Date of observation
2. `OriginalPrecipitation`: Original precipitation values from input file
3. `DeltaShiftPrecipitation`: Precipitation after applying monthly delta shifts
4. `OriginalTemperature`: Original temperature values from input file
5. `DeltaShiftTemperature`: Temperature after applying monthly offsets
6. `ScenarioPrecipitation`: Final scenario precipitation (drought-adjusted OR stretched)

**JSON Metadata:**
- Scenario information (type, name, date created, parameters)
- Input/output file paths
- Monthly delta shifts applied
- Summary statistics (date range, years processed, totals, means)
- Transformation results (mass balance verification, convergence metrics)
- Quality assurance information

### Subdaily Scenario Outputs

**CSV Output Columns:**
1. `DateTime`: Subdaily timestamp
2. `OriginalPrecipitation`: Original subdaily precipitation
3. `DeltaShiftPrecipitation`: Delta-shifted subdaily precipitation
4. `OriginalTemperature`: Original subdaily temperature
5. `DeltaShiftTemperature`: Delta-shifted subdaily temperature
6. `ScenarioPrecipitation`: Final scenario subdaily precipitation

**JSON Metadata:**
- All metadata from the daily scenario
- Subdaily-specific generation information
- Subdaily summary statistics
- DateTime range and record counts

---

## Complete Workflow Examples

### Example 1: Drought Scenario (Daily → Subdaily)

```r
# Step 1: Generate daily drought scenario
source("SimulateDailyDrought.r")
daily_result <- drought_simulation_with_shifts(
  input_file = "short.csv",
  output_file = "dailyWeatherScenario.csv",
  delta_file = "MonthlyDeltaShifts.csv",
  drought_factor = 0.75  # 25% spring/summer reduction
)

# Step 2: Apply to subdaily data
source("generateSubDailyWeatherScenario.r")
subdaily_result <- generate_subdaily_weather_scenario(
  subdaily_file = "short_subdaily.csv",
  daily_shifts_file = "dailyWeatherScenario.csv",
  output_csv = "subDailyWeatherScenario.csv",
  output_json = "subDailyWeatherScenario.json"
)
```

### Example 2: Extreme Precipitation Scenario (Daily → Subdaily)

```r
# Step 1: Generate daily extreme precipitation scenario
source("StretchDailyPrecipitation.r")
daily_result <- stretch_precipitation_with_offsets(
  input_file = "short.csv",
  output_file = "dailyWeatherScenario.csv",
  threshold = 95,
  stretch_factor = 50,
  scenario_name = "RCP 8.5 - 2050"
)

# Step 2: Apply to subdaily data
source("generateSubDailyWeatherScenario.r")
subdaily_result <- generate_subdaily_weather_scenario(
  subdaily_file = "hourly_weather.csv",
  daily_shifts_file = "dailyWeatherScenario.csv",
  output_csv = "hourlyWeatherScenario.csv"
)
```

### Example 3: Multiple Scenarios

```r
# Generate different daily scenarios
source("SimulateDailyDrought.r")
source("StretchDailyPrecipitation.r")

# Scenario 1: Moderate drought
drought_moderate <- drought_simulation_with_shifts(
  output_file = "moderate_drought.csv",
  drought_factor = 0.75
)

# Scenario 2: Severe drought
drought_severe <- drought_simulation_with_shifts(
  output_file = "severe_drought.csv",
  drought_factor = 0.5
)

# Scenario 3: Extreme precipitation
extreme_precip <- stretch_precipitation_with_offsets(
  output_file = "extreme_precip.csv",
  threshold = 95,
  stretch_factor = 50
)

# Apply each to subdaily data
source("generateSubDailyWeatherScenario.r")

subdaily_moderate <- generate_subdaily_weather_scenario(
  daily_shifts_file = "moderate_drought.csv",
  output_csv = "subdaily_moderate_drought.csv"
)

subdaily_severe <- generate_subdaily_weather_scenario(
  daily_shifts_file = "severe_drought.csv",
  output_csv = "subdaily_severe_drought.csv"
)

subdaily_extreme <- generate_subdaily_weather_scenario(
  daily_shifts_file = "extreme_precip.csv",
  output_csv = "subdaily_extreme_precip.csv"
)
```

---

## Requirements

**R Version:** R 3.5.0 or higher recommended

**R Packages:**
- `lubridate`: For flexible date and datetime parsing (automatically installed if missing)
- `jsonlite`: For JSON metadata output (automatically installed if missing)

**Base R:** The scripts use base R functions for optimization (`optim`), data manipulation, and CSV I/O.

**Installation:**
All required packages are automatically installed when running the scripts if they are not already present.

---

## Notes

### General Features

- **Case-insensitive column matching**: All scripts handle column name variations (e.g., "Precipitation", "precipitation", "precipitaition")
- **Flexible date parsing**: Multiple date/datetime formats are supported
- **Mass balance preservation**: All precipitation transformations preserve total precipitation sums
- **Comprehensive metadata**: JSON files track all parameters, transformations, and quality metrics
- **Automatic package installation**: Scripts install required packages if missing

### Data Requirements

- **Daily data**: Must contain date, precipitation, and temperature columns
- **Subdaily data**: Must contain datetime timestamp, precipitation, and temperature columns
- **Monthly delta shifts**: Must contain 12 rows (one per month) with precipitation percent change and temperature offset

### Temporal Resolution

- **Daily scenarios**: Work with any daily time series
- **Subdaily scenarios**: Work with any subdaily resolution (hourly, 15-minute, etc.)
- **Timestep matching**: Subdaily data is matched to daily scenarios by date component

### Quality Assurance

- All scripts include extensive error checking and informative error messages
- Mass balance verification is performed and reported in JSON metadata
- Convergence metrics are tracked for optimization-based methods
- Summary statistics are calculated and reported for validation

---

## License

See LICENSE file for licensing information (GNU Lesser General Public License v2.1).

---

## Citation

When using these tools in publications, please cite:

```
Climate Scenario Generation Tools
R scripts for generating daily and subdaily climate scenarios
GitHub: [repository URL]
```

---

## Support and Contact

For questions, issues, or contributions, please open an issue on the GitHub repository.