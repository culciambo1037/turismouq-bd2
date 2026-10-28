-- =====================================================================
-- 08_pruebas.sql
-- Proyecto integrador TurismoUQ - Bases de Datos II (2026-2) - ENTREGA 2
-- Autor: Cesar Arturo Giraldo Velez
--
-- QUE HACE: prueba cada componente de la Entrega 2 y deja la evidencia en
--   el Script Output (guardela como .txt o .pdf para la entrega).
--     P1. fn_valor_estadia          (20 %)
--     P2. sp_crear_reserva          (15 %)
--     P3. cursor de liquidacion     (15 %)
--     P4. disparador de sentencia   (10 %)
--     P5. disparador de fila        (10 %)
--     P6. tablespace                 (5 %)
--     P7. vista materializada       (15 %)
--   El paquete (10 %) se prueba en P1, P2 y P3: todo se llama como
--   PKG_TURISMO.<componente>.
--
-- COMO SE EJECUTA: conectado como TURISMO_UQ, despues de 04, 05, 06 y 07,
--   con F5. Al final limpia lo que creo, asi se puede repetir cuantas
--   veces se quiera sin alterar los resultados de la Entrega 1.
--
-- DATOS DE PRUEBA: se buscan por nombre (no por numero de ID), para que
--   el script funcione aunque los ID cambien.
--   Habitacion de referencia: la 101 del Hotel Mirador del Eje.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100

VARIABLE v_hab       NUMBER
VARIABLE v_reserva   NUMBER
VARIABLE v_hab_ocup  NUMBER
VARIABLE v_ocup_in   VARCHAR2(10)
VARIABLE v_ocup_out  VARCHAR2(10)
VARIABLE v_aloj      NUMBER

-- Habitacion de referencia
BEGIN
  SELECT h.id_habitacion INTO :v_hab
    FROM habitacion h
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   WHERE a.nombre_comercial = 'Hotel Mirador del Eje'
     AND h.numero = '101';
  DBMS_OUTPUT.PUT_LINE('Habitacion de referencia (Hotel Mirador del Eje, 101): id ' || :v_hab);
END;
/


-- #####################################################################
-- P1. fn_valor_estadia: valor noche por noche cruzando temporadas
-- #####################################################################

-- P1.1 Detalle noche por noche de una estadia del 10 al 17-dic-2026.
--      Del 10 al 14 es temporada MEDIA y desde el 15 es ALTA: la estadia
--      cruza temporadas. La noche del 17 (check-out) no aparece.
SELECT c.fecha,
       t.nombre      AS temporada,
       t.categoria,
       tf.precio_noche
  FROM calendario c
  JOIN temporada t ON t.id_temporada = c.id_temporada
  JOIN tarifa tf   ON tf.id_temporada = c.id_temporada
                  AND tf.id_habitacion = :v_hab
 WHERE c.fecha >= DATE '2026-12-10'
   AND c.fecha <  DATE '2026-12-17'
 ORDER BY c.fecha;

-- P1.2 La funcion debe dar exactamente la suma de la tabla anterior
SELECT pkg_turismo.fn_valor_estadia(:v_hab, DATE '2026-12-10', DATE '2026-12-17') AS valor_funcion,
       (SELECT SUM(tf.precio_noche)
          FROM calendario c
          JOIN tarifa tf ON tf.id_temporada = c.id_temporada AND tf.id_habitacion = :v_hab
         WHERE c.fecha >= DATE '2026-12-10' AND c.fecha < DATE '2026-12-17') AS suma_manual
  FROM dual;

-- P1.3 Contra los datos: el valor guardado (congelado) de 3.000 lineas de
--      reserva debe coincidir con lo que calcula la funcion hoy.
SELECT COUNT(*) AS lineas_revisadas,
       SUM(CASE WHEN rh.valor_estadia =
                     pkg_turismo.fn_valor_estadia(rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout)
                THEN 1 ELSE 0 END) AS coinciden
  FROM reserva_habitacion rh
 WHERE rh.id_reserva_hab <= 3000;

-- P1.4 Casos de error esperados
BEGIN
  DBMS_OUTPUT.PUT_LINE('P1.4a check-out igual al check-in:');
  DBMS_OUTPUT.PUT_LINE('  valor = ' || pkg_turismo.fn_valor_estadia(:v_hab, DATE '2026-12-10', DATE '2026-12-10'));
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  ERROR ESPERADO -> ' || SQLERRM);
END;
/
BEGIN
  DBMS_OUTPUT.PUT_LINE('P1.4b estadia fuera del calendario de temporadas (marzo de 2027):');
  DBMS_OUTPUT.PUT_LINE('  valor = ' || pkg_turismo.fn_valor_estadia(:v_hab, DATE '2027-03-01', DATE '2027-03-05'));
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  ERROR ESPERADO -> ' || SQLERRM);
END;
/


-- #####################################################################
-- P2. sp_crear_reserva: caso exitoso y sus tres excepciones propias
-- #####################################################################

-- P2.1 Caso exitoso: una habitacion del Hotel Mirador del Eje con
--      capacidad para 2 que este libre del 10 al 17-dic-2026.
--      Se fija la fecha de reserva (1-oct-2026) para que la prueba de
--      el mismo resultado sin importar el dia en que se corra.
DECLARE
  v_id NUMBER;
BEGIN
  SELECT MIN(h.id_habitacion) INTO :v_hab
    FROM habitacion h
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   WHERE a.nombre_comercial = 'Hotel Mirador del Eje'
     AND h.capacidad >= 2
     AND NOT EXISTS (SELECT 1
                       FROM reserva_habitacion rh
                       JOIN reserva r ON r.id_reserva = rh.id_reserva
                      WHERE rh.id_habitacion = h.id_habitacion
                        AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
                        AND rh.fecha_checkin < DATE '2026-12-17'
                        AND DATE '2026-12-10' < rh.fecha_checkout);

  DBMS_OUTPUT.PUT_LINE('P2.1 Caso exitoso con la habitacion libre ' || :v_hab || ':');
  pkg_turismo.sp_crear_reserva(
    p_id_cliente    => 1,
    p_id_habitacion => :v_hab,
    p_fecha_in      => DATE '2026-12-10',
    p_fecha_out     => DATE '2026-12-17',
    p_num_huespedes => 2,
    p_id_reserva    => v_id,
    p_fecha_reserva => DATE '2026-10-01');
  :v_reserva := v_id;
  COMMIT;
END;
/

-- Lo que quedo guardado (encabezado y linea con su valor congelado)
SELECT r.id_reserva, r.estado, r.fecha_reserva, r.fecha_checkin, r.fecha_checkout,
       rh.id_habitacion, rh.num_huespedes, rh.valor_estadia
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
 WHERE r.id_reserva = :v_reserva;

-- P2.2 Error -20001: check-out anterior al check-in
DECLARE
  v_id NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('P2.2 Check-out (10-dic) anterior al check-in (17-dic):');
  pkg_turismo.sp_crear_reserva(1, :v_hab, DATE '2026-12-17', DATE '2026-12-10', 2, v_id, DATE '2026-10-01');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  ERROR ESPERADO -> ' || SQLERRM);
END;
/

-- P2.3 Error -20002: capacidad excedida (habitacion sencilla, 3 huespedes)
DECLARE
  v_id   NUMBER;
  v_senc NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_senc FROM habitacion WHERE capacidad = 1;
  DBMS_OUTPUT.PUT_LINE('P2.3 Habitacion ' || v_senc || ' (capacidad 1) para 3 huespedes:');
  pkg_turismo.sp_crear_reserva(1, v_senc, DATE '2026-12-10', DATE '2026-12-17', 3, v_id, DATE '2026-10-01');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  ERROR ESPERADO -> ' || SQLERRM);
END;
/

-- P2.4 Error -20003: habitacion no disponible. Se toma una estadia ya
--      COMPLETADA y se intenta reservar la misma habitacion en las
--      mismas fechas.
DECLARE
  v_id  NUMBER;
  v_in  DATE;
  v_out DATE;
BEGIN
  SELECT rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout
    INTO :v_hab_ocup, v_in, v_out
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
   WHERE r.estado = 'COMPLETADA'
     AND rh.id_reserva_hab = (SELECT MIN(x.id_reserva_hab)
                                FROM reserva_habitacion x
                                JOIN reserva y ON y.id_reserva = x.id_reserva
                               WHERE y.estado = 'COMPLETADA');
  :v_ocup_in  := TO_CHAR(v_in,  'YYYY-MM-DD');
  :v_ocup_out := TO_CHAR(v_out, 'YYYY-MM-DD');

  DBMS_OUTPUT.PUT_LINE('P2.4 Habitacion ' || :v_hab_ocup || ' del ' || :v_ocup_in ||
                       ' al ' || :v_ocup_out || ' (ya ocupada):');
  pkg_turismo.sp_crear_reserva(1, :v_hab_ocup, v_in, v_out, 1, v_id, v_in - 30);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  ERROR ESPERADO -> ' || SQLERRM);
END;
/

-- P2.5 Error -20004 (extra): habitacion inexistente
DECLARE
  v_id NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('P2.5 Habitacion 999999 (no existe):');
  pkg_turismo.sp_crear_reserva(1, 999999, DATE '2026-12-10', DATE '2026-12-17', 2, v_id, DATE '2026-10-01');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  ERROR ESPERADO -> ' || SQLERRM);
END;
/


-- #####################################################################
-- P3. Cursor explicito con parametros: liquidacion de diciembre de 2025
-- #####################################################################
EXEC pkg_turismo.sp_liquidacion_mensual(2025, 12);

-- Los 10 alojamientos con mayor valor a pagar en el mes
SELECT a.nombre_comercial AS alojamiento, l.noches_vendidas, l.recaudo_bruto, l.reembolsos,
       l.recaudo_neto, l.comision, l.valor_a_pagar
  FROM liquidacion_mensual l
  JOIN alojamiento a ON a.id_alojamiento = l.id_alojamiento
 WHERE l.anio = 2025 AND l.mes = 12
 ORDER BY l.valor_a_pagar DESC
 FETCH FIRST 10 ROWS ONLY;

-- Control cruzado: el recaudo neto liquidado debe ser igual al recaudo
-- de diciembre 2025 que muestra la consulta 4 de la Entrega 1.
SELECT (SELECT COUNT(*)          FROM liquidacion_mensual WHERE anio = 2025 AND mes = 12) AS alojamientos,
       (SELECT SUM(recaudo_neto) FROM liquidacion_mensual WHERE anio = 2025 AND mes = 12) AS neto_liquidado,
       (SELECT SUM(CASE estado WHEN 'EXITOSO' THEN monto ELSE -monto END)
          FROM pago
         WHERE estado IN ('EXITOSO', 'REEMBOLSADO')
           AND fecha_pago >= DATE '2025-12-01'
           AND fecha_pago <  DATE '2026-01-01')                                       AS recaudo_consulta_4
  FROM dual;

-- Error esperado: mes invalido
BEGIN
  DBMS_OUTPUT.PUT_LINE('P3 Mes 13:');
  pkg_turismo.sp_liquidacion_mensual(2025, 13);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  ERROR ESPERADO -> ' || SQLERRM);
END;
/


-- #####################################################################
-- P4. Disparador de sentencia: auditoria de TARIFA
--     Una sola sentencia UPDATE sube 10.000 las tarifas de temporada ALTA
--     2026 de la habitacion 101; otra sentencia las devuelve. Cada
--     sentencia debe quedar como UN lote en la auditoria.
-- #####################################################################
BEGIN
  SELECT h.id_habitacion INTO :v_hab
    FROM habitacion h
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   WHERE a.nombre_comercial = 'Hotel Mirador del Eje'
     AND h.numero = '101';
END;
/

UPDATE tarifa
   SET precio_noche = precio_noche + 10000
 WHERE id_habitacion = :v_hab
   AND id_temporada IN (SELECT id_temporada FROM temporada WHERE categoria = 'ALTA' AND anio = 2026);
COMMIT;

UPDATE tarifa
   SET precio_noche = precio_noche - 10000
 WHERE id_habitacion = :v_hab
   AND id_temporada IN (SELECT id_temporada FROM temporada WHERE categoria = 'ALTA' AND anio = 2026);
COMMIT;

-- Detalle: quien, cuando, valor anterior y nuevo
SELECT a.id_lote, a.id_tarifa, t.nombre AS temporada, a.precio_anterior, a.precio_nuevo,
       a.usuario_bd, a.usuario_so, a.equipo,
       TO_CHAR(a.fecha_cambio, 'YYYY-MM-DD HH24:MI:SS') AS fecha_cambio
  FROM auditoria_tarifa a
  JOIN temporada t ON t.id_temporada = a.id_temporada
 WHERE a.id_lote IN (SELECT id_lote FROM (SELECT DISTINCT id_lote FROM auditoria_tarifa ORDER BY id_lote DESC)
                      WHERE ROWNUM <= 2)
 ORDER BY a.id_lote, a.id_tarifa;

-- Resumen: una fila por sentencia (lote)
SELECT id_lote, COUNT(*) AS tarifas_cambiadas,
       SUM(precio_nuevo - precio_anterior) AS cambio_total,
       MIN(usuario_bd) AS usuario,
       TO_CHAR(MIN(fecha_cambio), 'YYYY-MM-DD HH24:MI:SS') AS fecha
  FROM auditoria_tarifa
 GROUP BY id_lote
 ORDER BY id_lote;


-- #####################################################################
-- P5. Disparador de fila: impedir solapes en RESERVA_HABITACION
--     Se intenta insertar DIRECTAMENTE (sin pasar por el paquete) una
--     linea para la habitacion ya ocupada de la prueba P2.4, en las
--     mismas fechas, dentro de la reserva de prueba.
-- #####################################################################
BEGIN
  DBMS_OUTPUT.PUT_LINE('P5.1 Insercion directa que se solapa:');
  INSERT INTO reserva_habitacion (fecha_checkin, fecha_checkout, num_huespedes,
                                  valor_estadia, id_reserva, id_habitacion)
  VALUES (TO_DATE(:v_ocup_in, 'YYYY-MM-DD'), TO_DATE(:v_ocup_out, 'YYYY-MM-DD'),
          1, 100000, :v_reserva, :v_hab_ocup);
  DBMS_OUTPUT.PUT_LINE('  (no deberia llegar aqui)');
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  ERROR ESPERADO -> ' || SQLERRM);
END;
/

-- P5.2 La misma habitacion en fechas libres (enero de 2027) SI se acepta.
--      Se deshace enseguida con ROLLBACK: solo se quiere ver que pasa.
BEGIN
  DBMS_OUTPUT.PUT_LINE('P5.2 Misma habitacion en fechas libres:');
  INSERT INTO reserva_habitacion (fecha_checkin, fecha_checkout, num_huespedes,
                                  valor_estadia, id_reserva, id_habitacion)
  VALUES (DATE '2027-01-08', DATE '2027-01-10', 1, 100000, :v_reserva, :v_hab_ocup);
  DBMS_OUTPUT.PUT_LINE('  Insercion aceptada: ' || SQL%ROWCOUNT || ' fila. Se deshace con ROLLBACK.');
  ROLLBACK;
END;
/


-- #####################################################################
-- P6. Tablespace propio para el historico
-- #####################################################################
SELECT table_name, tablespace_name
  FROM user_tables
 WHERE table_name IN ('RESERVA', 'RESERVA_HABITACION', 'RESERVA_HISTORICO')
 ORDER BY table_name;

SELECT segment_name, tablespace_name, ROUND(bytes / 1024 / 1024, 2) AS mb
  FROM user_segments
 WHERE segment_name = 'RESERVA_HISTORICO';

SELECT tablespace_name,
       CASE max_bytes WHEN -1 THEN 'ILIMITADA' ELSE TO_CHAR(max_bytes) END AS cuota
  FROM user_ts_quotas
 ORDER BY tablespace_name;

SELECT anio_cierre, COUNT(*) AS reservas, SUM(total_pagado - total_reembolsado) AS recaudo_neto
  FROM reserva_historico
 GROUP BY anio_cierre
 ORDER BY anio_cierre;


-- #####################################################################
-- P7. Vista materializada: lectura, desactualizacion y refresco
-- #####################################################################

-- P7.1 Ocupacion de diciembre de 2026: los 10 alojamientos mas llenos
SELECT alojamiento, municipio, num_habitaciones, noches_ocupadas, noches_disponibles, pct_ocupacion
  FROM mv_ocupacion_mensual
 WHERE anio = 2026 AND mes = 12
 ORDER BY pct_ocupacion DESC
 FETCH FIRST 10 ROWS ONLY;

-- P7.2 Se CONFIRMA la reserva de prueba de P2.1 (7 noches en dic-2026).
--      La vista todavia NO la refleja: guarda el resultado del ultimo
--      refresco, no se recalcula sola.
UPDATE reserva SET estado = 'CONFIRMADA' WHERE id_reserva = :v_reserva;
COMMIT;

BEGIN
  SELECT r.id_alojamiento INTO :v_aloj FROM reserva r WHERE r.id_reserva = :v_reserva;
END;
/

SELECT 'ANTES DEL REFRESCO' AS momento,
       (SELECT noches_ocupadas FROM mv_ocupacion_mensual
         WHERE id_alojamiento = :v_aloj AND anio = 2026 AND mes = 12) AS noches_en_vista,
       (SELECT COUNT(*)
          FROM reserva r
          JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
          JOIN calendario c ON c.fecha >= rh.fecha_checkin AND c.fecha < rh.fecha_checkout
         WHERE r.id_alojamiento = :v_aloj
           AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
           AND c.fecha >= DATE '2026-12-01' AND c.fecha < DATE '2027-01-01') AS noches_reales
  FROM dual;

-- P7.3 Refresco manual (lo mismo que hace la tarea de las 2:00 a.m.)
EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');

SELECT 'DESPUES DEL REFRESCO' AS momento,
       (SELECT noches_ocupadas FROM mv_ocupacion_mensual
         WHERE id_alojamiento = :v_aloj AND anio = 2026 AND mes = 12) AS noches_en_vista,
       (SELECT COUNT(*)
          FROM reserva r
          JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
          JOIN calendario c ON c.fecha >= rh.fecha_checkin AND c.fecha < rh.fecha_checkout
         WHERE r.id_alojamiento = :v_aloj
           AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
           AND c.fecha >= DATE '2026-12-01' AND c.fecha < DATE '2027-01-01') AS noches_reales
  FROM dual;

SELECT mview_name, refresh_method, refresh_mode,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_refresco
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';

SELECT job_name, enabled, repeat_interval,
       TO_CHAR(next_run_date, 'YYYY-MM-DD HH24:MI') AS proxima_ejecucion
  FROM user_scheduler_jobs
 WHERE job_name = 'JOB_REFRESCO_OCUPACION';


-- #####################################################################
-- LIMPIEZA: se borra la reserva de prueba y se refresca la vista, para
-- que los datos queden igual que al terminar la Entrega 1.
-- (La auditoria y la liquidacion se conservan como evidencia.)
-- #####################################################################
DELETE FROM reserva_habitacion WHERE id_reserva = :v_reserva;
DELETE FROM reserva            WHERE id_reserva = :v_reserva;
COMMIT;
EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');

SELECT 'Pruebas terminadas' AS resultado FROM dual;
