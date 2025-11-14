#!/bin/bash
psql -d ecommerce <<'EOF'
CREATE TABLE "User" (
    idUser SERIAL PRIMARY KEY,
    name VARCHAR(100),
    lastName VARCHAR(100)
);

CREATE TABLE "Item" (
    idItem SERIAL PRIMARY KEY,
    itemName VARCHAR(100)
);

CREATE TABLE "Order" (
    idOrder SERIAL PRIMARY KEY,
    deliveryAddress VARCHAR(200),
    price NUMERIC
);

CREATE TABLE "UserOrders" (
    idUser INT REFERENCES "User"(idUser),
    idOrder INT REFERENCES "Order"(idOrder),
    PRIMARY KEY (idUser, idOrder)
);

CREATE TABLE "OrderItems" (
    idOrder INT REFERENCES "Order"(idOrder),
    idItem INT REFERENCES "Item"(idItem),
    quantity INT,
    PRIMARY KEY (idOrder, idItem)
);

-- sample data
INSERT INTO "User" (name, lastName) VALUES
('Alice', 'Smith'),
('Bob', 'Jones');

INSERT INTO "Item" (itemName) VALUES
('Laptop'),
('Mouse'),
('Keyboard');

INSERT INTO "Order" (deliveryAddress, price) VALUES
('123 Elm Street', 1200.50),
('456 Oak Avenue', 80.00);

INSERT INTO "UserOrders" VALUES (1, 1), (2, 2);
INSERT INTO "OrderItems" VALUES (1, 1, 1), (1, 2, 2), (2, 3, 1);
EOF