-- =====================================================================
-- 03_consultas.sql
-- Proyecto integrador TurismoUQ - Bases de Datos II (2026-2)
-- Autor: Cesar Arturo Giraldo Velez
--
-- QUE HACE: las 7 consultas de analisis de la Entrega 1.
--   1. Ocupacion por municipio y mes ................ PIVOT
--   2. Ingresos por municipio, tipo y temporada ..... ROLLUP + GROUPING
--   3. Top 3 alojamientos por municipio ............. RANK + PARTITION BY
--   4. Variacion de recaudo mes contra mes .......... LAG
--   5. Ventas en un rango de fechas ................. variables de enlace
--   6. Composicion del valor por tipo ............... UNPIVOT
--   7. Calificacion real vs estrellas (libre) ....... DENSE_RANK + HAVING
--
-- COMO SE EJECUTA: conectado como TURISMO_UQ, despues de 01 y 02.
--   F5 ejecuta todo el script. Para ver una sola consulta, ponga el cursor
--   dentro de ella y presione Ctrl+Enter.
--
-- DEFINICIONES DE NEGOCIO USADAS (ver documento de reglas):
--   * Noche ocupada: cada dia entre el check-in (incluido) y el check-out
--     (excluido) de una linea de RESERVA_HABITACION. Solo cuentan las
--     reservas CONFIRMADAS o COMPLETADAS: las canceladas liberan la
--     habitacion y las pendientes aun no la bloquean.
--   * Recaudo (vista financiera): pagos EXITOSOS menos REEMBOLSOS, por
--     fecha de pago. Incluye estadias, servicios y lo retenido de las
--     canceladas.
--   * Ingreso por temporada (vista operativa): valor de las noches
--     ocupadas, cada una con la tarifa de la temporada de ESE dia.
--   * CALENDARIO + TARIFA resuelven la estadia que cruza temporadas: el
--     JOIN con calendario convierte cada estadia en una fila por noche,
--     y cada noche busca su propia temporada y su propia tarifa.
-- =====================================================================


-- =====================================================================
-- CONSULTA 1 - PIVOT
-- Pregunta: cual es el porcentaje de ocupacion de cada municipio, mes a
--           mes, en 2024, 2025 y 2026?
--   % ocupacion = noches ocupadas / noches disponibles x 100
--   noches disponibles = habitaciones del municipio x dias del mes
-- Como funciona:
--   * habitaciones_mun : cuantas habitaciones tiene cada municipio.
--   * dias_mes         : cuantos dias tiene cada mes (sale del calendario).
--   * noches_ocupadas  : el JOIN con CALENDARIO "explota" cada estadia en
--                        una fila por noche; luego se cuentan por mes.
--   * ocupacion        : arma una fila por municipio-anio-mes con su %.
--                        El LEFT JOIN deja en 0 los meses sin reservas.
--   * PIVOT gira los 12 meses de filas a columnas. Exige una funcion de
--     agregacion: como hay un solo valor por celda, MAX lo devuelve tal cual.
-- =====================================================================
WITH habitaciones_mun AS (
  SELECT a.id_municipio, COUNT(*) AS num_habitaciones
    FROM habitacion h
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   GROUP BY a.id_municipio
),
dias_mes AS (
  SELECT EXTRACT(YEAR FROM fecha) AS anio, EXTRACT(MONTH FROM fecha) AS mes, COUNT(*) AS dias
    FROM calendario
   WHERE fecha < DATE '2027-01-01'
   GROUP BY EXTRACT(YEAR FROM fecha), EXTRACT(MONTH FROM fecha)
),
noches_ocupadas AS (
  SELECT a.id_municipio,
         EXTRACT(YEAR FROM c.fecha)  AS anio,
         EXTRACT(MONTH FROM c.fecha) AS mes,
         COUNT(*)                    AS noches
    FROM reserva r
    JOIN reserva_habitacion rh ON rh.id_reserva     = r.id_reserva
    JOIN alojamiento a         ON a.id_alojamiento  = r.id_alojamiento
    JOIN calendario c          ON c.fecha >= rh.fecha_checkin
                              AND c.fecha <  rh.fecha_checkout
   WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
     AND c.fecha < DATE '2027-01-01'
   GROUP BY a.id_municipio, EXTRACT(YEAR FROM c.fecha), EXTRACT(MONTH FROM c.fecha)
),
ocupacion AS (
  SELECT m.nombre AS municipio,
         d.anio,
         d.mes,
         ROUND(100 * NVL(n.noches, 0) / (h.num_habitaciones * d.dias), 1) AS pct
    FROM municipio m
    JOIN habitaciones_mun h ON h.id_municipio = m.id_municipio
   CROSS JOIN dias_mes d
    LEFT JOIN noches_ocupadas n ON n.id_municipio = m.id_municipio
                               AND n.anio         = d.anio
                               AND n.mes          = d.mes
)
SELECT *
  FROM ocupacion
 PIVOT (MAX(pct) FOR mes IN (1 AS ene, 2 AS feb, 3 AS mar, 4  AS abr, 5  AS may, 6  AS jun,
                             7 AS jul, 8 AS ago, 9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic))
 ORDER BY municipio, anio;


-- =====================================================================
-- CONSULTA 2 - ROLLUP + GROUPING
-- Pregunta: cuanto ingreso cada municipio, cada tipo de alojamiento y cada
--           categoria de temporada en 2025, con subtotales y total general?
-- Como funciona:
--   * Cada noche ocupada de 2025 se valora con la tarifa de SU temporada
--     (JOIN calendario -> temporada -> tarifa). Asi una estadia del 20 al
--     26 de diciembre reparte su valor entre temporada media y alta.
--   * ROLLUP (municipio, tipo, temporada) produce, ademas del detalle:
--       - subtotal por municipio + tipo     (temporada agrupada)
--       - subtotal por municipio            (tipo y temporada agrupados)
--       - total general                     (todo agrupado)
--   * En esas filas de subtotal la columna agrupada viene en NULL.
--     GROUPING(col) devuelve 1 cuando la fila es un subtotal de esa
--     columna, y 0 cuando es un valor real. Con eso se ponen las etiquetas
--     y se ordena para que cada subtotal quede debajo de su detalle.
--   * GROUPING_ID resume el nivel: 0 detalle, 1 subtotal de tipo,
--     3 subtotal de municipio, 7 total general.
-- =====================================================================
SELECT CASE WHEN GROUPING(m.nombre) = 1 THEN '*** TOTAL GENERAL ***'
            ELSE m.nombre END                                         AS municipio,
       CASE WHEN GROUPING(m.nombre)  = 1 THEN '-'
            WHEN GROUPING(ta.nombre) = 1 THEN '** Subtotal municipio **'
            ELSE ta.nombre END                                        AS tipo_alojamiento,
       CASE WHEN GROUPING(ta.nombre)  = 1 THEN '-'
            WHEN GROUPING(t.categoria) = 1 THEN '* Subtotal tipo *'
            ELSE t.categoria END                                      AS temporada,
       COUNT(*)                                                       AS noches_vendidas,
       SUM(tf.precio_noche)                                           AS ingresos,
       GROUPING_ID(m.nombre, ta.nombre, t.categoria)                  AS nivel
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva    = r.id_reserva
  JOIN alojamiento a         ON a.id_alojamiento = r.id_alojamiento
  JOIN municipio m           ON m.id_municipio   = a.id_municipio
  JOIN tipo_alojamiento ta   ON ta.id_tipo       = a.id_tipo
  JOIN calendario c          ON c.fecha >= rh.fecha_checkin
                            AND c.fecha <  rh.fecha_checkout
  JOIN temporada t           ON t.id_temporada   = c.id_temporada
  JOIN tarifa tf             ON tf.id_habitacion = rh.id_habitacion
                            AND tf.id_temporada  = c.id_temporada
 WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND c.fecha BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
 GROUP BY ROLLUP (m.nombre, ta.nombre, t.categoria)
 ORDER BY GROUPING(m.nombre),   m.nombre,
          GROUPING(ta.nombre),  ta.nombre,
          GROUPING(t.categoria), t.categoria;


-- =====================================================================
-- CONSULTA 3 - RANK con PARTITION BY
-- Pregunta: cuales son los 3 alojamientos que mas recaudan DENTRO de cada
--           municipio, y que porcentaje del recaudo de su municipio
--           representan?
-- Como funciona:
--   * recaudo: pagos EXITOSOS suman, REEMBOLSADOS restan (regla D22);
--     PENDIENTES y FALLIDOS no cuentan porque el dinero no entro.
--   * RANK() OVER (PARTITION BY municipio ORDER BY recaudo DESC) numera
--     los alojamientos de 1 en adelante, REINICIANDO en cada municipio.
--     Si dos empatan, comparten puesto y el siguiente se salta (1,1,3).
--   * RATIO_TO_REPORT calcula la participacion de cada alojamiento en el
--     total de su municipio.
--   * El filtro puesto <= 3 va en la consulta EXTERNA: una funcion de
--     ventana no se puede usar en el WHERE del mismo SELECT que la calcula.
--   * Los municipios con menos de 3 alojamientos muestran los que tengan.
-- =====================================================================
WITH recaudo AS (
  SELECT r.id_alojamiento,
         SUM(CASE p.estado WHEN 'EXITOSO'     THEN  p.monto
                           WHEN 'REEMBOLSADO' THEN -p.monto
                           ELSE 0 END) AS recaudo
    FROM pago p
    JOIN reserva r ON r.id_reserva = p.id_reserva
   GROUP BY r.id_alojamiento
),
ranking AS (
  SELECT m.nombre           AS municipio,
         a.nombre_comercial AS alojamiento,
         ta.nombre          AS tipo,
         rc.recaudo,
         RANK() OVER (PARTITION BY m.nombre ORDER BY rc.recaudo DESC)        AS puesto,
         ROUND(100 * RATIO_TO_REPORT(rc.recaudo) OVER (PARTITION BY m.nombre), 1) AS pct_del_municipio
    FROM recaudo rc
    JOIN alojamiento a       ON a.id_alojamiento = rc.id_alojamiento
    JOIN municipio m         ON m.id_municipio   = a.id_municipio
    JOIN tipo_alojamiento ta ON ta.id_tipo       = a.id_tipo
)
SELECT municipio, puesto, alojamiento, tipo, recaudo, pct_del_municipio
  FROM ranking
 WHERE puesto <= 3
 ORDER BY municipio, puesto;


-- =====================================================================
-- CONSULTA 4 - LAG
-- Pregunta: como varia el recaudo de la plataforma de un mes a otro, y
--           como va contra el mismo mes del anio anterior?
-- Como funciona:
--   * mensual: recaudo neto por mes de pago (EXITOSOS - REEMBOLSOS).
--     Los reembolsos restan en el mes en que se hacen.
--   * LAG(recaudo)     trae el valor de la fila ANTERIOR (mes anterior).
--   * LAG(recaudo, 12) trae el valor de 12 filas atras (mismo mes del
--     anio anterior). Funciona porque todos los meses tienen pagos.
--   * El primer mes no tiene anterior: LAG devuelve NULL y la variacion
--     tambien queda en NULL (no es un error).
--   * NULLIF evita una division por cero si algun mes tuviera recaudo 0.
--   * El filtro de fecha deja explicito el periodo analizado: 2024 a 2026.
-- =====================================================================
WITH mensual AS (
  SELECT TRUNC(p.fecha_pago, 'MM') AS mes,
         SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto ELSE -p.monto END) AS recaudo
    FROM pago p
   WHERE p.estado IN ('EXITOSO', 'REEMBOLSADO')
     AND p.fecha_pago < DATE '2027-01-01'   -- periodo analizado: 2024 a 2026
   GROUP BY TRUNC(p.fecha_pago, 'MM')
)
SELECT TO_CHAR(mes, 'YYYY-MM')                              AS periodo,
       recaudo,
       LAG(recaudo) OVER (ORDER BY mes)                     AS recaudo_mes_anterior,
       recaudo - LAG(recaudo) OVER (ORDER BY mes)           AS variacion,
       ROUND(100 * (recaudo - LAG(recaudo) OVER (ORDER BY mes))
                 / NULLIF(LAG(recaudo) OVER (ORDER BY mes), 0), 1) AS variacion_pct,
       LAG(recaudo, 12) OVER (ORDER BY mes)                 AS mismo_mes_anio_anterior,
       ROUND(100 * (recaudo - LAG(recaudo, 12) OVER (ORDER BY mes))
                 / NULLIF(LAG(recaudo, 12) OVER (ORDER BY mes), 0), 1) AS variacion_anual_pct
  FROM mensual
 ORDER BY mes;


-- =====================================================================
-- CONSULTA 5 - CONSULTA PARAMETRIZADA con variables de enlace
-- Pregunta: para un rango de fechas cualquiera, cuantas noches vendio
--           cada tipo de alojamiento, cuanto ingreso y a que tarifa
--           promedio por noche?
-- Como funciona:
--   * VARIABLE declara variables de enlace (bind variables) en la sesion;
--     EXEC les asigna valor. En la consulta se usan con dos puntos
--     (:fecha_ini). Para otro rango basta cambiar los dos EXEC.
--   * Por que variables de enlace y no fechas escritas en el SQL:
--       - Oracle analiza la consulta una sola vez y reutiliza el plan de
--         ejecucion con cualquier valor (menos trabajo para el motor).
--       - El valor viaja separado del codigo SQL: evita inyeccion de SQL.
--   * Una noche cuenta si su fecha cae dentro del rango, aunque la
--     estadia empiece antes o termine despues.
--   * Si ejecuta solo el SELECT con Ctrl+Enter, SQL Developer abre una
--     ventana para escribir los valores (formato AAAA-MM-DD).
--   Ejemplo: temporada decembrina 2025-2026.
-- =====================================================================
VARIABLE fecha_ini VARCHAR2(10)
VARIABLE fecha_fin VARCHAR2(10)
EXEC :fecha_ini := '2025-12-15';
EXEC :fecha_fin := '2026-01-12';

SELECT ta.nombre                     AS tipo_alojamiento,
       COUNT(DISTINCT r.id_reserva)  AS reservas,
       COUNT(*)                      AS noches_vendidas,
       SUM(tf.precio_noche)          AS ingreso_estadias,
       ROUND(AVG(tf.precio_noche))   AS tarifa_promedio_noche
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva    = r.id_reserva
  JOIN alojamiento a         ON a.id_alojamiento = r.id_alojamiento
  JOIN tipo_alojamiento ta   ON ta.id_tipo       = a.id_tipo
  JOIN calendario c          ON c.fecha >= rh.fecha_checkin
                            AND c.fecha <  rh.fecha_checkout
  JOIN tarifa tf             ON tf.id_habitacion = rh.id_habitacion
                            AND tf.id_temporada  = c.id_temporada
 WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND c.fecha BETWEEN TO_DATE(:fecha_ini, 'YYYY-MM-DD')
                   AND TO_DATE(:fecha_fin, 'YYYY-MM-DD')
 GROUP BY ta.nombre
 ORDER BY ingreso_estadias DESC;


-- =====================================================================
-- CONSULTA 6 - UNPIVOT
-- Pregunta: de que se compone el valor que genera cada tipo de
--           alojamiento: estadias, servicios complementarios o dinero
--           retenido por cancelaciones?
-- Como funciona:
--   * por_tipo calcula los tres componentes como TRES COLUMNAS:
--       estadias   = suma de valor_estadia (precio congelado) de reservas
--                    confirmadas o completadas;
--       servicios  = cantidad x precio_unitario de esas mismas reservas;
--       retenido   = pagos EXITOSOS - REEMBOLSOS de reservas canceladas
--                    (el 20 % o el 100 % que se queda el alojamiento).
--   * UNPIVOT hace lo contrario de PIVOT: convierte esas tres columnas en
--     FILAS (una por componente), con dos columnas nuevas: "componente"
--     (el nombre) y "valor" (la cifra). Asi se pueden ordenar y comparar.
--   * RATIO_TO_REPORT da el peso de cada componente dentro de su tipo.
-- =====================================================================
WITH estadias AS (
  SELECT r.id_alojamiento, SUM(rh.valor_estadia) AS valor
    FROM reserva r
    JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
   WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
   GROUP BY r.id_alojamiento
),
servicios AS (
  SELECT r.id_alojamiento, SUM(rs.cantidad * rs.precio_unitario) AS valor
    FROM reserva r
    JOIN reserva_servicio rs ON rs.id_reserva = r.id_reserva
   WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
   GROUP BY r.id_alojamiento
),
retenido AS (
  SELECT r.id_alojamiento,
         SUM(CASE p.estado WHEN 'EXITOSO' THEN p.monto ELSE -p.monto END) AS valor
    FROM reserva r
    JOIN pago p ON p.id_reserva = r.id_reserva
   WHERE r.estado = 'CANCELADA'
     AND p.estado IN ('EXITOSO', 'REEMBOLSADO')
   GROUP BY r.id_alojamiento
),
por_tipo AS (
  SELECT ta.nombre               AS tipo,
         NVL(SUM(e.valor), 0)    AS estadias,
         NVL(SUM(s.valor), 0)    AS servicios,
         NVL(SUM(rt.valor), 0)   AS retenido
    FROM alojamiento a
    JOIN tipo_alojamiento ta ON ta.id_tipo = a.id_tipo
    LEFT JOIN estadias  e  ON e.id_alojamiento  = a.id_alojamiento
    LEFT JOIN servicios s  ON s.id_alojamiento  = a.id_alojamiento
    LEFT JOIN retenido  rt ON rt.id_alojamiento = a.id_alojamiento
   GROUP BY ta.nombre
)
SELECT tipo,
       componente,
       valor,
       ROUND(100 * RATIO_TO_REPORT(valor) OVER (PARTITION BY tipo), 1) AS pct_del_tipo
  FROM por_tipo
UNPIVOT (valor FOR componente IN (estadias  AS 'ESTADIAS',
                                  servicios AS 'SERVICIOS',
                                  retenido  AS 'RETENIDO POR CANCELACIONES'))
 ORDER BY tipo, valor DESC;


-- =====================================================================
-- CONSULTA 7 - CONSULTA LIBRE
-- Pregunta de negocio: que tan bien calificados estan los alojamientos
--   segun sus resenas, y coinciden las estrellas que ellos mismos se
--   autoasignan con lo que opinan los clientes?
--   (La gerencia lo pide en la seccion 1.8 del enunciado.)
-- Como funciona:
--   * Agrupa las resenas por alojamiento: numero, promedio, % de 5
--     estrellas y % de resenas negativas (1 o 2 estrellas).
--   * HAVING COUNT(*) >= 20 deja por fuera alojamientos con pocas resenas,
--     cuyo promedio no seria confiable.
--   * DENSE_RANK() OVER (PARTITION BY tipo ...) da el puesto de cada
--     alojamiento dentro de su tipo. La funcion de ventana se aplica
--     DESPUES del GROUP BY, por eso puede ordenar por AVG(...).
--     A diferencia de RANK, no salta puestos tras un empate (1,1,2).
--   * brecha = estrellas autoasignadas - promedio real. Positiva: el
--     alojamiento promete mas de lo que entrega.
-- =====================================================================
SELECT ta.nombre                                                         AS tipo,
       DENSE_RANK() OVER (PARTITION BY ta.nombre
                          ORDER BY AVG(re.calificacion) DESC)            AS puesto_en_su_tipo,
       a.nombre_comercial                                                AS alojamiento,
       m.nombre                                                          AS municipio,
       COUNT(*)                                                          AS resenas,
       ROUND(AVG(re.calificacion), 2)                                    AS promedio_real,
       a.estrellas                                                       AS estrellas_autoasignadas,
       ROUND(a.estrellas - AVG(re.calificacion), 2)                      AS brecha,
       ROUND(100 * SUM(CASE WHEN re.calificacion = 5  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_5_estrellas,
       ROUND(100 * SUM(CASE WHEN re.calificacion <= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_negativas
  FROM resena re
  JOIN reserva r           ON r.id_reserva     = re.id_reserva
  JOIN alojamiento a       ON a.id_alojamiento = r.id_alojamiento
  JOIN tipo_alojamiento ta ON ta.id_tipo       = a.id_tipo
  JOIN municipio m         ON m.id_municipio   = a.id_municipio
 GROUP BY ta.nombre, a.nombre_comercial, m.nombre, a.estrellas
HAVING COUNT(*) >= 20
 ORDER BY tipo, puesto_en_su_tipo, resenas DESC;
