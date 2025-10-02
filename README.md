# Precipitation Data Processing Tools

R scripts for modifying precipitation and temperature data through monthly delta shifts, precipitation stretching, and drought simulation.

## Repository Contents

### R Scripts

#### `drought_sim_delta.r`
Combines monthly delta shifts (climate change projections) with drought simulation in a two-stage transformation process.

**Description:**  
This script performs a two-stage transformation:
1. **Stage 1 - Delta Shifts**: Applies monthly precipitation percentage changes and temperature offsets to simulate climate change projections
2. **Stage 2 - Drought Simulation**: Reduces spring/summer (March-August) precipitation and redistributes it proportionally to fall/winter (September-February) days with precipitation

This allows modeling of both long-term climate trends (via delta shifts) and drought scenarios simultaneously.

**Parameters:**
- `input_file`: Path to input CSV file (default: `"short.csv"`)
- `output_file`: Path to output CSV file (default: `"drought_delta_shifted.csv"`)
- `delta_file`: Path to monthly delta shifts CSV (default: `"MonthlyDeltaShifts.csv"`)
- `drought_factor`: Proportion of spring/summer precipitation to retain (default: `0.75`)

**Input File Formats:**

*Main input file (e.g., short.csv):*
- `date`: Date in YYYY-MM-DD format
- `precipitaition` (or `precipitation`): Precipitation values
- `air_temperature`: Temperature values in °C

*Delta shifts file (e.g., MonthlyDeltaShifts.csv):*
- `Month`: Integer 1-12 representing calendar months
- `PPctChange`: Precipitation percent change (e.g., 10 for +10%, -15 for -15%)
- `Toffest`: Temperature offset in °C (e.g., 2.5 for +2.5°C increase)

**Usage:**
```r
# Source the script
source("drought_sim_delta.r")

# Basic usage with defaults
result <- drought_simulation_with_shifts()

# Custom parameters
result <- drought_simulation_with_shifts(
  input_file = "short.csv",
  output_file = "my_output.csv",
  delta_file = "MonthlyDeltaShifts.csv",
  drought_factor = 0.75
)
```

**Output:**  
CSV file with columns:
- `date`: Date of observation
- `precipitation`: Original precipitation values
- `air_temperature`: Original temperature values
- `precipitation_ds`: Delta-shifted precipitation (after Stage 1)
- `drought_precipitation_ds`: Final drought-adjusted delta-shifted precipitation (after Stage 2)
- `air_temperature_ds`: Delta-shifted temperature

**Summary Output:**  
The script prints comprehensive statistics including:
- Delta shift results (precipitation and temperature changes)
- Seasonal breakdown of days and precipitation days
- Mass balance verification for both stages
- Drought scaling factor statistics by season

**Methodology:**
- **Seasons**: Spring/summer (March-August), Fall/winter (September-February)
- **Delta shifts**: Applied monthly; precipitation multiplier only on days with precipitation > 0; temperature offset on all days
- **Drought simulation**: Reduces spring/summer precipitation by `(1 - drought_factor)` and redistributes proportionally to fall/winter days with precipitation
- **Mass balance**: Preserved within each season year

---

#### `precip_stretch_offsets.r`
Applies monthly delta shifts and then stretches extreme precipitation events using an optimized sigmoid function while maintaining mass balance.

**Description:**  
This script performs a two-stage precipitation transformation:
1. **Stage 1 - Delta Shifts**: Applies monthly precipitation percentage changes and temperature offsets
2. **Stage 2 - Precipitation Stretching**: Stretches precipitation above a threshold percentile using a sigmoid-based function with four optimized parameters (a, b, c, d) to maintain mass balance

The stretching emphasizes extreme precipitation events while preserving the total precipitation sum.

**Parameters:**
- `input_file`: Path to input CSV file with date, precipitation, and temperature columns
- `offset_file`: Path to monthly offsets CSV (default: `"MonthlyDeltaShifts.csv"`)
- `output_file`: Path to output CSV file (default: `"stretched_precipitation.csv"`)
- `threshold`: Threshold percentile value (0-100) above which to stretch precipitation
- `stretch_factor`: Maximum stretch percentage (e.g., 50 for 50% increase at the extreme)
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
- `Toffest`: Temperature offset in °C

**Usage:**
```r
# Source the script
source("precip_stretch_offsets.r")

# Example usage
result <- stretch_precipitation_with_offsets(
  input_file = "short.csv",
  offset_file = "MonthlyDeltaShifts.csv",
  output_file = "stretched_output.csv",
  threshold = 95,        # 95th percentile threshold
  stretch_factor = 50,   # 50% stretch for extreme events
  tolerance = 0.01       # 1% convergence tolerance
)
```

**Output:**  
CSV file with columns:
- `date`: Date of observation
- `original_precipitation`: Original precipitation values
- `shifted_precipitation`: Delta-shifted precipitation (after Stage 1)
- `stretched_precipitation`: Final stretched precipitation (after Stage 2)
- `stretch_factor`: Stretch factor applied to each day
- `original_temperature`: Original temperature values
- `shifted_temperature`: Delta-shifted temperature

**Additional Output:**  
Metadata text file (`*_metadata.txt`) containing:
- Input/output file paths
- Monthly offsets applied
- User parameters (threshold, stretch factor)
- Optimized parameters (a, b, c, d)
- Precipitation transformation summary (original → shifted → stretched totals)
- Temperature transformation summary
- Convergence error and statistics

**Methodology:**
- **Delta shifts**: Applied first to modify baseline climate
- **Cumulative distribution**: Calculated for precipitation values (z-values 0-100)
- **Sigmoid stretch function**: Smooth transition using optimized parameters
- **Mass balance**: Iterative optimization ensures `sum(stretched) = sum(shifted)`
- **Optimization**: Nelder-Mead method adjusts parameters a, b, c, d to achieve mass balance within tolerance

---

### Example Data Files

#### `short.csv`
Example climate data file containing daily precipitation and temperature observations.

**Format:**
- `date`: Date in YYYY-MM-DD format
- `precipitaition`: Daily precipitation values (note: spelling variation in column name)
- `air_temperature`: Daily air temperature values in °C

**Data Range:** Contains 10,958 rows of daily observations spanning multiple years (1988-2019 based on document samples)

**Usage:** This file serves as the default input for both scripts when run with default parameters.

---

#### `MonthlyDeltaShifts.csv`
Example monthly climate change delta values for precipitation and temperature adjustments.

**Format:**
- `Month`: Integer 1-12 (January through December)
- `PPctChange`: Precipitation percent change for each month (can be positive or negative)
- `Toffest`: Temperature offset in °C for each month

**Data:** Contains 12 rows, one for each calendar month

**Usage:** This file is used by both scripts to apply monthly climate change projections. The precipitation change is applied as a multiplier only to days with precipitation > 0, while the temperature offset is applied to all days.

---

## Requirements

**R Packages:**
- `lubridate`: For flexible date parsing (will be automatically installed if missing)

**Base R:** The scripts use base R functions for optimization (`optim`), data manipulation, and CSV I/O.

---

## Workflow Comparison

### `drought_sim_delta.r` Workflow:
```
Original Data → Delta Shifts → Drought Simulation → Output
```
- Focus: Seasonal precipitation redistribution with climate change
- Best for: Modeling drought impacts under future climate scenarios

### `precip_stretch_offsets.r` Workflow:
```
Original Data → Delta Shifts → Precipitation Stretching → Output
```
- Focus: Extreme event emphasis with climate change
- Best for: Modeling intensified precipitation extremes under future climate scenarios

---

## Key Concepts

### Seasonal Definitions (drought_sim_delta.r)
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
5. Ensure `sum(stretched) = sum(shifted)` within tolerance

### Mass Balance
Both scripts preserve precipitation mass balance:
- **drought_sim_delta.r**: `sum(drought_precipitation_ds) = sum(precipitation_ds)`
- **precip_stretch_offsets.r**: `sum(stretched_precipitation) = sum(shifted_precipitation)`

---

## Example Workflows

```r
# 1. Drought simulation with climate change
source("drought_sim_delta.r")
result1 <- drought_simulation_with_shifts()

# 2. Extreme precipitation intensification with climate change
source("precip_stretch_offsets.r")
result2 <- stretch_precipitation_with_offsets(
  input_file = "short.csv",
  threshold = 95,
  stretch_factor = 50
)

# 3. Severe drought scenario for 2050
source("drought_sim_delta.r")
result3 <- drought_simulation_with_shifts(
  input_file = "short.csv",
  output_file = "severe_drought_2050.csv",
  delta_file = "MonthlyDeltaShifts.csv",
  drought_factor = 0.5  # 50% spring/summer reduction
)
```

---

## License

See LICENSE file for licensing information (GNU Lesser General Public License v2.1).
