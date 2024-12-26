SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Core Tables
CREATE TABLE departments (
    dept_id INTEGER PRIMARY KEY,
    dept_name VARCHAR(50),
    location VARCHAR(50),
    budget DECIMAL(15,2),
    created_at DATETIME DEFAULT GETDATE(),
    last_modified DATETIME
);

CREATE TABLE employees (
    emp_id INTEGER PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    dept_id INTEGER,
    hire_date DATE,
    salary DECIMAL(10,2),
    manager_id INTEGER,
    email VARCHAR(100),
    phone VARCHAR(20),
    status VARCHAR(20) DEFAULT 'ACTIVE',
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id),
    FOREIGN KEY (manager_id) REFERENCES employees(emp_id)
);

CREATE TABLE performance_reviews (
    review_id INTEGER PRIMARY KEY,
    emp_id INTEGER,
    review_date DATE,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    comments TEXT,
    reviewer_id INTEGER,
    FOREIGN KEY (emp_id) REFERENCES employees(emp_id),
    FOREIGN KEY (reviewer_id) REFERENCES employees(emp_id)
);

CREATE TABLE salary_history (
    history_id INTEGER IDENTITY(1,1) PRIMARY KEY,
    emp_id INTEGER,
    old_salary DECIMAL(10,2),
    new_salary DECIMAL(10,2),
    change_date DATETIME,
    reason VARCHAR(100),
    FOREIGN KEY (emp_id) REFERENCES employees(emp_id)
);

-- Triggers
CREATE TRIGGER trg_salary_history
ON employees
AFTER UPDATE
AS
BEGIN
    IF UPDATE(salary)
    BEGIN
        INSERT INTO salary_history (emp_id, old_salary, new_salary, change_date, reason)
        SELECT 
            i.emp_id,
            d.salary,
            i.salary,
            GETDATE(),
            'Salary Update'
        FROM inserted i
        JOIN deleted d ON i.emp_id = d.emp_id
    END
END;

-- Stored Procedures
CREATE PROCEDURE sp_give_raise
    @emp_id INT,
    @percentage DECIMAL(5,2),
    @reason VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @old_salary DECIMAL(10,2);
    DECLARE @new_salary DECIMAL(10,2);
    
    SELECT @old_salary = salary
    FROM employees
    WHERE emp_id = @emp_id;
    
    SET @new_salary = @old_salary * (1 + @percentage/100);
    
    UPDATE employees
    SET salary = @new_salary
    WHERE emp_id = @emp_id;
    
    INSERT INTO salary_history (emp_id, old_salary, new_salary, change_date, reason)
    VALUES (@emp_id, @old_salary, @new_salary, GETDATE(), @reason);
END;

-- Views
CREATE VIEW vw_department_stats AS
WITH dept_hierarchy AS (
    SELECT 
        e.dept_id,
        e.emp_id,
        e.salary,
        CASE 
            WHEN e.manager_id IS NULL THEN 0
            ELSE 1
        END as is_subordinate
    FROM employees e
)
SELECT 
    d.dept_id,
    d.dept_name,
    d.location,
    COUNT(dh.emp_id) as employee_count,
    SUM(dh.salary) as total_salary_cost,
    AVG(dh.salary) as avg_salary,
    SUM(CASE WHEN dh.is_subordinate = 0 THEN 1 ELSE 0 END) as manager_count,
    d.budget,
    d.budget - SUM(dh.salary) as budget_remaining
FROM departments d
LEFT JOIN dept_hierarchy dh ON d.dept_id = dh.dept_id
GROUP BY d.dept_id, d.dept_name, d.location, d.budget;

-- Functions
CREATE FUNCTION fn_get_employee_performance(
    @emp_id INT,
    @start_date DATE,
    @end_date DATE
)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        e.first_name + ' ' + e.last_name as employee_name,
        COUNT(pr.review_id) as review_count,
        AVG(CAST(pr.rating as DECIMAL(3,2))) as avg_rating,
        STRING_AGG(pr.comments, ' | ') as all_comments
    FROM employees e
    LEFT JOIN performance_reviews pr ON e.emp_id = pr.emp_id
    WHERE e.emp_id = @emp_id
    AND pr.review_date BETWEEN @start_date AND @end_date
    GROUP BY e.first_name, e.last_name
);

-- Sample Data
INSERT INTO departments VALUES
(1, 'Administrator', 'Jeppestown', 1000000, GETDATE(), GETDATE()),
(2, 'Marketing', 'Newtown', 800000, GETDATE(), GETDATE()),
(3, 'Sales', 'Braamfontein', 900000, GETDATE(), GETDATE()),
(4, 'Operator', 'East gate', 600000, GETDATE(), GETDATE()),
(5, 'DevOps', 'Droonfontein', 1200000, GETDATE(), GETDATE()),
(6, 'Designer', 'Hillbrow', 700000, GETDATE(), GETDATE());

INSERT INTO employees VALUES
(1, 'Thabo', 'Nkosi', 1, '2020-01-15', 85000, NULL, 'thabo.nkosi@company.co.za', '+27821234567', 'ACTIVE'),
(2, 'Nomvula', 'Dlamini', 2, '2020-03-20', 75000, 1, 'nomvula.dlamini@company.co.za', '+27829876543', 'ACTIVE'),
(3, 'Sipho', 'Mabaso', 3, '2021-02-10', 65000, 1, 'sipho.mabaso@company.co.za', '+27823456789', 'ACTIVE'),
(4, 'Lesego', 'Mokoena', 4, '2021-06-01', 70000, 1, 'lesego.mokoena@company.co.za', '+27827654321', 'ACTIVE'),
(5, 'Tumelo', 'Khumalo', 5, '2021-08-15', 90000, 1, 'tumelo.khumalo@company.co.za', '+27825678901', 'ACTIVE'),
(6, 'Lindiwe', 'Zulu', 6, '2022-01-10', 68000, 1, 'lindiwe.zulu@company.co.za', '+27828901234', 'ACTIVE');

-- Advanced Queries

-- 1. Hierarchical Employee Structure with CTEs
WITH RECURSIVE emp_hierarchy AS (
    SELECT 
        emp_id,
        first_name,
        last_name,
        manager_id,
        1 as level,
        CAST(first_name + ' ' + last_name as VARCHAR(1000)) as hierarchy_path
    FROM employees
    WHERE manager_id IS NULL
    
    UNION ALL
    
    SELECT 
        e.emp_id,
        e.first_name,
        e.last_name,
        e.manager_id,
        eh.level + 1,
        CAST(eh.hierarchy_path + ' > ' + e.first_name + ' ' + e.last_name as VARCHAR(1000))
    FROM employees e
    JOIN emp_hierarchy eh ON e.manager_id = eh.emp_id
)
SELECT 
    level,
    hierarchy_path
FROM emp_hierarchy
ORDER BY level, hierarchy_path;

-- 2. Department Performance Analysis with Window Functions
SELECT 
    d.dept_name,
    e.first_name + ' ' + e.last_name as employee,
    pr.rating,
    AVG(pr.rating) OVER (PARTITION BY d.dept_id) as dept_avg_rating,
    pr.rating - AVG(pr.rating) OVER (PARTITION BY d.dept_id) as rating_vs_dept_avg,
    RANK() OVER (PARTITION BY d.dept_id ORDER BY pr.rating DESC) as dept_rank
FROM departments d
JOIN employees e ON d.dept_id = e.dept_id
JOIN performance_reviews pr ON e.emp_id = pr.emp_id;

-- 3. Salary Percentiles using NTILE
SELECT 
    e.first_name + ' ' + e.last_name as employee,
    d.dept_name,
    e.salary,
    NTILE(4) OVER (ORDER BY e.salary) as salary_quartile,
    PERCENT_RANK() OVER (ORDER BY e.salary) as salary_percentile
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id;
