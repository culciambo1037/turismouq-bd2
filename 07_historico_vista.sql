-- =====================================================================
-- 07_historico_vista.sql
-- Proyecto integrador TurismoUQ - Bases de Datos II (2026-2) - ENTREGA 2
-- Autor: Cesar Arturo Giraldo Velez
--
-- QUE HACE:
--   Parte A. Crea la tabla RESERVA_HISTORICO DENTRO del tablespace
--            TS_HISTORICO y archiva en ella las reservas cerradas de los
--            anios anteriores al actual (2024 y 2025).
--   Parte B. Crea la vista materializada MV_OCUPACION_MENSUAL (ocupacion
--            por alojamiento y mes) y programa su refresco nocturno.
--
-- COMO SE EJECUTA: conectado como TURISMO_UQ, despues de 06 (F5).
--   Se puede correr varias veces: borra y recrea lo que exista.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

-- Control de conexion: si no se esta conectado como TURISMO_UQ, el script
-- se detiene aqui (evita crear objetos en el esquema equivocado).
WHENEVER SQLERROR EXIT
BEGIN
  IF USER <> 'TURISMO_UQ' THEN
    RAISE_APPLICATION_ERROR(-20099,
      'Conexion equivocada: este script se corre como TURISMO_UQ y estas conectado como ' || USER || '.');
  END IF;
END;
/
WHENEVER SQLERROR CONTINUE


-- #####################################################################
-- PARTE A. HISTORICO DE RESERVAS EN SU PROPIO TABLESPACE
-- #####################################################################

-- A.0 Limpieza
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name = 'RESERVA_HISTORICO') LOOP
    EXECUTE IMMEDIATE 'DROP TABLE reserva_historico PURGE';
  END LOOP;
END;
/

-- =====================================================================
-- A.1 TABLA RESERVA_HISTORICO
--   Es una "foto de cierre" de cada reserva terminada: ya trae resueltos
--   el alojamiento, el municipio, el cliente y los totales. Asi los
--   reportes historicos no necesitan unir 6 tablas, y la foto no cambia
--   aunque despues cambien las tarifas o los datos del cliente.
--   La clausula TABLESPACE ts_historico es la que la ubica en el
--   tablespace propio (las demas tablas estan en USERS).
--   En una operacion real, despues de archivar un anio se podrian depurar
--   esas reservas de las tablas operativas. Aqui NO se borran, para que
--   las consultas de la Entrega 1 sigan dando los mismos resultados.
-- =====================================================================
CREATE TABLE reserva_historico (
  id_reserva          NUMBER(8)      CONSTRAINT nn_hist_reserva  NOT NULL,
  anio_cierre         NUMBER(4)      CONSTRAINT nn_hist_anio     NOT NULL,
  estado              VARCHAR2(12)   CONSTRAINT nn_hist_estado   NOT NULL,
  fecha_reserva       DATE           CONSTRAINT nn_hist_freserva NOT NULL,
  fecha_checkin       DATE           CONSTRAINT nn_hist_checkin  NOT NULL,
  fecha_checkout      DATE           CONSTRAINT nn_hist_checkout NOT NULL,
  fecha_cancelacion   DATE,
  id_alojamiento      NUMBER(5)      CONSTRAINT nn_hist_aloj     NOT NULL,
  alojamiento         VARCHAR2(100)  CONSTRAINT nn_hist_alojnom  NOT NULL,
  tipo_alojamiento    VARCHAR2(40)   CONSTRAINT nn_hist_tipo     NOT NULL,
  municipio           VARCHAR2(60)   CONSTRAINT nn_hist_mun      NOT NULL,
  id_cliente          NUMBER(6)      CONSTRAINT nn_hist_cliente  NOT NULL,
  cliente             VARCHAR2(170)  CONSTRAINT nn_hist_clinom   NOT NULL,
  num_habitaciones    NUMBER(3)      CONSTRAINT nn_hist_numhab   NOT NULL,
  noches_habitacion   NUMBER(5)      CONSTRAINT nn_hist_noches   NOT NULL,
  valor_estadias      NUMBER(14,2)   CONSTRAINT nn_hist_vest     NOT NULL,
  valor_servicios     NUMBER(14,2)   CONSTRAINT nn_hist_vserv    NOT NULL,
  total_pagado        NUMBER(14,2)   CONSTRAINT nn_hist_pagado   NOT NULL,
  total_reembolsado   NUMBER(14,2)   CONSTRAINT nn_hist_reemb    NOT NULL,
  fecha_archivo       DATE           DEFAULT SYSDATE
                                     CONSTRAINT nn_hist_farchivo NOT NULL,
  CONSTRAINT pk_reserva_historico PRIMARY KEY (id_reserva),
  CONSTRAINT ck_hist_estado       CHECK (estado IN ('COMPLETADA', 'CANCELADA'))
)
TABLESPACE ts_historico;

COMMENT ON TABLE reserva_historico IS
  'Historico de reservas cerradas (completadas o canceladas) de anios ya terminados. Vive en el tablespace TS_HISTORICO.';

-- =====================================================================
-- A.2 ARCHIVO DE LOS ANIOS CERRADOS (2024 y 2025)
--   Solo entran reservas COMPLETADAS o CANCELADAS cuyo check-out es
--   anterior al 01-ene-2026: esas ya no van a cambiar.
-- =====================================================================
INSERT INTO reserva_historico (
       id_reserva, anio_cierre, estado, fecha_reserva, fecha_checkin, fecha_checkout,
       fecha_cancelacion, id_alojamiento, alojamiento, tipo_alojamiento, municipio,
       id_cliente, cliente, num_habitaciones, noches_habitacion, valor_estadias,
       valor_servicios, total_pagado, total_reembolsado)
SELECT r.id_reserva,
       EXTRACT(YEAR FROM r.fecha_checkout),
       r.estado, r.fecha_reserva, r.fecha_checkin, r.fecha_checkout, r.fecha_cancelacion,
       a.id_alojamiento, a.nombre_comercial, ta.nombre, m.nombre,
       c.id_cliente, c.nombres || ' ' || c.apellidos,
       (SELECT COUNT(*) FROM reserva_habitacion rh WHERE rh.id_reserva = r.id_reserva),
       (SELECT NVL(SUM(rh.fecha_checkout - rh.fecha_checkin), 0)
          FROM reserva_habitacion rh WHERE rh.id_reserva = r.id_reserva),
       (SELECT NVL(SUM(rh.valor_estadia), 0)
          FROM reserva_habitacion rh WHERE rh.id_reserva = r.id_reserva),
       (SELECT NVL(SUM(rs.cantidad * rs.precio_unitario), 0)
          FROM reserva_servicio rs WHERE rs.id_reserva = r.id_reserva),
       (SELECT NVL(SUM(p.monto), 0)
          FROM pago p WHERE p.id_reserva = r.id_reserva AND p.estado = 'EXITOSO'),
       (SELECT NVL(SUM(p.monto), 0)
          FROM pago p WHERE p.id_reserva = r.id_reserva AND p.estado = 'REEMBOLSADO')
  FROM reserva r
  JOIN alojamiento a       ON a.id_alojamiento = r.id_alojamiento
  JOIN tipo_alojamiento ta ON ta.id_tipo       = a.id_tipo
  JOIN municipio m         ON m.id_municipio   = a.id_municipio
  JOIN cliente c           ON c.id_cliente     = r.id_cliente
 WHERE r.estado IN ('COMPLETADA', 'CANCELADA')
   AND r.fecha_checkout < DATE '2026-01-01';
COMMIT;

-- A.3 Verificacion: la tabla esta en TS_HISTORICO y las demas en USERS
SELECT table_name, tablespace_name
  FROM user_tables
 WHERE table_name IN ('RESERVA', 'RESERVA_HISTORICO')
 ORDER BY table_name;

SELECT anio_cierre, estado, COUNT(*) AS reservas
  FROM reserva_historico
 GROUP BY anio_cierre, estado
 ORDER BY anio_cierre, estado;


-- #####################################################################
-- PARTE B. VISTA MATERIALIZADA DE OCUPACION MENSUAL
-- #####################################################################

-- B.0 Limpieza: tarea programada y vista materializada anteriores
BEGIN
  FOR j IN (SELECT job_name FROM user_scheduler_jobs WHERE job_name = 'JOB_REFRESCO_OCUPACION') LOOP
    DBMS_SCHEDULER.DROP_JOB(job_name => j.job_name, force => TRUE);
  END LOOP;
  FOR v IN (SELECT mview_name FROM user_mviews WHERE mview_name = 'MV_OCUPACION_MENSUAL') LOOP
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_ocupacion_mensual';
  END LOOP;
END;
/

-- =====================================================================
-- B.1 VISTA MATERIALIZADA MV_OCUPACION_MENSUAL
--   Que es: una consulta cuyo RESULTADO queda guardado como si fuera una
--   tabla. Leerla es inmediato; el calculo pesado (cruzar ~31.500 lineas
--   de reserva con el calendario, noche por noche) se hace solo cuando
--   se refresca, no cada vez que alguien la consulta.
--
--   Contenido: una fila por alojamiento y mes (60 x 36 = 2.160 filas):
--     noches disponibles = habitaciones del alojamiento x dias del mes
--     noches ocupadas    = noches de reservas CONFIRMADAS o COMPLETADAS
--     % de ocupacion     = ocupadas / disponibles x 100
--   Al ser por alojamiento, de ella se obtiene tambien la ocupacion por
--   municipio o por tipo (sumando noches, no promediando porcentajes).
--
--   POLITICA DE REFRESCO: COMPLETE + ON DEMAND, programado cada noche a
--   las 2:00 a.m. (seccion B.2). Por que:
--   1. El refresco rapido (FAST) no es posible: la consulta cruza las
--      reservas con el calendario por RANGO de fechas (no por igualdad),
--      usa uniones externas y subconsultas agrupadas. Oracle no puede
--      actualizar ese resultado "por diferencias".
--   2. ON COMMIT tampoco: ademas de no ser permitido para esta consulta,
--      recalcularia la ocupacion de todo el departamento cada vez que
--      alguien confirma una reserva, haciendo lenta la operacion diaria.
--   3. La ocupacion mensual es un reporte de gerencia: un dia de retraso
--      es aceptable. Recalcular 2.160 filas tarda segundos, y a las 2 a.m.
--      casi nadie esta reservando.
--   4. ON DEMAND permite ademas refrescarla a mano cuando se necesite,
--      por ejemplo al cierre de mes:
--        EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
--      Con el refresco atomico (el predeterminado), mientras se refresca
--      los usuarios siguen viendo los datos anteriores; nunca ven la vista
--      vacia.
-- =====================================================================
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
  BUILD IMMEDIATE
  REFRESH COMPLETE ON DEMAND
AS
SELECT d.anio,
       d.mes,
       a.id_alojamiento,
       a.nombre_comercial                              AS alojamiento,
       m.nombre                                        AS municipio,
       ta.nombre                                       AS tipo_alojamiento,
       h.num_habitaciones,
       d.dias                                          AS dias_mes,
       h.num_habitaciones * d.dias                     AS noches_disponibles,
       NVL(o.noches, 0)                                AS noches_ocupadas,
       ROUND(100 * NVL(o.noches, 0) / (h.num_habitaciones * d.dias), 2) AS pct_ocupacion
  FROM alojamiento a
  JOIN municipio m         ON m.id_municipio = a.id_municipio
  JOIN tipo_alojamiento ta ON ta.id_tipo     = a.id_tipo
  JOIN (SELECT id_alojamiento, COUNT(*) AS num_habitaciones
          FROM habitacion
         GROUP BY id_alojamiento) h
    ON h.id_alojamiento = a.id_alojamiento
 CROSS JOIN (SELECT EXTRACT(YEAR FROM fecha)  AS anio,
                    EXTRACT(MONTH FROM fecha) AS mes,
                    COUNT(*)                  AS dias
               FROM calendario
              WHERE fecha < DATE '2027-01-01'
              GROUP BY EXTRACT(YEAR FROM fecha), EXTRACT(MONTH FROM fecha)) d
  LEFT JOIN (SELECT r.id_alojamiento,
                    EXTRACT(YEAR FROM c.fecha)  AS anio,
                    EXTRACT(MONTH FROM c.fecha) AS mes,
                    COUNT(*)                    AS noches
               FROM reserva r
               JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
               JOIN calendario c          ON c.fecha >= rh.fecha_checkin
                                         AND c.fecha <  rh.fecha_checkout
              WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
              GROUP BY r.id_alojamiento, EXTRACT(YEAR FROM c.fecha), EXTRACT(MONTH FROM c.fecha)) o
    ON o.id_alojamiento = a.id_alojamiento
   AND o.anio           = d.anio
   AND o.mes            = d.mes;

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS
  'Ocupacion mensual por alojamiento. Refresco COMPLETO bajo demanda, programado cada noche a las 2:00 a.m. (JOB_REFRESCO_OCUPACION).';

-- =====================================================================
-- B.2 TAREA PROGRAMADA: refresco completo cada noche a las 2:00 a.m.
--   DBMS_SCHEDULER es el programador de tareas de Oracle. La tarea llama
--   a DBMS_MVIEW.REFRESH con 'C' (complete = recalcular todo).
-- =====================================================================
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_REFRESCO_OCUPACION',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN DBMS_MVIEW.REFRESH(''MV_OCUPACION_MENSUAL'', ''C''); END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0; BYSECOND=0',
    enabled         => TRUE,
    comments        => 'Refresco completo nocturno de la vista materializada de ocupacion mensual');
END;
/

-- =====================================================================
-- B.3 VERIFICACION
-- =====================================================================
SELECT mview_name, refresh_mode, refresh_method, build_mode,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_refresco
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';

SELECT job_name, enabled, state, repeat_interval,
       TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI') AS proxima_ejecucion
  FROM user_scheduler_jobs
 WHERE job_name = 'JOB_REFRESCO_OCUPACION';

-- Debe dar 2.160 filas (60 alojamientos x 36 meses)
SELECT COUNT(*) AS filas_vista FROM mv_ocupacion_mensual;
