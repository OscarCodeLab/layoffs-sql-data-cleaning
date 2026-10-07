/* ================================================================
   PROJECT  : Layoffs Data Cleaning
   TOOL     : Microsoft SQL Server / SSMS
   REQUIRES : SQL Server 2017 or later (uses TRIM, TRY_CONVERT,
              DROP TABLE IF EXISTS)
   AUTHOR   : Kolawole Opeyemi Oscar
   DATABASE : DataCleaningLab
   SOURCE   : layoffs.csv (Layoffs.fyi data from Kaggle), 4,615 rows, 11 columns

   TABLE FLOW:
   layoffs_raw        original import, never modified
   layoffs_Staging    working copy for cleaning and type conversion
   layoffs_Staging2   duplicates removed (one row per layoff event)
   layoffs_clean      final cleaned table

   IMPORT:
   Loaded with the Import and Export Wizard (Flat File Source): comma
   delimited, text qualifier ", UTF-8, every column as NVARCHAR text
   (source width 600). Nothing is rejected or changed on import, which is
   why raw values look like 96.0, '' for blanks and m/d/yyyy dates.

   CLEANING APPROACH:
   - Trim spaces and convert blanks to NULL
   - Standardize inconsistent text values
   - Convert dates and numbers to proper data types
   - Remove duplicates last, on the cleaned values

   FINAL DATA TYPES:
   total_laid_off        INT
   layoff_date           DATE
   date_added            DATE
   percentage_laid_off   DECIMAL(7,4)
   funds_raised          DECIMAL(18,4)
   Other columns         Text

   NOTES:
   - funds_raised is kept as provided: the file gives no unit or currency.

   KNOWN LIMITATIONS (left as provided, reviewed but not changed):
   - A few near-duplicate events remain because they differ in funds_raised
     (e.g. FNZ 2023-07-06, Oda 2022-11-01).
   - TaskUs (2022-06-21) shows 52 laid off at 0%, which is probably a
     missing value in the source.
   - Netflix funds_raised (121,900) is an outlier from the source.
   ================================================================ */
USE DataCleaningLab;

/* Re-run safety: rebuild everything from layoffs_raw (which is never touched) */
DROP TABLE IF EXISTS layoffs_clean;

DROP TABLE IF EXISTS layoffs_Staging2;

DROP TABLE IF EXISTS layoffs_Staging;

/* ================================================================
   STEP 1: CREATE A STAGING COPY
   Keep the original raw data untouched.
   ================================================================ */
SELECT *
INTO   layoffs_Staging
FROM   layoffs_raw;

SELECT TOP 20 *
FROM   layoffs_Staging;

/* ================================================================
   STEP 2: RENAME DATE COLUMN
   "date" is also a SQL Server data type name, so layoff_date is clearer.
   ================================================================ */
EXECUTE sp_rename 'dbo.layoffs_Staging.date', 'layoff_date', 'COLUMN';

SELECT TOP 20 *
FROM   layoffs_Staging;

/* ================================================================
   STEP 3: CLEAN TEXT COLUMNS
   Remove unnecessary spaces and convert blank values to NULL.
   ================================================================ */
UPDATE layoffs_Staging
SET    company  = NULLIF (TRIM(company), ''),
       location = NULLIF (TRIM(location), ''),
       industry = NULLIF (TRIM(industry), ''),
       source   = NULLIF (TRIM(source), ''),
       stage    = NULLIF (TRIM(stage), ''),
       country  = NULLIF (TRIM(country), '');

/* Clean company names.
   Three company names end with the word "copy" (left over from the source
   spreadsheet), for example "Sage Therapeutics copy". The word is not part
   of the real name, so it is removed. */
-- Preview first: which rows will change? (expect 3 rows)
SELECT company,
       location
FROM   layoffs_Staging
WHERE  company LIKE '% copy';

-- Remove the word " copy" and any extra spaces left behind
UPDATE layoffs_Staging
SET    company = TRIM(REPLACE(company, ' copy', ''))
WHERE  company LIKE '% copy'; -- 3 rows

-- Check: should now return 0 rows
SELECT company
FROM   layoffs_Staging
WHERE  company LIKE '% copy';

/* Merge company names spelled with different capitalization.
   Seven companies appear with two spellings, for example "Tiktok" and
   "TikTok". They are the same company, so each gets one official spelling.
   Mara/MARA and Loop/LOOP are NOT merged: they are different companies. */
-- Preview: show every spelling (COLLATE ...CS... makes SQL Server see capitals)
SELECT   DISTINCT company COLLATE Latin1_General_CS_AS AS spelling
FROM     layoffs_Staging
WHERE    company IN ('7shifts', 'Appgate', 'Clearco', 'FreshBooks', 'Salesloft', 'TikTok', 'UiPath')
ORDER BY spelling; -- expect 14 rows (2 per company)

-- Give each company one official spelling
UPDATE layoffs_Staging
SET    company = CASE WHEN company = '7shifts' THEN '7shifts' WHEN company = 'Appgate' THEN 'Appgate' WHEN company = 'Clearco' THEN 'Clearco' WHEN company = 'FreshBooks' THEN 'FreshBooks' WHEN company = 'Salesloft' THEN 'Salesloft' WHEN company = 'TikTok' THEN 'TikTok' WHEN company = 'UiPath' THEN 'UiPath' ELSE company END
WHERE  company IN ('7shifts', 'Appgate', 'Clearco', 'FreshBooks', 'Salesloft', 'TikTok', 'UiPath'); -- 29 rows

-- Check: run the preview again, expect 7 rows (one spelling each)
SELECT   DISTINCT company COLLATE Latin1_General_CS_AS AS spelling
FROM     layoffs_Staging
WHERE    company IN ('7shifts', 'Appgate', 'Clearco', 'FreshBooks', 'Salesloft', 'TikTok', 'UiPath')
ORDER BY spelling;

/* Standardize location names.
   Business rule: the country column already holds the country, so
   ", Non-U.S." is removed ("London" and "London, Non-U.S." were two places). */
UPDATE layoffs_Staging
SET    location = TRIM(REPLACE(location, ', Non-U.S.', ''));

/* Standardize country name.
   UAE and United Arab Emirates are the same country. */
UPDATE layoffs_Staging
SET    country = 'United Arab Emirates'
WHERE  country = 'UAE';

/* Fill the two missing countries where the location
   clearly identifies the country. */
SELECT company,
       location,
       country
FROM   layoffs_Staging
WHERE  country IS NULL; -- expect 2 rows (Berlin, Montreal)

UPDATE layoffs_Staging
SET    country = 'Germany'
WHERE  location LIKE 'Berlin%'
       AND country IS NULL;

UPDATE layoffs_Staging
SET    country = 'Canada'
WHERE  location LIKE 'Montreal%'
       AND country IS NULL;

SELECT company,
       location,
       country
FROM   layoffs_Staging
WHERE  country IS NULL; -- expect 0 rows

/* Fix locations that are only "Non-U.S." (no city).
   Four rows have "Non-U.S." in the location column instead of a city
   (BitMEX x3, WeDoctor). It is a placeholder, not a place, so it becomes
   'Unknown' like the other missing locations. The country column still
   shows where the company is. */
-- Preview: which rows will change? (expect 4 rows)
SELECT company,
       location,
       country
FROM   layoffs_Staging
WHERE  location = 'Non-U.S.';

-- Replace the placeholder with 'Unknown'
UPDATE layoffs_Staging
SET    location = 'Unknown'
WHERE  location = 'Non-U.S.'; -- 4 rows

-- Check: should now return 0 rows
SELECT company,
       location
FROM   layoffs_Staging
WHERE  location = 'Non-U.S.';

/* Handle missing and inconsistent values in stage, industry, location and source.
   Missing stage, industry and location become 'Unknown' (stage already uses
   it for 776 rows), so they show up as a group in GROUP BY. Numbers, dates
   and source keep NULL. 'Company exec' is merged into 'Company executive'
   and the placeholder 'Read more at:' is set to NULL. */
SELECT   DISTINCT stage
FROM     layoffs_Staging
ORDER BY 1;

SELECT   DISTINCT industry
FROM     layoffs_Staging
ORDER BY 1;

SELECT   source,
         COUNT(*) AS rows_count
FROM     layoffs_Staging
WHERE    source NOT LIKE 'http%'
GROUP BY source
ORDER BY rows_count DESC;

UPDATE layoffs_Staging
SET    stage = 'Unknown'
WHERE  stage IS NULL; -- 8 rows

UPDATE layoffs_Staging
SET    industry = 'Unknown'
WHERE  industry IS NULL; -- 2 rows

UPDATE layoffs_Staging
SET    location = 'Unknown'
WHERE  location IS NULL; -- 1 row

UPDATE layoffs_Staging
SET    source = 'Company executive'
WHERE  source = 'Company exec'; -- 7 rows

UPDATE layoffs_Staging
SET    source = NULL
WHERE  source = 'Read more at:'; -- 1 row

/* 'Times Internet' and one cut-off link are left as provided
   (they cannot be fixed without guessing). */
/* ================================================================
   STEP 4: CONVERT DATE COLUMNS
   The source dates are stored as text in m/d/yyyy format.
   Style 101 = m/d/yyyy. A wrong style could swap day and month.
   ================================================================ */
SELECT TOP 20 layoff_date,
              TRY_CONVERT (DATE, layoff_date, 101) AS converted_date
FROM   layoffs_Staging;

SELECT TOP 20 date_added,
              TRY_CONVERT (DATE, date_added, 101) AS converted_date
FROM   layoffs_Staging;

/* Check for invalid dates (expect 0 rows) */
SELECT layoff_date
FROM   layoffs_Staging
WHERE  layoff_date IS NOT NULL
       AND TRY_CONVERT (DATE, layoff_date, 101) IS NULL;

SELECT date_added
FROM   layoffs_Staging
WHERE  date_added IS NOT NULL
       AND TRY_CONVERT (DATE, date_added, 101) IS NULL;

/* Convert blank dates to NULL (TRY_CONVERT would turn '' into 1900-01-01) */
UPDATE layoffs_Staging
SET    layoff_date = NULLIF (TRIM(layoff_date), ''),
       date_added  = NULLIF (TRIM(date_added), '');

/* Rewrite as yyyy-mm-dd, a format SQL Server always reads correctly */
UPDATE layoffs_Staging
SET    layoff_date = CONVERT (VARCHAR (10), TRY_CONVERT (DATE, layoff_date, 101), 23);

UPDATE layoffs_Staging
SET    date_added = CONVERT (VARCHAR (10), TRY_CONVERT (DATE, date_added, 101), 23);

/* Change the columns to DATE */
ALTER TABLE layoffs_Staging ALTER COLUMN layoff_date DATE NULL;

ALTER TABLE layoffs_Staging ALTER COLUMN date_added DATE NULL;

/* ================================================================
   STEP 5: CONVERT TOTAL_LAID_OFF
   A blank means "not reported", not "zero layoffs", so blanks
   become NULL and are never replaced with 0.
   ================================================================ */
SELECT DISTINCT total_laid_off
FROM   layoffs_Staging;

/* Check for invalid numeric values (expect 0 rows) */
SELECT total_laid_off
FROM   layoffs_Staging
WHERE  TRIM(total_laid_off) <> ''
       AND TRY_CAST (total_laid_off AS DECIMAL (18, 2)) IS NULL;

/* Convert blanks to NULL */
UPDATE layoffs_Staging
SET    total_laid_off = NULLIF (TRIM(total_laid_off), '');

/* Convert values such as 96.0 to 96
   (text like '96.0' cannot go straight to INT) */
UPDATE layoffs_Staging
SET    total_laid_off = CAST (CAST (total_laid_off AS DECIMAL (18, 2)) AS INT)
WHERE  total_laid_off IS NOT NULL;

/* Change column to INT */
ALTER TABLE layoffs_Staging ALTER COLUMN total_laid_off INT NULL;

/* ================================================================
   STEP 6: CONVERT PERCENTAGE_LAID_OFF
   Values are stored between 0 and 1 (1 = 100%).
   ================================================================ */
SELECT DISTINCT percentage_laid_off
FROM   layoffs_Staging;

/* Check for invalid values (expect 0 rows) */
SELECT percentage_laid_off
FROM   layoffs_Staging
WHERE  TRIM(percentage_laid_off) <> ''
       AND TRY_CAST (percentage_laid_off AS DECIMAL (7, 4)) IS NULL;

/* Convert blanks to NULL (before the type change, so they stay NULL) */
UPDATE layoffs_Staging
SET    percentage_laid_off = NULLIF (TRIM(percentage_laid_off), '');

/* Change column to DECIMAL */
ALTER TABLE layoffs_Staging ALTER COLUMN percentage_laid_off DECIMAL (7, 4) NULL;

/* ================================================================
   STEP 7: CONVERT FUNDS_RAISED
   ================================================================ */
SELECT   DISTINCT funds_raised
FROM     layoffs_Staging
ORDER BY 1;

/* Check for invalid values (expect 0 rows) */
SELECT funds_raised
FROM   layoffs_Staging
WHERE  TRIM(funds_raised) <> ''
       AND TRY_CAST (funds_raised AS DECIMAL (18, 4)) IS NULL;

/* Convert blanks to NULL */
UPDATE layoffs_Staging
SET    funds_raised = NULLIF (TRIM(funds_raised), '');

/* Keep four decimal places so source precision is not unnecessarily lost */
ALTER TABLE layoffs_Staging ALTER COLUMN funds_raised DECIMAL (18, 4) NULL;

/* ================================================================
   STEP 8: REMOVE DUPLICATES
   ROW_NUMBER() is applied across the columns that describe the layoff event.
   source and date_added are left out: they describe the report, not the
   layoff. date_added is a real DATE by now, so ORDER BY keeps the earliest.
   ================================================================ */
SELECT COUNT(*) AS rows_before
FROM   layoffs_Staging;

WITH   Duplicate_CTE
AS     (SELECT *,
               ROW_NUMBER() OVER (PARTITION BY company, location, total_laid_off, layoff_date, percentage_laid_off, industry, stage, funds_raised, country ORDER BY date_added) AS Row_Num
        FROM   layoffs_Staging)
SELECT *
INTO   layoffs_Staging2
FROM   Duplicate_CTE
WHERE  Row_Num = 1;

/* Check number of rows after removing duplicates */
SELECT COUNT(*) AS cleaned_staging_rows
FROM   layoffs_Staging2;

/* ================================================================
   STEP 9: REMOVE HELPER COLUMN
   ================================================================ */
ALTER TABLE layoffs_Staging2 DROP COLUMN Row_Num;

/* ================================================================
   STEP 10: CREATE FINAL CLEAN TABLE
   Rename Staging2 instead of copying it again.
   ================================================================ */
EXECUTE sp_rename 'dbo.layoffs_Staging2', 'layoffs_clean';

/* ================================================================
   STEP 11: FINAL VALIDATION
   ================================================================ */
/* Compare row counts (the difference is the duplicates removed) */
SELECT 'Raw' AS table_name,
       COUNT(*) AS row_count
FROM   layoffs_raw
UNION ALL
SELECT 'Clean',
       COUNT(*)
FROM   layoffs_clean;

/* Check final data types */
SELECT   COLUMN_NAME,
         DATA_TYPE
FROM     INFORMATION_SCHEMA.COLUMNS
WHERE    TABLE_NAME = 'layoffs_clean'
ORDER BY ORDINAL_POSITION;

/* Check for remaining duplicates (expect 0 rows) */
WITH   Duplicate_Check
AS     (SELECT *,
               ROW_NUMBER() OVER (PARTITION BY company, location, total_laid_off, layoff_date, percentage_laid_off, industry, stage, funds_raised, country ORDER BY date_added) AS Row_Num
        FROM   layoffs_clean)
SELECT *
FROM   Duplicate_Check
WHERE  Row_Num > 1;

/* Check invalid percentage values (expect 0 rows) */
SELECT *
FROM   layoffs_clean
WHERE  percentage_laid_off < 0
       OR percentage_laid_off > 1;

/* Check invalid total layoffs (expect 0 rows) */
SELECT *
FROM   layoffs_clean
WHERE  total_laid_off < 0;

/* Check for layoff dates in the future (expect 0 rows) */
SELECT *
FROM   layoffs_clean
WHERE  layoff_date > CAST (GETDATE() AS DATE);

/* Check for placeholder dates (expect 0 rows) */
SELECT *
FROM   layoffs_clean
WHERE  layoff_date < '1990-01-01'
       OR date_added < '1990-01-01';

/* Check that no country is missing (expect 0 rows) */
SELECT *
FROM   layoffs_clean
WHERE  country IS NULL;

/* Check remaining missing values.
   Numbers stay NULL when not reported. Missing stage, industry and
   location are 'Unknown'.
   These rows are kept on purpose: they still hold a company and a date.
   Filtering them out is an analysis decision, not cleaning. */
SELECT SUM(CASE WHEN total_laid_off IS NULL THEN 1 ELSE 0 END) AS missing_total_laid_off,
       SUM(CASE WHEN percentage_laid_off IS NULL THEN 1 ELSE 0 END) AS missing_percentage_laid_off,
       SUM(CASE WHEN funds_raised IS NULL THEN 1 ELSE 0 END) AS missing_funds_raised,
       SUM(CASE WHEN industry = 'Unknown' THEN 1 ELSE 0 END) AS unknown_industry,
       SUM(CASE WHEN location = 'Unknown' THEN 1 ELSE 0 END) AS unknown_location,
       SUM(CASE WHEN stage = 'Unknown' THEN 1 ELSE 0 END) AS unknown_stage
FROM   layoffs_clean;

/* Final preview */
SELECT   TOP 20 *
FROM     layoffs_clean
ORDER BY layoff_date;
