-- ============================================================
-- AtliQ Motors - EV Market Analysis
-- Database: MySQL 8.0+
-- Analysis period: FY2022 - FY2024
-- ============================================================

CREATE DATABASE IF NOT EXISTS atliq_motors_ev;
USE atliq_motors_ev;

DROP TABLE IF EXISTS electric_vehicle_sales_by_makers;
DROP TABLE IF EXISTS electric_vehicle_sales_by_state;
DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date (
    date DATE PRIMARY KEY,
    fiscal_year INT NOT NULL,
    quarter VARCHAR(2) NOT NULL
);

CREATE TABLE electric_vehicle_sales_by_makers (
    date DATE NOT NULL,
    vehicle_category VARCHAR(30) NOT NULL,
    maker VARCHAR(100) NOT NULL,
    electric_vehicles_sold INT NOT NULL,
    PRIMARY KEY (date, vehicle_category, maker),
    FOREIGN KEY (date) REFERENCES dim_date(date)
);

CREATE TABLE electric_vehicle_sales_by_state (
    date DATE NOT NULL,
    state VARCHAR(100) NOT NULL,
    vehicle_category VARCHAR(30) NOT NULL,
    electric_vehicles_sold INT NOT NULL,
    total_vehicles_sold INT NOT NULL,
    PRIMARY KEY (date, state, vehicle_category),
    FOREIGN KEY (date) REFERENCES dim_date(date)
);

-- ============================================================
-- CSV IMPORT
-- ============================================================
-- Recommended: MySQL Workbench > Table Data Import Wizard.
-- The commented LOAD DATA examples below assume the CSV files
-- are available under the repository's data/ directory.

-- LOAD DATA LOCAL INFILE 'data/dim_date.csv'
-- INTO TABLE dim_date
-- FIELDS TERMINATED BY ','
-- OPTIONALLY ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 ROWS
-- (@date, fiscal_year, quarter)
-- SET date = STR_TO_DATE(@date, '%d-%b-%y');

-- LOAD DATA LOCAL INFILE 'data/electric_vehicle_sales_by_makers.csv'
-- INTO TABLE electric_vehicle_sales_by_makers
-- FIELDS TERMINATED BY ','
-- OPTIONALLY ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 ROWS
-- (@date, vehicle_category, maker, electric_vehicles_sold)
-- SET date = STR_TO_DATE(@date, '%d-%b-%y');

-- LOAD DATA LOCAL INFILE 'data/electric_vehicle_sales_by_state.csv'
-- INTO TABLE electric_vehicle_sales_by_state
-- FIELDS TERMINATED BY ','
-- OPTIONALLY ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'
-- IGNORE 1 ROWS
-- (@date, state, vehicle_category, electric_vehicles_sold, total_vehicles_sold)
-- SET date = STR_TO_DATE(@date, '%d-%b-%y');

-- ============================================================
-- DATA VALIDATION
-- ============================================================

SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL
SELECT 'electric_vehicle_sales_by_makers', COUNT(*) FROM electric_vehicle_sales_by_makers
UNION ALL
SELECT 'electric_vehicle_sales_by_state', COUNT(*) FROM electric_vehicle_sales_by_state;

-- ============================================================
-- Q1. TOP 3 AND BOTTOM 3 2-WHEELER MAKERS
-- FY2023 and FY2024
-- ============================================================

WITH maker_sales AS (
    SELECT
        d.fiscal_year,
        m.maker,
        SUM(m.electric_vehicles_sold) AS ev_units
    FROM electric_vehicle_sales_by_makers m
    JOIN dim_date d ON m.date = d.date
    WHERE m.vehicle_category = '2-Wheelers'
      AND d.fiscal_year IN (2023, 2024)
    GROUP BY d.fiscal_year, m.maker
),
ranked AS (
    SELECT
        fiscal_year,
        maker,
        ev_units,
        ROW_NUMBER() OVER (
            PARTITION BY fiscal_year ORDER BY ev_units DESC, maker
        ) AS top_rank,
        ROW_NUMBER() OVER (
            PARTITION BY fiscal_year ORDER BY ev_units ASC, maker
        ) AS bottom_rank
    FROM maker_sales
)
SELECT
    fiscal_year,
    CASE
        WHEN top_rank <= 3 THEN 'Top 3'
        ELSE 'Bottom 3'
    END AS performance_group,
    maker,
    ev_units
FROM ranked
WHERE top_rank <= 3 OR bottom_rank <= 3
ORDER BY fiscal_year, performance_group, ev_units DESC;

-- ============================================================
-- Q2. TOP 5 STATES BY EV PENETRATION IN FY2024
-- Separately for 2-wheelers and 4-wheelers
-- ============================================================

WITH state_penetration AS (
    SELECT
        s.state,
        s.vehicle_category,
        SUM(s.electric_vehicles_sold) AS ev_units,
        SUM(s.total_vehicles_sold) AS total_units,
        100.0 * SUM(s.electric_vehicles_sold)
            / NULLIF(SUM(s.total_vehicles_sold), 0) AS penetration_rate
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d ON s.date = d.date
    WHERE d.fiscal_year = 2024
    GROUP BY s.state, s.vehicle_category
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY vehicle_category
            ORDER BY penetration_rate DESC, state
        ) AS penetration_rank
    FROM state_penetration
)
SELECT
    state,
    vehicle_category,
    ev_units,
    total_units,
    ROUND(penetration_rate, 2) AS penetration_rate_pct
FROM ranked
WHERE penetration_rank <= 5
ORDER BY vehicle_category, penetration_rank;

-- ============================================================
-- Q3. STATES WITH DECLINING EV PENETRATION
-- Combined 2W + 4W penetration, FY2022 vs FY2024
-- ============================================================

WITH state_year AS (
    SELECT
        s.state,
        d.fiscal_year,
        SUM(s.electric_vehicles_sold) AS ev_units,
        SUM(s.total_vehicles_sold) AS total_units,
        100.0 * SUM(s.electric_vehicles_sold)
            / NULLIF(SUM(s.total_vehicles_sold), 0) AS penetration_rate
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d ON s.date = d.date
    WHERE d.fiscal_year IN (2022, 2024)
    GROUP BY s.state, d.fiscal_year
),
state_compare AS (
    SELECT
        state,
        MAX(CASE WHEN fiscal_year = 2022 THEN penetration_rate END) AS penetration_2022,
        MAX(CASE WHEN fiscal_year = 2024 THEN penetration_rate END) AS penetration_2024
    FROM state_year
    GROUP BY state
)
SELECT
    state,
    ROUND(penetration_2022, 2) AS penetration_2022_pct,
    ROUND(penetration_2024, 2) AS penetration_2024_pct,
    ROUND(penetration_2024 - penetration_2022, 2) AS change_percentage_points
FROM state_compare
WHERE penetration_2024 < penetration_2022
ORDER BY change_percentage_points ASC;

-- ============================================================
-- Q4. QUARTERLY TRENDS FOR TOP 5 4-WHEELER MAKERS
-- Top 5 are defined by total 4W EV sales across FY2022-FY2024.
-- ============================================================

WITH maker_total AS (
    SELECT
        m.maker,
        SUM(m.electric_vehicles_sold) AS total_ev_units
    FROM electric_vehicle_sales_by_makers m
    JOIN dim_date d ON m.date = d.date
    WHERE m.vehicle_category = '4-Wheelers'
      AND d.fiscal_year BETWEEN 2022 AND 2024
    GROUP BY m.maker
),
top_5_makers AS (
    SELECT maker, total_ev_units
    FROM (
        SELECT
            maker,
            total_ev_units,
            ROW_NUMBER() OVER (
                ORDER BY total_ev_units DESC, maker
            ) AS maker_rank
        FROM maker_total
    ) x
    WHERE maker_rank <= 5
)
SELECT
    d.fiscal_year,
    d.quarter,
    m.maker,
    SUM(m.electric_vehicles_sold) AS quarterly_ev_units
FROM electric_vehicle_sales_by_makers m
JOIN dim_date d ON m.date = d.date
JOIN top_5_makers t ON m.maker = t.maker
WHERE m.vehicle_category = '4-Wheelers'
  AND d.fiscal_year BETWEEN 2022 AND 2024
GROUP BY d.fiscal_year, d.quarter, m.maker
ORDER BY d.fiscal_year, d.quarter, m.maker;

-- ============================================================
-- Q5. DELHI VS KARNATAKA - FY2024
-- ============================================================

SELECT
    s.state,
    s.vehicle_category,
    SUM(s.electric_vehicles_sold) AS ev_units,
    SUM(s.total_vehicles_sold) AS total_vehicle_units,
    ROUND(
        100.0 * SUM(s.electric_vehicles_sold)
        / NULLIF(SUM(s.total_vehicles_sold), 0),
        2
    ) AS penetration_rate_pct
FROM electric_vehicle_sales_by_state s
JOIN dim_date d ON s.date = d.date
WHERE d.fiscal_year = 2024
  AND s.state IN ('Delhi', 'Karnataka')
GROUP BY s.state, s.vehicle_category
ORDER BY s.state, s.vehicle_category;

-- ============================================================
-- Q6. CAGR FOR TOP 5 4-WHEELER MAKERS
-- Top 5 are defined by FY2024 sales.
-- CAGR is calculated only when FY2022 sales > 0.
-- ============================================================

WITH maker_year AS (
    SELECT
        m.maker,
        d.fiscal_year,
        SUM(m.electric_vehicles_sold) AS ev_units
    FROM electric_vehicle_sales_by_makers m
    JOIN dim_date d ON m.date = d.date
    WHERE m.vehicle_category = '4-Wheelers'
      AND d.fiscal_year IN (2022, 2024)
    GROUP BY m.maker, d.fiscal_year
),
maker_summary AS (
    SELECT
        maker,
        MAX(CASE WHEN fiscal_year = 2022 THEN ev_units END) AS units_2022,
        MAX(CASE WHEN fiscal_year = 2024 THEN ev_units END) AS units_2024
    FROM maker_year
    GROUP BY maker
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            ORDER BY COALESCE(units_2024, 0) DESC, maker
        ) AS maker_rank
    FROM maker_summary
)
SELECT
    maker,
    units_2022,
    units_2024,
    CASE
        WHEN units_2022 > 0 AND units_2024 > 0
        THEN ROUND(
            100.0 * (
                POWER(units_2024 / units_2022, 1.0 / 2) - 1
            ),
            2
        )
        ELSE NULL
    END AS cagr_pct,
    CASE
        WHEN units_2022 = 0 THEN 'CAGR not defined: FY2022 sales = 0'
        ELSE 'CAGR calculated'
    END AS cagr_note
FROM ranked
WHERE maker_rank <= 5
ORDER BY units_2024 DESC;

-- ============================================================
-- Q7. TOP 10 STATES BY CAGR IN TOTAL VEHICLES SOLD
-- FY2022 to FY2024
-- ============================================================

WITH state_year AS (
    SELECT
        s.state,
        d.fiscal_year,
        SUM(s.total_vehicles_sold) AS total_vehicle_units
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d ON s.date = d.date
    WHERE d.fiscal_year IN (2022, 2024)
    GROUP BY s.state, d.fiscal_year
),
state_summary AS (
    SELECT
        state,
        MAX(CASE WHEN fiscal_year = 2022 THEN total_vehicle_units END) AS total_2022,
        MAX(CASE WHEN fiscal_year = 2024 THEN total_vehicle_units END) AS total_2024
    FROM state_year
    GROUP BY state
)
SELECT
    state,
    total_2022,
    total_2024,
    ROUND(
        100.0 * (
            POWER(total_2024 / NULLIF(total_2022, 0), 1.0 / 2) - 1
        ),
        2
    ) AS cagr_pct
FROM state_summary
WHERE total_2022 > 0
ORDER BY cagr_pct DESC
LIMIT 10;

-- ============================================================
-- Q8. PEAK AND LOW SEASON MONTHS
-- EV sales aggregated by calendar month across FY2022-FY2024.
-- ============================================================

WITH monthly_sales AS (
    SELECT
        MONTH(s.date) AS month_number,
        MONTHNAME(s.date) AS month_name,
        SUM(s.electric_vehicles_sold) AS ev_units
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d ON s.date = d.date
    WHERE d.fiscal_year BETWEEN 2022 AND 2024
    GROUP BY MONTH(s.date), MONTHNAME(s.date)
)
SELECT
    month_number,
    month_name,
    ev_units,
    CASE
        WHEN ev_units = MAX(ev_units) OVER () THEN 'Peak'
        WHEN ev_units = MIN(ev_units) OVER () THEN 'Low'
        ELSE 'Normal'
    END AS season_type
FROM monthly_sales
ORDER BY month_number;

-- ============================================================
-- Q9. 2030 EV SALES SCENARIO
-- Top 10 FY2024 states by combined EV penetration.
--
-- Projection:
-- CAGR = (EV_2024 / EV_2022)^(1/2) - 1
-- 2030 = EV_2024 * (1 + CAGR)^6
--
-- This is a mechanical CAGR scenario, NOT a demand forecast.
-- ============================================================

WITH state_year AS (
    SELECT
        s.state,
        d.fiscal_year,
        SUM(s.electric_vehicles_sold) AS ev_units,
        SUM(s.total_vehicles_sold) AS total_units
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d ON s.date = d.date
    WHERE d.fiscal_year IN (2022, 2024)
    GROUP BY s.state, d.fiscal_year
),
state_summary AS (
    SELECT
        state,
        MAX(CASE WHEN fiscal_year = 2022 THEN ev_units END) AS ev_2022,
        MAX(CASE WHEN fiscal_year = 2024 THEN ev_units END) AS ev_2024,
        MAX(CASE WHEN fiscal_year = 2024 THEN total_units END) AS total_2024
    FROM state_year
    GROUP BY state
),
scenario AS (
    SELECT
        *,
        100.0 * ev_2024 / NULLIF(total_2024, 0) AS penetration_2024,
        CASE
            WHEN ev_2022 > 0 AND ev_2024 > 0
            THEN POWER(ev_2024 / ev_2022, 1.0 / 2) - 1
            ELSE NULL
        END AS cagr
    FROM state_summary
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            ORDER BY penetration_2024 DESC, state
        ) AS penetration_rank
    FROM scenario
)
SELECT
    state,
    ev_2022,
    ev_2024,
    ROUND(penetration_2024, 2) AS penetration_2024_pct,
    ROUND(100.0 * cagr, 2) AS cagr_pct,
    CASE
        WHEN cagr IS NOT NULL
        THEN ROUND(ev_2024 * POWER(1 + cagr, 6), 0)
        ELSE NULL
    END AS projected_ev_sales_2030,
    'Mechanical CAGR scenario; not a demand forecast' AS projection_note
FROM ranked
WHERE penetration_rank <= 10
ORDER BY penetration_rank;

-- ============================================================
-- Q10. ESTIMATED EV REVENUE GROWTH
--
-- The supplied dataset contains units, not vehicle prices.
-- Therefore revenue is estimated using explicit assumptions.
--
-- 2W average price assumption = INR 100,000
-- 4W average price assumption = INR 1,500,000
--
-- Change these variables if a different assumption is justified.
-- ============================================================

SET @avg_price_2w = 100000;
SET @avg_price_4w = 1500000;

WITH yearly_units AS (
    SELECT
        d.fiscal_year,
        SUM(CASE
            WHEN s.vehicle_category = '2-Wheelers'
            THEN s.electric_vehicles_sold ELSE 0 END) AS units_2w,
        SUM(CASE
            WHEN s.vehicle_category = '4-Wheelers'
            THEN s.electric_vehicles_sold ELSE 0 END) AS units_4w
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d ON s.date = d.date
    WHERE d.fiscal_year IN (2022, 2023, 2024)
    GROUP BY d.fiscal_year
),
revenue AS (
    SELECT
        fiscal_year,
        units_2w,
        units_4w,
        units_2w * @avg_price_2w AS revenue_2w,
        units_4w * @avg_price_4w AS revenue_4w,
        units_2w * @avg_price_2w
            + units_4w * @avg_price_4w AS total_revenue
    FROM yearly_units
)
SELECT
    fiscal_year,
    units_2w,
    units_4w,
    revenue_2w,
    revenue_4w,
    total_revenue,
    ROUND(
        100.0 * (
            total_revenue
            / NULLIF(LAG(total_revenue) OVER (ORDER BY fiscal_year), 0)
            - 1
        ),
        2
    ) AS revenue_growth_pct_vs_previous_fy
FROM revenue
ORDER BY fiscal_year;

-- Direct year-to-year growth requested by the assignment.
WITH yearly_units AS (
    SELECT
        d.fiscal_year,
        SUM(CASE WHEN s.vehicle_category = '2-Wheelers'
                 THEN s.electric_vehicles_sold ELSE 0 END) AS units_2w,
        SUM(CASE WHEN s.vehicle_category = '4-Wheelers'
                 THEN s.electric_vehicles_sold ELSE 0 END) AS units_4w
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d ON s.date = d.date
    WHERE d.fiscal_year IN (2022, 2023, 2024)
    GROUP BY d.fiscal_year
)
SELECT
    ROUND(
        100.0 * (
            POWER(
                (SELECT units_2w FROM yearly_units WHERE fiscal_year = 2024)
                / NULLIF(
                    (SELECT units_2w FROM yearly_units WHERE fiscal_year = 2022),
                    0
                ),
                1.0 / 2
            ) - 1
        ),
        2
    ) AS estimated_revenue_cagr_2w_2022_2024_pct,
    ROUND(
        100.0 * (
            POWER(
                (SELECT units_4w FROM yearly_units WHERE fiscal_year = 2024)
                / NULLIF(
                    (SELECT units_4w FROM yearly_units WHERE fiscal_year = 2022),
                    0
                ),
                1.0 / 2
            ) - 1
        ),
        2
    ) AS estimated_revenue_cagr_4w_2022_2024_pct,
    ROUND(
        100.0 * (
            (SELECT units_2w FROM yearly_units WHERE fiscal_year = 2024)
            / NULLIF(
                (SELECT units_2w FROM yearly_units WHERE fiscal_year = 2023),
                0
            ) - 1
        ),
        2
    ) AS estimated_revenue_growth_2w_2023_2024_pct,
    ROUND(
        100.0 * (
            (SELECT units_4w FROM yearly_units WHERE fiscal_year = 2024)
            / NULLIF(
                (SELECT units_4w FROM yearly_units WHERE fiscal_year = 2023),
                0
            ) - 1
        ),
        2
    ) AS estimated_revenue_growth_4w_2023_2024_pct;

-- ============================================================
-- OPTIONAL EXECUTIVE KPI SUMMARY
-- ============================================================

SELECT
    d.fiscal_year,
    SUM(s.electric_vehicles_sold) AS total_ev_units,
    SUM(s.total_vehicles_sold) AS total_vehicle_units,
    ROUND(
        100.0 * SUM(s.electric_vehicles_sold)
        / NULLIF(SUM(s.total_vehicles_sold), 0),
        2
    ) AS overall_ev_penetration_pct
FROM electric_vehicle_sales_by_state s
JOIN dim_date d ON s.date = d.date
GROUP BY d.fiscal_year
ORDER BY d.fiscal_year;

-- ============================================================
-- END OF PROJECT
-- ============================================================
