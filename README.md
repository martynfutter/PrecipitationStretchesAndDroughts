# Climate Scenario Generation Tools

R scripts for generating future climate scenarios by modifying precipitation and temperature data through monthly delta shifts combined with either drought simulation or precipitation stretching.

---

## Repository Contents

### R Scripts

#### `SimulateDailyDrought.r`
Combines monthly delta shifts (climate change projections) with drought simulation in a two-stage transformation process.

**Description:**  
This script performs a two-stage transformation:
1. **Stage 1 - Delta Shifts**: Applies monthly precipitation percentage changes and temperature offsets to simulate climate change projections
2. **Stage 2 - Drought Simulation**: Reduces spring/summer (March-August) precipitation and redistributes it proportionally to fall/winter (September-February) days with precipitation

This allows modeling of both long-term climate trends (via delta shifts) and drought scenarios simultaneously.

**Parameters:**
- `input_file`: Path to input CSV file (default: `"short.csv"`)
- `output_file`: Path to output CSV file (default: `"dailyWeatherScenario.csv"`)
- `delta_file`: Path to monthly delta shifts CSV (default: `"MonthlyDeltaShifts.csv"`)
- `drought_factor`: Proportion of spring/summer precipitation to retain (default: `0.75`, meaning 25% reduction)

**Input File Formats:**

*Main input file (e.g., short.csv):*
- `date`: Date in YYYY-MM-DD format
- `precipitaition` (or `precipitation`): Precipitation values (handles typos)
- `air_temperature`: Temperature values in °C

*Delta shifts file (MonthlyDeltaShifts.csv):*
- `Month`: Integer 1-12 representing calendar months
- `PPctChange`: Precipitation percent change (e.g., 10 for +10%, -15 for -15%)
- `Toffset`: Temperature offset in °C (e.g., 2.5 for +2.5°C increase)

**Usage:**
```r
# Source the script
source("SimulateDailyDrought.r")

# Basic usage with defaults
result <- drought_simulation_with_shifts()

# Custom parameters
result <- drought_simulation_with_shifts(
  input_file = "short.csv",
  output_file = "dailyWeatherScenario.csv",
  delta_file = "MonthlyDeltaShifts.csv",
  drought_factor = 0.75
)
```

**Output Files:**
- **CSV file** (`dailyWeatherScenario.csv`) with columns:
  - `Date`: Date of observation
  - `OriginalPrecipitation`: Original precipitation values
  - `DeltaShiftPrecipitation`: Delta-shifted precipitation (after Stage 1)
  - `OriginalTemperature`: Original temperature values
  - `DeltaShiftTemperature`: Delta-shifted temperature
  - `ScenarioPrecipitation`: Final drought-adjusted precipitation (after Stage 2)

- **JSON metadata file** (`dailyWeatherScenario.json`) containing:
  - Scenario information (type, name, date created, drought reduction factor)
  - Input/output file paths
  - Monthly delta shifts applied
  - Summary statistics (date range, years processed)
  - Delta shift results (precipitation and temperature changes)
  - Drought simulation results (seasonal breakdown, mass balance verification)
  - Drought scaling factors by year

**Methodology:**
- **Seasons**: Spring/summer (March-August), Fall/winter (September-February)
- **Season Year**: For Jan-Feb, assigned to previous calendar year for continuity
- **Delta shifts**: Applied monthly; precipitation multiplier only on days with precipitation > 0; temperature offset on all days
- **Drought simulation**: Reduces spring/summer precipitation by `(1 - drought_factor)` and redistributes proportionally to fall/winter days with precipitation
- **Mass balance**: Preserved within each season year to ensure `sum(ScenarioPrecipitation) = sum(DeltaShiftPrecipitation)`

---

#### `StretchDailyPrecipitation.r`
Applies monthly delta shifts and then stretches extreme precipitation events using an optimized sigmoid function while maintaining mass balance.

**Description:**  
This script performs a two-stage transformation:
1. **Stage 1 - Delta Shifts**: Applies monthly precipitation percentage changes and temperature offsets
2. **Stage 2 - Precipitation Stretching**: Stretches precipitation above a threshold percentile using a sigmoid-based function with four optimized parameters (a, b, c, d) to maintain mass balance

The stretching emphasizes extreme precipitation events while preserving the total precipitation sum.

**Parameters:**
- `input_file`: Path to input CSV file with date, precipitation, and temperature columns
- `offset_file`: Path to monthly offsets CSV (default: `"MonthlyDeltaShifts.csv"`)
- `output_file`: Path to output CSV file (default: `"dailyWeatherScenario.csv"`)
- `threshold`: Threshold percentile value (0-100) above which to stretch precipitation
- `stretch_factor`: Maximum stretch percentage (e.g., 50 for 50% increase at the extreme)
- `scenario_name`: Name of the weather scenario (default: `"Default Scenario"`)
- `date_format`: Date parsing format (default: `"%Y-%m-%d"`)
- `tolerance`: Convergence tolerance for mass balance (default: `0.01` = 1%)
- `max_iter`: Maximum optimization iterations (default: `1000`)

**Input File Formats:**

*Main input file:*
- `date`: Date column (case-insensitive, handles variants like "datetime")
- `precipitation`: Precipitation values (handles typos like "precipitaition")
- `air_temperature`: Temperature values (handles variants like "temp", "temperature")

*Offset file (same as MonthlyDeltaShifts.csv):*
- `Month`: Integer 1-12
- `PPctChange`: Precipitation percent change
- `Toffset`: Temperature offset in °C

**Usage:**
```r
# Source the script
source("StretchDailyPrecipitation.r")

# Example usage
result <- stretch_precipitation_with_offsets(
  input_file = "short.csv",
  offset_file = "MonthlyDeltaShifts.csv",
  output_file = "dailyWeatherScenario.csv",
  threshold = 95,          # 95th percentile threshold
  stretch_factor = 50,     # 50% stretch for extreme events
  scenario_name = "RCP 8.5 - 2050",
  tolerance = 0.01         # 1% convergence tolerance
)
```

**Output Files:**
- **CSV file** (`dailyWeatherScenario.csv`) with columns:
  - `Date`: Date of observation
  - `OriginalPrecipitation`: Original precipitation values
  - `DeltaShiftPrecipitation`: Delta-shifted precipitation (after Stage 1)
  - `OriginalTemperature`: Original temperature values
  - `DeltaShiftTemperature`: Delta-shifted temperature
  - `ScenarioPrecipitation`: Final stretched precipitation (after Stage 2)

- **JSON metadata file** (`dailyWeatherScenario.json`) containing:
  - Scenario information (name, date created, stretch value)
  - Input/output file paths
  - Monthly offsets applied
  - User parameters (threshold, stretch factor, tolerance)
  - Optimized parameters (a, b, c, d)
  - Precipitation results (original → shifted → stretched totals, convergence error)
  - Temperature results (original and shifted means)
  - Data summary (total days processed, date range)

**Methodology:**
- **Delta shifts**: Applied first to modify baseline climate
- **Cumulative distribution**: Calculated for precipitation values (z-values 0-100)
- **Sigmoid stretch function**: Smooth transition using optimized parameters
- **Mass balance**: Iterative optimization ensures `sum(ScenarioPrecipitation) = sum(DeltaShiftPrecipitation)` within tolerance
- **Optimization**: Nelder-Mead method adjusts parameters a, b, c, d to achieve mass balance

---

### Input Data Files

#### `short.csv`
Example climate data file containing daily precipitation and temperature observations.

**Format:**
- `date`: Date in YYYY-MM-DD format
- `precipitaition`: Daily precipitation values (note: spelling variation in column name)
- `air_temperature`: Daily air temperature values in °C

**Data Range:** Contains 10,958 rows of daily observations spanning 30 years (1991-2020)

**Usage:** This file serves as the default input for both scripts when run with default parameters.

---

#### `MonthlyDeltaShifts.csv`
Example monthly climate change delta values for precipitation and temperature adjustments.

**Format:**
- `Month`: Integer 1-12 (January through December)
- `PPctChange`: Precipitation percent change for each month (can be positive or negative)
- `Toffset`: Temperature offset in °C for each month

**Data:** Contains 12 rows, one for each calendar month

**Usage:** This file is used by both scripts to apply monthly climate change projections. The precipitation change is applied as a multiplier only to days with precipitation > 0, while the temperature offset is applied to all days.

---

### Example Output Files

The `exampleFiles/` directory contains example outputs from both scripts:

#### `exampleFiles/drought/`
- `dailyWeatherScenario.csv`: Example output from drought simulation
- `dailyWeatherScenario.json`: Example metadata from drought simulation

#### `exampleFiles/stretch/`
- `dailyWeatherScenario.csv`: Example output from precipitation stretching
- `dailyWeatherScenario.json`: Example metadata from precipitation stretching

---

## Requirements

**R Packages:**
- `lubridate`: For flexible date parsing (automatically installed if missing)
- `jsonlite`: For JSON metadata output (automatically installed if missing)

**Base R:** The scripts use base R functions for optimization (`optim`), data manipulation, and CSV I/O.

---

## Workflow Comparison

### `SimulateDailyDrought.r` Workflow:
```
Original Data → Delta Shifts → Drought Simulation → Output
```
- **Focus**: Seasonal precipitation redistribution with climate change
- **Best for**: Modeling drought impacts under future climate scenarios
- **Key feature**: Reduces spring/summer precipitation and redistributes to fall/winter

### `StretchDailyPrecipitation.r` Workflow:
```
Original Data → Delta Shifts → Precipitation Stretching → Output
```
- **Focus**: Extreme event emphasis with climate change
- **Best for**: Modeling intensified precipitation extremes under future climate scenarios
- **Key feature**: Amplifies high-percentile precipitation events while maintaining total precipitation

---

## Key Concepts

### Seasonal Definitions (SimulateDailyDrought.r)
- **Spring/Summer**: March through August (months 3-8)
- **Fall/Winter**: September through February (months 9-12, 1-2)
- **Season Year**: For Jan-Feb, assigned to previous calendar year for continuity

### Drought Simulation Algorithm
1. Calculate seasonal precipitation totals by season year
2. Determine amount to shift: `p2shift = springSummer_total × (1 - drought_factor)`
3. Reduce all spring/summer precipitation by `drought_factor`
4. Distribute `p2shift` to fall/winter days with precipitation proportionally

### Precipitation Stretching Algorithm
1. Apply delta shifts to baseline precipitation
2. Calculate cumulative distribution (z-values) for precipitation
3. Apply sigmoid stretch function to precipitation above threshold
4. Optimize parameters (a, b, c, d) to maintain mass balance
5. Ensure `sum(ScenarioPrecipitation) = sum(DeltaShiftPrecipitation)` within tolerance

### Mass Balance
Both scripts preserve precipitation mass balance:
- **SimulateDailyDrought.r**: `sum(ScenarioPrecipitation) = sum(DeltaShiftPrecipitation)`
- **StretchDailyPrecipitation.r**: `sum(ScenarioPrecipitation) = sum(DeltaShiftPrecipitation)`

---

## Example Usage

```r
# 1. Drought simulation with climate change
source("SimulateDailyDrought.r")
result1 <- drought_simulation_with_shifts()

# 2. Extreme precipitation intensification with climate change
source("StretchDailyPrecipitation.r")
result2 <- stretch_precipitation_with_offsets(
  input_file = "short.csv",
  threshold = 95,
  stretch_factor = 50,
  scenario_name = "RCP 8.5 - 2050"
)

# 3. Severe drought scenario
source("SimulateDailyDrought.r")
result3 <- drought_simulation_with_shifts(
  input_file = "short.csv",
  output_file = "severe_drought_scenario.csv",
  delta_file = "MonthlyDeltaShifts.csv",
  drought_factor = 0.5  # 50% spring/summer reduction
)

# 4. Moderate extreme event scenario
source("StretchDailyPrecipitation.r")
result4 <- stretch_precipitation_with_offsets(
  input_file = "short.csv",
  output_file = "moderate_extreme_scenario.csv",
  threshold = 90,        # 90th percentile
  stretch_factor = 25,   # 25% maximum stretch
  scenario_name = "RCP 4.5 - 2050"
)
```

---

## Output File Structure

Both scripts produce consistent output formats:

**CSV Output Columns:**
1. `Date`: Date of observation
2. `OriginalPrecipitation`: Original precipitation values from input file
3. `DeltaShiftPrecipitation`: Precipitation after applying monthly delta shifts
4. `OriginalTemperature`: Original temperature values from input file
5. `DeltaShiftTemperature`: Temperature after applying monthly offsets
6. `ScenarioPrecipitation`: Final scenario precipitation (drought-adjusted OR stretched)

**JSON Metadata:**
- Comprehensive information about the scenario generation process
- All parameters used
- Statistical summaries of transformations
- Quality assurance metrics (e.g., mass balance verification)

---

## License

See LICENSE file for licensing information (GNU Lesser General Public License v2.1).

---

## Notes

- Both scripts are case-insensitive when reading column names
- Date parsing is flexible and handles multiple common date formats
- All precipitation transformations preserve mass balance
- Temperature transformations apply uniform monthly offsets
- Scripts automatically install required packages if missing