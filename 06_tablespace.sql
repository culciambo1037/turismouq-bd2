-- =====================================================================
-- 06_tablespace.sql
-- Proyecto integrador TurismoUQ - Bases de Datos II (2026-2) - ENTREGA 2
-- Autor: Cesar Arturo Giraldo Velez
--
-- QUE HACE: crea el tablespace propio TS_HISTORICO, donde vivira el
--           historico de reservas (la tabla se crea en el script 07).
--
-- COMO SE EJECUTA: conectado como SYSTEM a la PDB (FREEPDB1 o XEPDB1),
--   con F5. Crear tablespaces es una tarea de administrador: el usuario
--   TURISMO_UQ no tiene ese privilegio, y esta bien que no lo tenga.
--   Se puede correr varias veces: si el tablespace ya existe, NO lo borra
--   (podria tener datos de otras tablas o del historico); solo ajusta el
--   crecimiento de sus datafiles a lo definido aqui.
--
-- POR QUE SEPARAR EL HISTORICO EN SU PROPIO TABLESPACE
--   Un tablespace es un contenedor logico; sus datos viven en uno o mas
--   archivos fisicos (datafiles). Separar el historico permite:
--   1. Controlar el crecimiento: el historico solo crece (cada anio que
--      se cierra se agrega) y nunca se modifica. En su propio tablespace
--      no compite por espacio con las tablas de operacion diaria (USERS).
--   2. Respaldar mejor: cuando un anio queda cerrado, el tablespace se
--      puede poner en solo lectura (ALTER TABLESPACE ... READ ONLY) y
--      respaldarse una sola vez. Los respaldos diarios solo copian USERS,
--      que es mas pequeno y cambia todos los dias.
--   3. Ubicarlo en otro disco: su datafile puede ir en almacenamiento mas
--      barato o mas lento, porque se consulta poco. Ademas, las lecturas
--      de reportes historicos no compiten por disco con las reservas
--      que se crean en linea.
--   4. Administrarlo aparte: se puede mover, ampliar, desconectar o
--      borrar el historico sin tocar las tablas operativas.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED


-- =====================================================================
-- 1. CREAR EL TABLESPACE
--    Para no escribir a mano la ruta del datafile (cambia segun el equipo
--    y la version de Oracle), el bloque busca la carpeta donde esta el
--    datafile del tablespace USERS y crea ahi el nuevo archivo.
--    * SIZE 50M               : tamano inicial.
--    * AUTOEXTEND ON NEXT 25M : crece de 25 MB en 25 MB cuando se llena...
--    * MAXSIZE 1G             : ...hasta un tope de 1 GB, para que nunca
--                               llene el disco por accidente.
--    * REUSE                  : si quedo un archivo viejo con ese nombre,
--                               lo reutiliza en vez de fallar.
--    * EXTENT MANAGEMENT LOCAL y SEGMENT SPACE MANAGEMENT AUTO: el espacio
--      lo administra el propio tablespace, que es lo recomendado.
-- =====================================================================
DECLARE
  v_existe   PLS_INTEGER;
  v_archivo  VARCHAR2(600);
  v_carpeta  VARCHAR2(600);
  v_sep      VARCHAR2(1);
BEGIN
  SELECT COUNT(*) INTO v_existe
    FROM dba_tablespaces
   WHERE tablespace_name = 'TS_HISTORICO';

  IF v_existe > 0 THEN
    -- Ya existe: se conserva. Borrarlo seria peligroso (ORA-14404 si tiene
    -- particiones de otras tablas, y perdida del historico si ya se cargo).
    -- Solo se igualan las reglas de crecimiento de sus datafiles.
    FOR f IN (SELECT file_name
                FROM dba_data_files
               WHERE tablespace_name = 'TS_HISTORICO') LOOP
      EXECUTE IMMEDIATE 'ALTER DATABASE DATAFILE ''' || f.file_name ||
                        ''' AUTOEXTEND ON NEXT 25M MAXSIZE 1G';
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Tablespace TS_HISTORICO ya existia: se conserva y se ajusta su crecimiento (25M hasta 1G).');
  ELSE
    -- Carpeta del datafile de USERS (separador "\" en Windows, "/" en Linux)
    SELECT file_name INTO v_archivo
      FROM dba_data_files
     WHERE tablespace_name = 'USERS'
       AND ROWNUM = 1;

    v_sep     := CASE WHEN INSTR(v_archivo, '\') > 0 THEN '\' ELSE '/' END;
    v_carpeta := SUBSTR(v_archivo, 1, INSTR(v_archivo, v_sep, -1));

    EXECUTE IMMEDIATE
      'CREATE TABLESPACE ts_historico ' ||
      'DATAFILE ''' || v_carpeta || 'ts_historico01.dbf'' SIZE 50M REUSE ' ||
      'AUTOEXTEND ON NEXT 25M MAXSIZE 1G ' ||
      'EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO';

    DBMS_OUTPUT.PUT_LINE('Tablespace TS_HISTORICO creado en ' || v_carpeta || 'ts_historico01.dbf');
  END IF;
END;
/


-- =====================================================================
-- 2. PERMISOS PARA TURISMO_UQ
--    * QUOTA: sin cuota, TURISMO_UQ no podria guardar datos en el nuevo
--      tablespace aunque exista.
--    * CREATE JOB: para programar el refresco nocturno de la vista
--      materializada (script 07).
-- =====================================================================
ALTER USER turismo_uq QUOTA UNLIMITED ON ts_historico;
GRANT CREATE JOB TO turismo_uq;


-- =====================================================================
-- 3. VERIFICACION
-- =====================================================================
SELECT tablespace_name, status, extent_management, segment_space_management
  FROM dba_tablespaces
 WHERE tablespace_name IN ('USERS', 'TS_HISTORICO')
 ORDER BY tablespace_name;

SELECT tablespace_name, file_name,
       ROUND(bytes / 1024 / 1024)    AS mb_actual,
       autoextensible,
       ROUND(maxbytes / 1024 / 1024) AS mb_maximo
  FROM dba_data_files
 WHERE tablespace_name IN ('USERS', 'TS_HISTORICO')
 ORDER BY tablespace_name;

SELECT username, tablespace_name,
       CASE max_bytes WHEN -1 THEN 'ILIMITADA' ELSE TO_CHAR(max_bytes) END AS cuota
  FROM dba_ts_quotas
 WHERE username = 'TURISMO_UQ';

-- Que hay hoy dentro de TS_HISTORICO (en una base nueva sale vacio;
-- despues del script 07 debe aparecer TURISMO_UQ.RESERVA_HISTORICO)
SELECT owner, segment_name, partition_name, segment_type,
       ROUND(bytes / 1024 / 1024, 2) AS mb
  FROM dba_segments
 WHERE tablespace_name = 'TS_HISTORICO'
 ORDER BY owner, segment_name, partition_name;
