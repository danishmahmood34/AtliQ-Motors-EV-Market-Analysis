-- ============================================================
-- AtliQ Motors - EV Market Analysis
-- Database: MySQL 8.0+
-- Source datasets: Codebasics / Vahan Sewa
-- Analysis period: FY2022 - FY2024
-- ============================================================

CREATE DATABASE IF NOT EXISTS atliq_motors_ev;
USE atliq_motors_ev;

-- ============================================================
-- 1. TABLE SETUP
-- ============================================================

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
    CONSTRAINT fk_maker_date
        FOREIGN KEY (date) REFERENCES dim_date(date)
);

CREATE TABLE electric_vehicle_sales_by_state (
    date DATE NOT NULL,
    state VARCHAR(100) NOT NULL,
    vehicle_category VARCHAR(30) NOT NULL,
    electric_vehicles_sold INT NOT NULL,
    total_vehicles_sold INT NOT NULL,
    PRIMARY KEY (date, state, vehicle_category),
    CONSTRAINT fk_state_date
        FOREIGN KEY (date) REFERENCES dim_date(date)
);

-- ============================================================
-- 2. LOAD CSV DATA
-- ============================================================
-- Recommended in MySQL Workbench:
-- Use Table Data Import Wizard for the three CSV files.
--
-- If LOCAL INFILE is enabled, the following commands can be used.
-- Update the paths if necessary.
--
-- The CSV date format is DD-Mon-YY, so STR_TO_DATE() is used.

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
-- 3. DATA VALIDATION
-- ============================================================

SELECT 'dim_date' AS table_name, COUNT(*) AS row_count
FROM dim_date
UNION ALL
SELECT 'electric_vehicle_sales_by_makers', COUNT(*)
FROM electric_vehicle_sales_by_makers
UNION ALL
SELECT 'electric_vehicle_sales_by_state', COUNT(*)
FROM electric_vehicle_sales_by_state;

-- ============================================================
-- PRIMARY QUESTION 1
-- Top 3 and bottom 3 2-wheeler makers for FY2023 and FY2024
-- ============================================================

WITH maker_sales AS (
    SELECT
        d.fiscal_year,
        m.maker,
        SUM(m.electric_vehicles_sold) AS ev_units
    FROM electric_vehicle_sales_by_makers m
    JOIN dim_date d
        ON m.date = d.date
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
            PARTITION BY fiscal_year
            ORDER BY ev_units DESC, maker
        ) AS top_rank,
        ROW_NUMBER() OVER (
            PARTITION BY fiscal_year
            ORDER BY ev_units ASC, maker
        ) AS bottom_rank
    FROM maker_sales
)
SELECT
    fiscal_year,
    CASE
        WHEN top_rank <= 3 THEN 'Top 3'
        WHEN bottom_rank <= 3 THEN 'Bottom 3'
    END AS performance_group,
    maker,
    ev_units
FROM ranked
WHERE top_rank <= 3 OR bottom_rank <= 3
ORDER BY fiscal_year, performance_group, ev_units DESC;

-- ============================================================
-- PRIMARY QUESTION 2
-- Top 5 states by EV penetration in FY2024
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
    JOIN dim_date d
        ON s.date = d.date
    WHERE d.fiscal_year = 2024
    GROUP BY s.state, s.vehicle_category
),
ranked AS (
    SELECT
        state,
        vehicle_category,
        ev_units,
        total_units,
        penetration_rate,
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
-- PRIMARY QUESTION 3
-- States with a decline in EV penetration from FY2022 to FY2024
-- This uses combined 2W + 4W EV penetration.
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
    JOIN dim_date d
        ON s.date = d.date
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
-- PRIMARY QUESTION 4
-- Quarterly trends for the top 5 4-wheeler makers, FY2022-FY2024
-- Top 5 are determined by total 4W sales across the full period.
-- ============================================================

WITH maker_total AS (
    SELECT
        m.maker,
        SUM(m.electric_vehicles_sold) AS total_ev_units
    FROM electric_vehicle_sales_by_makers m
    JOIN dim_date d
        ON m.date = d.date
    WHERE m.vehicle_category = '4-Wheelers'
      AND d.fiscal_year BETWEEN 2022 AND 2024
    GROUP BY m.maker
),
top_5_makers AS (
    SELECT
        maker,
        total_ev_units,
        ROW_NUMBER() OVER (
            ORDER BY total_ev_units DESC, maker
        ) AS maker_rank
    FROM maker_total
)
SELECT
    d.fiscal_year,
    d.quarter,
    m.maker,
    SUM(m.electric_vehicles_sold) AS quarterly_ev_units
FROM electric_vehicle_sales_by_makers m
JOIN dim_date d
    ON m.date = d.date
JOIN top_5_makers t
    ON m.maker = t.maker
WHERE m.vehicle_category = '4-Wheelers'
  AND d.fiscal_year BETWEEN 2022 AND 2024
  AND t.maker_rank <= 5
GROUP BY d.fiscal_year, d.quarter, m.maker
ORDER BY d.fiscal_year, d.quarter, quarterly_ev_units DESC;

-- ============================================================
-- PRIMARY QUESTION 5
-- Delhi vs Karnataka: EV sales and penetration in FY2024
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
JOIN dim_date d
    ON s.date = d.date
WHERE d.fiscal_year = 2024
  AND s.state IN ('Delhi', 'Karnataka')
GROUP BY s.state, s.vehicle_category
ORDER BY s.state, s.vehicle_category;

-- Combined Delhi vs Karnataka view
SELECT
    s.state,
    SUM(s.electric_vehicles_sold) AS total_ev_units,
    SUM(s.total_vehicles_sold) AS total_vehicle_units,
    ROUND(
        100.0 * SUM(s.electric_vehicles_sold)
        / NULLIF(SUM(s.total_vehicles_sold), 0),
        2
    ) AS overall_penetration_rate_pct
FROM electric_vehicle_sales_by_state s
JOIN dim_date d
    ON s.date = d.date
WHERE d.fiscal_year = 2024
  AND s.state IN ('Delhi', 'Karnataka')
GROUP BY s.state
ORDER BY overall_penetration_rate_pct DESC;

-- ============================================================
-- PRIMARY QUESTION 6
-- CAGR of 4-wheeler units for the top 5 makers, FY2022-FY2024
-- CAGR period = 2 years.
-- ============================================================

WITH maker_year AS (
    SELECT
        m.maker,
        d.fiscal_year,
        SUM(m.electric_vehicles_sold) AS ev_units
    FROM electric_vehicle_sales_by_makers m
    JOIN dim_date d
        ON m.date = d.date
    WHERE m.vehicle_category = '4-Wheelers'
      AND d.fiscal_year IN (2022, 2024)
    GROUP BY m.maker, d.fiscal_year
),
maker_cagr AS (
    SELECT
        maker,
        MAX(CASE WHEN fiscal_year = 2022 THEN ev_units END) AS units_2022,
        MAX(CASE WHEN fiscal_year = 2024 THEN ev_units END) AS units_2024
    FROM maker_year
    GROUP BY maker
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY units_2024 DESC, maker
        ) AS maker_rank
    FROM maker_cagr
)
SELECT
    maker,
    units_2022,
    units_2024,
    ROUND(
        100.0 * (
            POWER(
                units_2024 / NULLIF(units_2022, 0),
                1.0 / 2
            ) - 1
        ),
        2
    ) AS cagr_pct
FROM ranked
WHERE maker_rank <= 5
ORDER BY cagr_pct DESC;

-- ============================================================
-- PRIMARY QUESTION 7
-- Top 10 states by CAGR in total vehicles sold, FY2022-FY2024
-- ============================================================

WITH state_year AS (
    SELECT
        s.state,
        d.fiscal_year,
        SUM(s.total_vehicles_sold) AS total_vehicle_units
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d
        ON s.date = d.date
    WHERE d.fiscal_year IN (2022, 2024)
    GROUP BY s.state, d.fiscal_year
),
state_cagr AS (
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
            POWER(
                total_2024 / NULLIF(total_2022, 0),
                1.0 / 2
            ) - 1
        ),
        2
    ) AS cagr_pct
FROM state_cagr
WHERE total_2022 > 0
ORDER BY cagr_pct DESC
LIMIT 10;

-- ============================================================
-- PRIMARY QUESTION 8
-- Peak and low season months for EV sales, 2022-2024
-- Months are aggregated across all three fiscal years.
-- ============================================================

WITH monthly_sales AS (
    SELECT
        MONTH(s.date) AS month_number,
        MONTHNAME(s.date) AS month_name,
        SUM(s.electric_vehicles_sold) AS ev_units
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d
        ON s.date = d.date
    WHERE d.fiscal_year BETWEEN 2022 AND 2024
    GROUP BY MONTH(s.date), MONTHNAME(s.date)
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY ev_units DESC) AS peak_rank,
        RANK() OVER (ORDER BY ev_units ASC) AS low_rank
    FROM monthly_sales
)
SELECT
    month_number,
    month_name,
    ev_units,
    CASE
        WHEN peak_rank = 1 THEN 'Peak'
        WHEN low_rank = 1 THEN 'Low'
        ELSE 'Normal'
    END AS season_type
FROM ranked
ORDER BY month_number;

-- ============================================================
-- PRIMARY QUESTION 9
-- Projected 2030 EV sales for the top 10 FY2024 states
-- ranked by combined 2W + 4W penetration.
--
-- Projection method:
-- CAGR (2022-2024) = (Sales_2024 / Sales_2022)^(1/2) - 1
-- 2030 projection = Sales_2024 * (1 + CAGR)^6
-- ============================================================

WITH state_year AS (
    SELECT
        s.state,
        d.fiscal_year,
        SUM(s.electric_vehicles_sold) AS ev_units,
        SUM(s.total_vehicles_sold) AS total_units
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d
        ON s.date = d.date
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
penetration_ranked AS (
    SELECT
        *,
        100.0 * ev_2024 / NULLIF(total_2024, 0) AS penetration_2024,
        POWER(
            ev_2024 / NULLIF(ev_2022, 0),
            1.0 / 2
        ) - 1 AS cagr
    FROM state_summary
),
top_10 AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY penetration_2024 DESC, state
        ) AS penetration_rank
    FROM penetration_ranked
)
SELECT
    state,
    ev_2022,
    ev_2024,
    ROUND(100.0 * penetration_2024, 2) AS penetration_2024_pct,
    ROUND(100.0 * cagr, 2) AS cagr_pct,
    ROUND(
        ev_2024 * POWER(1 + cagr, 6),
        0
    ) AS projected_ev_sales_2030
FROM top_10
WHERE penetration_rank <= 10
ORDER BY penetration_rank;

-- ============================================================
-- PRIMARY QUESTION 10
-- Estimated EV revenue growth: 2022 vs 2024 and 2023 vs 2024
--
-- IMPORTANT:
-- The supplied datasets contain EV units, not vehicle prices.
-- Therefore this is an estimated revenue model.
--
-- Default assumptions below can be changed:
-- 2-wheeler average unit price = INR 100,000
-- 4-wheeler average unit price = INR 1,500,000
--
-- Revenue growth percentages do not depend on the price assumption
-- when the same average unit price is applied across years.
-- ============================================================

SET @avg_price_2w = 100000;
SET @avg_price_4w = 1500000;

WITH yearly_units AS (
    SELECT
        d.fiscal_year,
        SUM(
            CASE
                WHEN s.vehicle_category = '2-Wheelers'
                    THEN s.electric_vehicles_sold
                ELSE 0
            END
        ) AS ev_2w_units,
        SUM(
            CASE
                WHEN s.vehicle_category = '4-Wheelers'
                    THEN s.electric_vehicles_sold
                ELSE 0
            END
        ) AS ev_4w_units
    FROM electric_vehicle_sales_by_state s
    JOIN dim_date d
        ON s.date = d.date
    WHERE d.fiscal_year IN (2022, 2023, 2024)
    GROUP BY d.fiscal_year
),
revenue AS (
    SELECT
        fiscal_year,
        ev_2w_units,
        ev_4w_units,
        ev_2w_units * @avg_price_2w AS revenue_2w,
        ev_4w_units * @avg_price_4w AS revenue_4w,
        (ev_2w_units * @avg_price_2w)
            + (ev_4w_units * @avg_price_4w) AS total_revenue
    FROM yearly_units
)
SELECT
    fiscal_year,
    ev_2w_units,
    ev_4w_units,
    revenue_2w,
    revenue_4w,
    total_revenue,
    ROUND(
        100.0 * (
            total_revenue
            / NULLIF(
                LAG(total_revenue) OVER (ORDER BY fiscal_year),
                0
            ) - 1
        ),
        2
    ) AS revenue_growth_pct_vs_previous_fy
FROM revenue
ORDER BY fiscal_year;

-- Direct comparison requested in the assignment:
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
    ) AS revenue_growth_2w_2022_vs_2024_pct,
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
    ) AS revenue_growth_4w_2022_vs_2024_pct,
    ROUND(
        100.0 * (
            (SELECT units_2w FROM yearly_units WHERE fiscal_year = 2024)
            / NULLIF(
                (SELECT units_2w FROM yearly_units WHERE fiscal_year = 2023),
                0
            ) - 1
        ),
        2
    ) AS revenue_growth_2w_2023_vs_2024_pct,
    ROUND(
        100.0 * (
            (SELECT units_4w FROM yearly_units WHERE fiscal_year = 2024)
            / NULLIF(
                (SELECT units_4w FROM yearly_units WHERE fiscal_year = 2023),
                0
            ) - 1
        ),
        2
    ) AS revenue_growth_4w_2023_vs_2024_pct;

-- ============================================================
-- OPTIONAL: QUICK KPI SUMMARY
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
JOIN dim_date d
    ON s.date = d.date
GROUP BY d.fiscal_year
ORDER BY d.fiscal_year;

-- ============================================================
-- END OF ANALYSIS
-- ============================================================
