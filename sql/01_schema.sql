-- ============================================================
-- ERP-система меблевого виробництва «DOMINANTA»
-- Файл: 01_schema.sql (створення БД, таблиць, обмежень та індексів)
-- СУБД: MySQL 8.0 / 8.4 LTS
-- ============================================================

DROP DATABASE IF EXISTS dominanta_erp;
CREATE DATABASE dominanta_erp
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE dominanta_erp;

-- ============================================================
-- ФАЗА 1: Довідники та незалежні сутності
-- ============================================================

-- 1. Довідник ролей доступу до ERP
CREATE TABLE roles (
  role_id   INT AUTO_INCREMENT PRIMARY KEY,
  role_name VARCHAR(50) NOT NULL UNIQUE
) ENGINE = InnoDB;

-- 2. Клієнти (фізичні та юридичні особи)
CREATE TABLE clients (
  client_id   INT AUTO_INCREMENT PRIMARY KEY,
  client_type ENUM('Фізична особа', 'Юридична особа') NOT NULL DEFAULT 'Фізична особа',
  name        VARCHAR(150) NOT NULL,
  phone       VARCHAR(20)  NOT NULL UNIQUE,
  email       VARCHAR(100) NULL,
  address     VARCHAR(255) NOT NULL,
  note        TEXT         NULL
) ENGINE = InnoDB;

-- 3. Постачальники сировини
CREATE TABLE suppliers (
  supplier_id    INT AUTO_INCREMENT PRIMARY KEY,
  name           VARCHAR(150) NOT NULL UNIQUE,
  edrpou         CHAR(8)      NOT NULL UNIQUE,
  contact_person VARCHAR(120) NOT NULL,
  phone          VARCHAR(20)  NOT NULL,
  address        VARCHAR(255) NOT NULL,
  CONSTRAINT chk_suppliers_edrpou CHECK (edrpou REGEXP '^[0-9]{8}$')
) ENGINE = InnoDB;

-- 4. Склад готової продукції (каталог меблів)
CREATE TABLE products (
  product_id         INT AUTO_INCREMENT PRIMARY KEY,
  sku                VARCHAR(20)    NOT NULL UNIQUE,
  name               VARCHAR(150)   NOT NULL,
  stock_qty          INT            NOT NULL DEFAULT 0,
  price              DECIMAL(10, 2) NOT NULL,
  package_dimensions VARCHAR(50)    NOT NULL,
  sleeping_area      VARCHAR(50)    NULL,
  available_colors   VARCHAR(100)   NOT NULL,
  has_drawer         TINYINT(1)     NOT NULL DEFAULT 0,
  CONSTRAINT chk_products_stock CHECK (stock_qty >= 0),
  CONSTRAINT chk_products_price CHECK (price > 0)
) ENGINE = InnoDB;

-- 5. Довідник сировини та залишків
CREATE TABLE materials (
  material_id   INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(150)   NOT NULL UNIQUE,
  unit          ENUM('м²', 'шт.', 'пог. м.', 'л.', 'кг') NOT NULL,
  stock_qty     DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  unit_price    DECIMAL(10, 2) NOT NULL,
  min_stock_qty DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  CONSTRAINT chk_materials_stock     CHECK (stock_qty >= 0),
  CONSTRAINT chk_materials_price     CHECK (unit_price > 0),
  CONSTRAINT chk_materials_min_stock CHECK (min_stock_qty >= 0)
) ENGINE = InnoDB;

-- ============================================================
-- ФАЗА 2: Персонал та технологічна карта (M:N)
-- ============================================================

-- 6. Персонал підприємства та облікові записи ERP
CREATE TABLE employees (
  employee_id     INT AUTO_INCREMENT PRIMARY KEY,
  full_name       VARCHAR(150)   NOT NULL,
  position        VARCHAR(100)   NOT NULL,
  salary          DECIMAL(10, 2) NOT NULL,
  phone           VARCHAR(20)    NOT NULL UNIQUE,
  email           VARCHAR(100)   NOT NULL UNIQUE,
  hire_date       DATE           NOT NULL,
  employment_type ENUM('Повна', 'Часткова', 'Контракт') NOT NULL DEFAULT 'Повна',
  login           VARCHAR(50)    NULL UNIQUE,
  password_hash   VARCHAR(255)   NULL,
  role_id         INT            NOT NULL,
  is_active       TINYINT(1)     NOT NULL DEFAULT 1,
  CONSTRAINT chk_employees_salary CHECK (salary > 0),
  CONSTRAINT fk_employees_role
    FOREIGN KEY (role_id) REFERENCES roles (role_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- 7. Технологічна карта виробу (M:N між products і materials)
CREATE TABLE product_materials (
  product_id   INT            NOT NULL,
  material_id  INT            NOT NULL,
  qty_required DECIMAL(10, 2) NOT NULL,
  PRIMARY KEY (product_id, material_id),
  CONSTRAINT chk_pm_qty CHECK (qty_required > 0),
  CONSTRAINT fk_pm_product
    FOREIGN KEY (product_id) REFERENCES products (product_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_pm_material
    FOREIGN KEY (material_id) REFERENCES materials (material_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ============================================================
-- ФАЗА 3: Замовлення, складські документи та фінанси
-- ============================================================

-- 8. Шапка клієнтських замовлень
CREATE TABLE orders (
  order_id       INT AUTO_INCREMENT PRIMARY KEY,
  client_id      INT            NOT NULL,
  employee_id    INT            NOT NULL,
  order_date     DATE           NOT NULL DEFAULT (CURRENT_DATE),
  deadline       DATE           NOT NULL,
  status         ENUM(
                   'Нове',
                   'В роботі',
                   'Готово до відправки',
                   'Виконане',
                   'Протерміноване',
                   'Скасоване'
                 ) NOT NULL DEFAULT 'Нове',
  payment_status ENUM('Не оплачено', 'Передоплата', 'Оплачено') NOT NULL DEFAULT 'Не оплачено',
  total_amount   DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  CONSTRAINT chk_orders_dates  CHECK (deadline >= order_date),
  CONSTRAINT chk_orders_amount CHECK (total_amount >= 0),
  CONSTRAINT fk_orders_client
    FOREIGN KEY (client_id) REFERENCES clients (client_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_orders_employee
    FOREIGN KEY (employee_id) REFERENCES employees (employee_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- 9. Позиції замовлення (M:N між orders і products)
CREATE TABLE order_items (
  order_item_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id      INT            NOT NULL,
  product_id    INT            NOT NULL,
  quantity      INT            NOT NULL,
  unit_price    DECIMAL(10, 2) NOT NULL,
  UNIQUE KEY uq_order_product (order_id, product_id),
  CONSTRAINT chk_oi_qty   CHECK (quantity > 0),
  CONSTRAINT chk_oi_price CHECK (unit_price > 0),
  CONSTRAINT fk_oi_order
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_oi_product
    FOREIGN KEY (product_id) REFERENCES products (product_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- 10. Прихідні накладні на сировину («Отримане»)
CREATE TABLE material_receipts (
  receipt_id     INT AUTO_INCREMENT PRIMARY KEY,
  receipt_number VARCHAR(20)    NOT NULL UNIQUE,
  supplier_id    INT            NOT NULL,
  receipt_date   DATE           NOT NULL DEFAULT (CURRENT_DATE),
  total_amount   DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  CONSTRAINT chk_receipts_amount CHECK (total_amount >= 0),
  CONSTRAINT fk_receipts_supplier
    FOREIGN KEY (supplier_id) REFERENCES suppliers (supplier_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- 11. Позиції прихідної накладної (M:N між material_receipts і materials)
CREATE TABLE material_receipt_items (
  receipt_item_id INT AUTO_INCREMENT PRIMARY KEY,
  receipt_id      INT            NOT NULL,
  material_id     INT            NOT NULL,
  quantity        DECIMAL(10, 2) NOT NULL,
  unit_price      DECIMAL(10, 2) NOT NULL,
  UNIQUE KEY uq_receipt_material (receipt_id, material_id),
  CONSTRAINT chk_mri_qty   CHECK (quantity > 0),
  CONSTRAINT chk_mri_price CHECK (unit_price > 0),
  CONSTRAINT fk_mri_receipt
    FOREIGN KEY (receipt_id) REFERENCES material_receipts (receipt_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_mri_material
    FOREIGN KEY (material_id) REFERENCES materials (material_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- 12. Видача сировини у виробництво («Видане»)
CREATE TABLE material_issues (
  issue_id    INT AUTO_INCREMENT PRIMARY KEY,
  issue_date  DATE           NOT NULL DEFAULT (CURRENT_DATE),
  material_id INT            NOT NULL,
  quantity    DECIMAL(10, 2) NOT NULL,
  employee_id INT            NOT NULL,
  order_id    INT            NULL,
  CONSTRAINT chk_issues_qty CHECK (quantity > 0),
  CONSTRAINT fk_issues_material
    FOREIGN KEY (material_id) REFERENCES materials (material_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_issues_employee
    FOREIGN KEY (employee_id) REFERENCES employees (employee_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_issues_order
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE = InnoDB;

-- 13. Фінансові операції («Фінанси»)
CREATE TABLE finance_transactions (
  transaction_id INT AUTO_INCREMENT PRIMARY KEY,
  tx_date        DATE           NOT NULL DEFAULT (CURRENT_DATE),
  tx_type        ENUM('Дохід', 'Витрата') NOT NULL,
  category       ENUM(
                   'Оплата замовлення',
                   'Закупівля сировини',
                   'Зарплата персоналу',
                   'Інше'
                 ) NOT NULL,
  amount         DECIMAL(12, 2) NOT NULL,
  order_id       INT            NULL,
  receipt_id     INT            NULL,
  employee_id    INT            NULL,
  CONSTRAINT chk_ft_amount CHECK (amount > 0),
  CONSTRAINT chk_ft_single_doc CHECK (
    (order_id IS NOT NULL) + (receipt_id IS NOT NULL) + (employee_id IS NOT NULL) <= 1
  ),
  CONSTRAINT fk_ft_order
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_ft_receipt
    FOREIGN KEY (receipt_id) REFERENCES material_receipts (receipt_id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_ft_employee
    FOREIGN KEY (employee_id) REFERENCES employees (employee_id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- ============================================================
-- ІНДЕКСИ (для фільтрації, сортування та звітів за період)
-- ============================================================

CREATE INDEX idx_orders_status_deadline ON orders (status, deadline);
CREATE INDEX idx_finance_date_type      ON finance_transactions (tx_date, tx_type);
CREATE INDEX idx_issues_date            ON material_issues (issue_date);
CREATE INDEX idx_receipts_date          ON material_receipts (receipt_date);