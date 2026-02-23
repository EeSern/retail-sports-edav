/* =========================================================
   Retail Sports — Real Names, Real Product Names,
   Skewed Orders by City (No FKs, NULLs, Duplicates)
   Permanent tables: Numbers, Customers, Products, Sales, Stores, Suppliers
   Authored by Namaxee
   ========================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* ---------- (Re)Create database ---------- */
IF DB_ID('RetailSports_Staging') IS NOT NULL
BEGIN
    ALTER DATABASE RetailSports_Staging SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RetailSports_Staging;
END;
CREATE DATABASE RetailSports_Staging;
GO

USE RetailSports_Staging;
/* Keep everything below in ONE batch (no more GO) */

/* ---------- Sizing knobs ---------- */
DECLARE @Customers            int = 50000;
DECLARE @Products             int = 1200;
DECLARE @Stores               int = 120;
DECLARE @Suppliers            int = 40;
DECLARE @Sales                int = 150000;   -- keep >= 100000
DECLARE @DuplicateCustomers   int = 2500;
DECLARE @DuplicateSales       int = 5000;

/* ---------- Numbers table (1..800000) ---------- */
IF OBJECT_ID('dbo.Numbers','U') IS NOT NULL DROP TABLE dbo.Numbers;
CREATE TABLE dbo.Numbers(n int not null primary key);
;WITH src AS
(
    SELECT TOP (800000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT dbo.Numbers(n) SELECT rn FROM src;

/* ---------- Permanent base tables (no foreign keys) ---------- */
IF OBJECT_ID('dbo.Customers','U') IS NOT NULL DROP TABLE dbo.Customers;
CREATE TABLE dbo.Customers
(
    CustomerID  int identity(1,1) primary key,
    FirstName   nvarchar(50)  null,
    LastName    nvarchar(50)  null,
    Email       nvarchar(120) null,
    Phone       nvarchar(30)  null,
    Gender      nvarchar(10)  null,
    BirthDate   date          null,
    City        nvarchar(60)  null,
    State       nvarchar(60)  null,
    Country     nvarchar(60)  null,
    SignupDate  date          null
);

IF OBJECT_ID('dbo.Suppliers','U') IS NOT NULL DROP TABLE dbo.Suppliers;
CREATE TABLE dbo.Suppliers
(
    SupplierID   int identity(1,1) primary key,
    SupplierName nvarchar(120) not null,
    Country      nvarchar(60)  null
);

IF OBJECT_ID('dbo.Stores','U') IS NOT NULL DROP TABLE dbo.Stores;
CREATE TABLE dbo.Stores
(
    StoreID   int identity(1,1) primary key,
    StoreName nvarchar(120) not null,
    City      nvarchar(60)  null,
    State     nvarchar(60)  null,
    Country   nvarchar(60)  null,
    StoreType nvarchar(30)  null,    -- Retail / Outlet / Express / Flagship
    OpenDate  date          null
);

IF OBJECT_ID('dbo.Products','U') IS NOT NULL DROP TABLE dbo.Products;
CREATE TABLE dbo.Products
(
    ProductID      int identity(1,1) primary key,
    SKU            nvarchar(30)  not null,
    ProductName    nvarchar(200) not null,   -- real product names
    Category       nvarchar(60)  not null,   -- Balls, Racquets, Fitness, Cycling, etc.
    Subcategory    nvarchar(60)  null,
    Brand          nvarchar(60)  null,       -- some NULLs on purpose
    Model          nvarchar(60)  null,
    LaunchDate     date          null,
    UnitPrice      decimal(10,2) null,
    CostPrice      decimal(10,2) null,
    WarrantyMonths int           null,       -- 3–36 typical for sports gear
    SupplierID     int           null
);

IF OBJECT_ID('dbo.Sales','U') IS NOT NULL DROP TABLE dbo.Sales;
CREATE TABLE dbo.Sales
(
    SalesID       bigint identity(1,1) primary key,
    OrderDate     date          not null,
    ShipDate      date          null,
    CustomerID    int           null,
    StoreID       int           null,
    ProductID     int           null,
    Quantity      int           not null,
    UnitPrice     decimal(10,2) null,
    Discount      decimal(5,2)  null,
    TotalAmount   decimal(12,2) null,
    PaymentMethod nvarchar(30)  null,   -- Credit Card / Debit Card / E-Wallet / Bank Transfer / Cash
    Channel       nvarchar(30)  null,   -- Online / In-Store / Marketplace
    OrderStatus   nvarchar(20)  null    -- Completed / Cancelled / Returned / Pending
);

/* ---------- Suppliers ---------- */
INSERT dbo.Suppliers(SupplierName, Country)
SELECT TOP (@Suppliers)
       CONCAT('Sports Supplier ', n),
       CHOOSE((n%10)+1,'Malaysia','Japan','South Korea','China','Singapore','USA','Germany','Canada','Australia','UK')
FROM dbo.Numbers
ORDER BY n;

/* ---------- Cities reference (CTE only) ---------- */
;WITH cities AS
(
    SELECT * FROM (VALUES
    ('Kuala Lumpur','Federal Territory','Malaysia'),
    ('Petaling Jaya','Selangor','Malaysia'),
    ('Shah Alam','Selangor','Malaysia'),
    ('Johor Bahru','Johor','Malaysia'),
    ('George Town','Penang','Malaysia'),
    ('Ipoh','Perak','Malaysia'),
    ('Kuching','Sarawak','Malaysia'),
    ('Kota Kinabalu','Sabah','Malaysia'),
    ('Melaka','Melaka','Malaysia'),
    ('Seremban','Negeri Sembilan','Malaysia'),
    ('Kuantan','Pahang','Malaysia'),
    ('Alor Setar','Kedah','Malaysia'),
    ('Miri','Sarawak','Malaysia'),
    ('Sandakan','Sabah','Malaysia'),
    ('Sibu','Sarawak','Malaysia')
    ) c(City,State,Country)
),
cities_n AS
(
    SELECT City, State, Country,
           ROW_NUMBER() OVER (ORDER BY City) AS rn,
           15 AS total
    FROM cities
)
/* ---------- Stores (evenly across 15 cities) ---------- */
INSERT dbo.Stores(StoreName, City, State, Country, StoreType, OpenDate)
SELECT TOP (@Stores)
       CONCAT('SportZone ', t.n) AS StoreName,
       cn.City, cn.State, cn.Country,
       CHOOSE( (t.n%5)+1, 'Retail','Retail','Outlet','Express','Flagship') AS StoreType,
       DATEADD(DAY, - (t.n%3650), CAST(GETDATE() AS date)) AS OpenDate
FROM dbo.Numbers t
JOIN cities_n cn
  ON ((t.n - 1) % cn.total) + 1 = cn.rn
ORDER BY t.n;

/* =========================================================
   Helper lists as TABLE VARIABLES (no permanent tables)
   ========================================================= */

/* --- Name pairs (aligned FirstName + LastName) --- */
DECLARE @NamePairs TABLE
(
    RowID    int identity(1,1) primary key,
    LastName nvarchar(50),
    FirstName nvarchar(50)
);
/* Chinese-style */
INSERT @NamePairs(LastName,FirstName) VALUES
('Lee','Wei'),('Lee','Jia'),('Lee','Mei'),('Lee','Yong'),('Lee','Hui'),
('Tan','Wei'),('Tan','Li'),('Tan','Jia'),('Tan','Mei'),('Tan','Hui'),
('Lim','Wei'),('Lim','Li'),('Lim','Jia'),('Lim','Mei'),('Lim','Yong'),
('Chen','Wei'),('Chen','Li'),('Chen','Hui'),('Chen','Jia'),('Chen','Mei'),
('Goh','Wei'),('Goh','Li'),('Goh','Jia'),('Goh','Mei'),('Goh','Hui');
/* Malay-style */
INSERT @NamePairs(LastName,FirstName) VALUES
('Rahman','Muhammad'),('Rahman','Ahmad'),('Rahman','Aisyah'),('Rahman','Nurul'),('Rahman','Siti'),
('Abdullah','Muhammad'),('Abdullah','Amin'),('Abdullah','Farah'),('Abdullah','Haziq'),('Abdullah','Aqil'),
('Hassan','Khairul'),('Hassan','Nadia'),('Ismail','Syafiq'),('Ismail','Nisa');
/* Indian-style */
INSERT @NamePairs(LastName,FirstName) VALUES
('Kumar','Arjun'),('Kumar','Priya'),('Kumar','Ravi'),('Kumar','Deepa'),
('Singh','Vijay'),('Singh','Neha'),('Nair','Rahul'),('Iyer','Anita');
/* Western-style */
INSERT @NamePairs(LastName,FirstName) VALUES
('Smith','James'),('Smith','Mary'),('Johnson','John'),('Johnson','Patricia'),
('Williams','Robert'),('Williams','Jennifer'),('Brown','Michael'),('Brown','Sarah'),
('Davis','William'),('Miller','Elizabeth'),('Wilson','David'),('Taylor','Emily');

DECLARE @NamePairCount int = (SELECT COUNT(*) FROM @NamePairs);

/* --- Real sports product catalog --- */
DECLARE @ProductCatalog TABLE
(
    CatalogID   int identity(1,1) primary key,
    Category    nvarchar(60)  not null,
    Subcategory nvarchar(60)  null,
    Brand       nvarchar(60)  not null,
    ProductName nvarchar(200) not null,
    Model       nvarchar(60)  null,
    BasePrice   decimal(10,2) not null
);

/* Balls (Football/Soccer, Basketball, Volleyball) */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Balls','Soccer','adidas','Al Rihla Pro Match Ball',NULL,699),
('Balls','Soccer','Nike','Flight Match Ball',NULL,649),
('Balls','Soccer','Puma','Orbita Match Ball',NULL,499),
('Balls','Basketball','Wilson','Evolution Game Basketball',NULL,329),
('Balls','Basketball','Spalding','NBA Zi/O Basketball',NULL,299),
('Balls','Volleyball','Mikasa','V200W Volleyball',NULL,399);

/* Racquets (Badminton & Tennis) */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Racquets','Badminton','Yonex','Astrox 100 ZZ',NULL,899),
('Racquets','Badminton','Yonex','Nanoflare 1000Z',NULL,899),
('Racquets','Badminton','Li-Ning','Windstorm 72',NULL,599),
('Racquets','Badminton','Victor','Thruster K 9000',NULL,799),
('Racquets','Tennis','Wilson','Pro Staff 97 v14',NULL,1199),
('Racquets','Tennis','Babolat','Pure Drive 2021',NULL,999),
('Racquets','Tennis','HEAD','Speed Pro 360+',NULL,1099),
('Racquets','Tennis','Yonex','Ezone 98',NULL,1099);

/* Fitness (Strength, Yoga, Suspension) */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Fitness','Dumbbells','Bowflex','SelectTech 552 Pair',NULL,1899),
('Fitness','Dumbbells','PowerBlock','Pro 50 Set',NULL,2299),
('Fitness','Yoga Mat','Manduka','PRO Yoga Mat',NULL,499),
('Fitness','Yoga Mat','lululemon','Reversible Mat 5mm',NULL,379),
('Fitness','Suspension','TRX','Home2 System',NULL,899),
('Fitness','Bands','Theraband','Resistance Bands Set',NULL,129);

/* Running Shoes (Sports Footwear) */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Footwear','Running','Nike','Air Zoom Pegasus 40',NULL,529),
('Footwear','Running','adidas','Ultraboost Light',NULL,799),
('Footwear','Running','ASICS','Gel-Kayano 30',NULL,699),
('Footwear','Running','HOKA','Clifton 9',NULL,679),
('Footwear','Running','New Balance','Fresh Foam 1080 v13',NULL,749);

/* Cycling (Helmets, Pumps, Pedals, Computers, Lights) */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Cycling','Helmet','Giro','Synthe MIPS II',NULL,999),
('Cycling','Helmet','Specialized','S-Works Prevail 3',NULL,1299),
('Cycling','Pedals','Shimano','SPD-SL PD-R7000',NULL,399),
('Cycling','Pump','Topeak','JoeBlow Sport III',NULL,219),
('Cycling','Computer','Garmin','Edge 530',NULL,1299),
('Cycling','Lights','CatEye','AMPP 500 Light Set',NULL,239);

/* Outdoor (Camping & Hydration) */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Outdoor','Tent','Coleman','Sundome 4 Tent',NULL,499),
('Outdoor','Tent','Quechua','2 Seconds Easy Tent',NULL,599),
('Outdoor','Pack','Osprey','Talon 22 Backpack',NULL,699),
('Outdoor','Bottle','CamelBak','Eddy Plus 0.75L',NULL,129);

/* Swimming (Goggles, Caps, Fins) */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Swimming','Goggles','Speedo','Vanquisher 2.0',NULL,129),
('Swimming','Goggles','Arena','Cobra Ultra',NULL,199),
('Swimming','Cap','Speedo','Silicone Swim Cap',NULL,49),
('Swimming','Fins','Arena','Powerfin Pro',NULL,259);

/* Cricket */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Cricket','Bat','Kookaburra','Kahuna 5.1',NULL,699),
('Cricket','Bat','Gray-Nicolls','Classic 500',NULL,799),
('Cricket','Ball','Kookaburra','Regulation Match Ball',NULL,129),
('Cricket','Gloves','Gunn & Moore','Diamond Batting Gloves',NULL,259);

/* Table Tennis */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Table Tennis','Paddle','STIGA','Pro Carbon',NULL,299),
('Table Tennis','Balls','DHS','3-Star 40+ Balls 6-pack',NULL,49),
('Table Tennis','Table','JOOLA','Inside 15 Table',NULL,1999);

/* Golf */
INSERT @ProductCatalog(Category,Subcategory,Brand,ProductName,Model,BasePrice) VALUES
('Golf','Balls','Titleist','Pro V1 (12-pack)',NULL,269),
('Golf','Driver','TaylorMade','Stealth 2 Driver',NULL,2999),
('Golf','Balls','Callaway','Chrome Soft (12-pack)',NULL,259),
('Golf','Putter','Odyssey','White Hot Pro 2.0',NULL,1099);

DECLARE @CatalogCount int = (SELECT COUNT(*) FROM @ProductCatalog);

/* --- City weights (table variable) to skew orders by city --- */
DECLARE @CityWeights TABLE(City nvarchar(60) primary key, Weight int not null);
INSERT @CityWeights(City,Weight) VALUES
('Kuala Lumpur',20),('Petaling Jaya',12),('Johor Bahru',10),('George Town',9),('Shah Alam',8),
('Kuching',7),('Kota Kinabalu',7),('Ipoh',6),('Melaka',5),('Seremban',4),
('Kuantan',4),('Alor Setar',3),('Miri',3),('Sandakan',1),('Sibu',1);

/* Expand stores by weight into a table variable for fast picking */
DECLARE @WeightedStores TABLE(rn int identity(1,1) primary key, StoreID int not null);
INSERT @WeightedStores(StoreID)
SELECT s.StoreID
FROM dbo.Stores s
JOIN @CityWeights w ON w.City = s.City
JOIN dbo.Numbers n ON n.n <= w.Weight;
DECLARE @WeightedStoreCount int = (SELECT COUNT(*) FROM @WeightedStores);

/* =========================================================
   Data population
   ========================================================= */

/* ---------- Products (real catalog, preserve NULL behavior) ---------- */
INSERT dbo.Products
(SKU, ProductName, Category, Subcategory, Brand, Model, LaunchDate, UnitPrice, CostPrice, WarrantyMonths, SupplierID)
SELECT TOP (@Products)
    CONCAT('SPORT', RIGHT('000000', 6 - LEN(CAST(t.n AS varchar(6)))) , t.n) AS SKU,
    pc.ProductName,
    pc.Category,
    pc.Subcategory,
    CASE WHEN t.n%20=0 THEN NULL ELSE pc.Brand END,        -- ~5% NULL Brand
    pc.Model,
    DATEADD(DAY, -(t.n%2200), CAST(GETDATE() AS date)) AS LaunchDate,
    CASE WHEN t.n%100=0 THEN NULL ELSE
         CAST(ROUND(pc.BasePrice * (0.95 + ((t.n%11)/100.0)), 2) AS decimal(10,2)) END AS UnitPrice,  -- ~1% NULL price
    CAST(ROUND((0.60 + ((t.n%21)/100.0)) * pc.BasePrice, 2) AS decimal(10,2)) AS CostPrice,          -- ~60–81% of base
    (3 + (t.n%34)) AS WarrantyMonths,                       -- 3–36
    ((t.n%@Suppliers)+1) AS SupplierID
FROM dbo.Numbers t
JOIN @ProductCatalog pc
  ON (((t.n - 1) % @CatalogCount) + 1) = pc.CatalogID
ORDER BY t.n;

/* ---------- Customers (aligned first+last names; other fields unchanged) ---------- */
INSERT dbo.Customers
(FirstName, LastName, Email, Phone, Gender, BirthDate, City, State, Country, SignupDate)
SELECT TOP (@Customers)
    np.FirstName,
    np.LastName,
    CASE WHEN t.n%20=0 THEN NULL ELSE CONCAT('cust', t.n, '@mail.com') END AS Email,
    CASE WHEN t.n%10=0 THEN NULL ELSE CONCAT('01', RIGHT('000000000',9-LEN(CAST(t.n AS varchar(9)))), t.n) END AS Phone,
    CASE WHEN t.n%2=0 THEN 'Male' ELSE 'Female' END AS Gender,
    CASE WHEN t.n%33=0 THEN NULL ELSE DATEADD(DAY, - (18*365 + (t.n%(42*365))), CAST(GETDATE() AS date)) END AS BirthDate,
    CHOOSE((t.n%12)+1,'Kuala Lumpur','Petaling Jaya','Shah Alam','Johor Bahru','George Town','Ipoh','Kuching','Kota Kinabalu','Melaka','Seremban','Kuantan','Alor Setar') AS City,
    CHOOSE((t.n%12)+1,'Federal Territory','Selangor','Selangor','Johor','Penang','Perak','Sarawak','Sabah','Melaka','Negeri Sembilan','Pahang','Kedah') AS State,
    'Malaysia' AS Country,
    DATEADD(DAY, -(t.n%2500), CAST(GETDATE() AS date)) AS SignupDate
FROM dbo.Numbers t
JOIN @NamePairs np
  ON (((t.n - 1) % @NamePairCount) + 1) = np.RowID
ORDER BY t.n;

/* ---------- Duplicate some customers ---------- */
INSERT dbo.Customers (FirstName, LastName, Email, Phone, Gender, BirthDate, City, State, Country, SignupDate)
SELECT TOP (@DuplicateCustomers)
       c.FirstName, c.LastName, c.Email, c.Phone, c.Gender, c.BirthDate, c.City, c.State, c.Country, c.SignupDate
FROM dbo.Customers c
JOIN dbo.Numbers nn ON c.CustomerID = nn.n
WHERE c.CustomerID % 17 = 0;

/* ---------- Sales (weighted Store pick; preserve NULLs & totals inline) ---------- */
DECLARE @CustCount  int = (SELECT COUNT(*) FROM dbo.Customers);
DECLARE @ProdCount  int = (SELECT COUNT(*) FROM dbo.Products);
DECLARE @StoreCount int = (SELECT COUNT(*) FROM dbo.Stores);

INSERT dbo.Sales
(OrderDate, ShipDate, CustomerID, StoreID, ProductID, Quantity, UnitPrice, Discount, TotalAmount,
 PaymentMethod, Channel, OrderStatus)
SELECT TOP (@Sales)
    DATEADD(DAY, (x.n%1370), CONVERT(date,'2022-01-01')) AS OrderDate,
    CASE WHEN x.n%10=0 THEN NULL ELSE DATEADD(DAY, (x.n%10),
         DATEADD(DAY, (x.n%1370), CONVERT(date,'2022-01-01'))) END AS ShipDate,
    /* ~0.5% NULL customer inline */
    CASE WHEN x.n%200=0 THEN NULL ELSE ((x.n%@CustCount)+1) END AS CustomerID,
    /* ~1% NULL store inline, else weighted store pick */
    CASE WHEN x.n%100=0 THEN NULL ELSE ws.StoreID END AS StoreID,
    ((x.n%@ProdCount)+1) AS ProductID,
    /* sports baskets: often >1 */
    CASE WHEN x.n%5 IN (0,1,2) THEN 1 WHEN x.n%5=3 THEN 2 ELSE 3 + (x.n%2) END AS Quantity,
    /* ~0.7% NULL price; else product price ± ~10% */
    CASE WHEN x.n%150=0 THEN NULL ELSE
      CAST(ROUND(
        (SELECT UnitPrice FROM dbo.Products WHERE ProductID = ((x.n%@ProdCount)+1)) *
        (0.95 + ((x.n%11)/100.0)), 2) AS decimal(10,2)) END AS UnitPrice,
    CAST(CASE WHEN x.n%3=0 THEN 0 ELSE ROUND(((x.n%31)/100.0),2) END AS decimal(5,2)) AS Discount,
    CAST(ROUND(
        (CASE WHEN x.n%150=0 THEN 0 ELSE
          (CASE WHEN x.n%5 IN (0,1,2) THEN 1 WHEN x.n%5=3 THEN 2 ELSE 3 + (x.n%2) END) *
          (SELECT COALESCE(UnitPrice,0) FROM dbo.Products WHERE ProductID=((x.n%@ProdCount)+1)) *
          (1 - (CASE WHEN x.n%3=0 THEN 0 ELSE ((x.n%31)/100.0) END))
        END), 2) AS decimal(12,2)) AS TotalAmount,
    CASE WHEN x.n%100=0 THEN NULL ELSE CHOOSE((x.n%5)+1,'Credit Card','Debit Card','E-Wallet','Bank Transfer','Cash') END AS PaymentMethod,
    CHOOSE((x.n%3)+1,'Online','In-Store','Marketplace') AS Channel,
    CHOOSE((x.n%10)+1,'Cancelled','Returned','Pending','Completed','Completed','Completed','Completed','Completed','Completed','Completed') AS OrderStatus
FROM dbo.Numbers x
CROSS APPLY
(
    SELECT StoreID
    FROM @WeightedStores
    WHERE rn = ((x.n % @WeightedStoreCount) + 1)
) AS ws
ORDER BY x.n;

/* ---------- Duplicate some Sales ---------- */
INSERT dbo.Sales
(OrderDate, ShipDate, CustomerID, StoreID, ProductID, Quantity, UnitPrice, Discount, TotalAmount, PaymentMethod, Channel, OrderStatus)
SELECT TOP (@DuplicateSales)
       s.OrderDate, s.ShipDate, s.CustomerID, s.StoreID, s.ProductID, s.Quantity,
       s.UnitPrice, s.Discount, s.TotalAmount, s.PaymentMethod, s.Channel, s.OrderStatus
FROM dbo.Sales s
JOIN dbo.Numbers nn ON s.SalesID = nn.n
WHERE s.SalesID % 23 = 0;

/* ---------- Row counts ---------- */
SELECT 'Customers' AS TableName, COUNT(*) AS Rows FROM dbo.Customers
UNION ALL SELECT 'Suppliers', COUNT(*) FROM dbo.Suppliers
UNION ALL SELECT 'Stores', COUNT(*)  FROM dbo.Stores
UNION ALL SELECT 'Products', COUNT(*) FROM dbo.Products
UNION ALL SELECT 'Sales', COUNT(*) FROM dbo.Sales;
