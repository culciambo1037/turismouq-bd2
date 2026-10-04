-- =====================================================================
-- 00_usuario.sql
-- Proyecto integrador TurismoUQ - Bases de Datos II (2026-2)
-- Autor: Cesar Arturo Giraldo Velez
--
-- QUE HACE: crea el usuario (esquema) TURISMO_UQ donde viviran todas las
--           tablas del proyecto, y le da los privilegios que necesitan las
--           tres entregas.
--
-- COMO SE EJECUTA:
--   1. Conectarse como SYSTEM a la base de datos conectable (PDB):
--        Oracle XE 21c  -> servicio XEPDB1
--        Oracle 23ai/26ai Free -> servicio FREEPDB1
--   2. Ejecutar este script UNA sola vez (F5 en SQL Developer).
--   3. Crear una conexion nueva en SQL Developer con el usuario TURISMO_UQ
--      y ejecutar alli los scripts 01, 02 y 03, en ese orden.
-- =====================================================================

-- 1. Crear el usuario. Cambie la contrasena si lo desea.
CREATE USER turismo_uq IDENTIFIED BY "TurismoUQ2026"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

-- 2. Privilegios para la Entrega 1 (tablas y consultas)
GRANT CREATE SESSION   TO turismo_uq;
GRANT CREATE TABLE     TO turismo_uq;
GRANT CREATE VIEW      TO turismo_uq;
GRANT CREATE SEQUENCE  TO turismo_uq;

-- 3. Privilegios que se usaran en las Entregas 2 y 3
GRANT CREATE PROCEDURE         TO turismo_uq;  -- funciones, procedimientos, paquetes
GRANT CREATE TRIGGER           TO turismo_uq;  -- disparadores
GRANT CREATE MATERIALIZED VIEW TO turismo_uq;  -- vista materializada de ocupacion
GRANT CREATE TYPE              TO turismo_uq;
