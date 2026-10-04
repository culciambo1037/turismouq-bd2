-- =====================================================================
-- 02_carga.sql
-- Proyecto integrador TurismoUQ - Bases de Datos II (2026-2)
-- Autor: Cesar Arturo Giraldo Velez
--
-- QUE HACE: llena las 15 tablas con datos de prueba ASIMETRICOS y con el
--           volumen minimo exigido (25.000+ reservas, 40.000+ servicios...).
--
-- COMO SE EJECUTA: conectado como TURISMO_UQ, despues de 01_ddl.sql, con F5.
--   Tarda entre 1 y 5 minutos. Al final muestra un resumen de conteos.
--
-- IDEAS CLAVE:
--   * Datos asimetricos a proposito: municipios con 12 alojamientos y otros
--     con 1; hoteles de 40 habitaciones y fincas de 3; mas reservas en
--     temporada alta, fines de semana y municipios turisticos (Salento,
--     Filandia, Montenegro). Sin asimetria, ROLLUP, PIVOT y RANK no
--     mostrarian diferencias reales.
--   * DBMS_RANDOM.SEED con una semilla propia: cada ejecucion produce
--     EXACTAMENTE los mismos datos (reproducible) y distintos a los de
--     cualquier otro grupo.
--   * Fecha de corte del generador: 31-dic-2026 (constante c_hoy). Los
--     anios 2024, 2025 y 2026 quedan COMPLETOS, como pide el enunciado.
--     Solo las estadias que empiezan en diciembre y terminan en enero de
--     2027 quedan CONFIRMADAS (huesped alojado al corte). Ninguna reserva
--     posterior al corte puede estar COMPLETADA ni tener resena, y ningun
--     pago futuro puede estar EXITOSO (reglas D7 y D25).
--   * El generador respeta las reglas de negocio desde ya: ninguna
--     habitacion queda con dos reservas activas solapadas (regla L9), los
--     huespedes no superan la capacidad (D4), el valor de cada estadia se
--     calcula noche por noche con la tarifa vigente (D9), etc.
--   * Los datos de texto van sin tildes para evitar problemas de
--     codificacion al abrir el archivo en Windows.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED


-- =====================================================================
-- 0. LIMPIEZA: borra los datos (de hijas a padres) para poder recargar.
--    Para empezar desde cero con los ID en 1, vuelva a correr 01_ddl.sql.
-- =====================================================================
DELETE FROM resena;
DELETE FROM pago;
DELETE FROM reserva_servicio;
DELETE FROM reserva_habitacion;
DELETE FROM reserva;
DELETE FROM usuario_sistema;
DELETE FROM cliente;
DELETE FROM tarifa;
DELETE FROM calendario;
DELETE FROM temporada;
DELETE FROM servicio;
DELETE FROM habitacion;
DELETE FROM alojamiento;
DELETE FROM tipo_alojamiento;
DELETE FROM municipio;
COMMIT;


-- =====================================================================
-- 1. MUNICIPIOS: los 12 municipios reales del Quindio.
--    El ID lo genera Oracle (IDENTITY); por eso mas adelante las FK se
--    buscan por nombre con subconsultas, nunca con numeros fijos.
-- =====================================================================
INSERT INTO municipio (nombre) VALUES ('Armenia');
INSERT INTO municipio (nombre) VALUES ('Buenavista');
INSERT INTO municipio (nombre) VALUES ('Calarca');
INSERT INTO municipio (nombre) VALUES ('Circasia');
INSERT INTO municipio (nombre) VALUES ('Cordoba');
INSERT INTO municipio (nombre) VALUES ('Filandia');
INSERT INTO municipio (nombre) VALUES ('Genova');
INSERT INTO municipio (nombre) VALUES ('La Tebaida');
INSERT INTO municipio (nombre) VALUES ('Montenegro');
INSERT INTO municipio (nombre) VALUES ('Pijao');
INSERT INTO municipio (nombre) VALUES ('Quimbaya');
INSERT INTO municipio (nombre) VALUES ('Salento');


-- =====================================================================
-- 2. TIPOS DE ALOJAMIENTO: los 4 del enunciado + Ecohotel (agregado).
-- =====================================================================
INSERT INTO tipo_alojamiento (nombre, descripcion)
  VALUES ('Finca cafetera', 'Casa campestre en finca productora de cafe, pocas habitaciones.');
INSERT INTO tipo_alojamiento (nombre, descripcion)
  VALUES ('Hotel', 'Establecimiento urbano con varias plantas y servicios completos.');
INSERT INTO tipo_alojamiento (nombre, descripcion)
  VALUES ('Glamping', 'Domos o cabanas de lujo en medio de la naturaleza.');
INSERT INTO tipo_alojamiento (nombre, descripcion)
  VALUES ('Hostal', 'Alojamiento economico orientado a mochileros.');
INSERT INTO tipo_alojamiento (nombre, descripcion)
  VALUES ('Ecohotel', 'Hotel sostenible en zona rural o de reserva natural.');
COMMIT;


-- =====================================================================
-- 3. ALOJAMIENTOS (60) Y HABITACIONES (598)
--    Reparto desigual por municipio (Armenia 12, Salento 10 ... Pijao 1)
--    y por tamano (hoteles de 15 a 40 habitaciones, fincas de 3 a 8).
--    El procedimiento local "aloj" inserta un alojamiento y luego crea
--    sus habitaciones segun el tipo:
--      Hotel / Hostal / Ecohotel -> numeradas por piso (101, 102 ... 201)
--      Finca cafetera            -> H1, H2, H3 ...
--      Glamping                  -> D1, D2 ... (domos)
--    Los nombres comerciales son inventados.
-- =====================================================================
DECLARE
  -- Inserta una habitacion
  PROCEDURE hab (p_aloj NUMBER, p_num VARCHAR2, p_tipo VARCHAR2, p_cap NUMBER, p_desc VARCHAR2) IS
  BEGIN
    INSERT INTO habitacion (numero, tipo_habitacion, capacidad, descripcion, id_alojamiento)
    VALUES (p_num, p_tipo, p_cap, p_desc, p_aloj);
  END hab;

  -- Inserta un alojamiento y sus p_num_hab habitaciones
  PROCEDURE aloj (p_nombre VARCHAR2, p_municipio VARCHAR2, p_tipo VARCHAR2,
                  p_estrellas NUMBER, p_num_hab NUMBER) IS
    v_id     alojamiento.id_alojamiento%TYPE;
    v_rural  BOOLEAN := p_tipo IN ('Finca cafetera', 'Glamping', 'Ecohotel');
    v_dir    VARCHAR2(150);
    v_slug   VARCHAR2(100) := LOWER(REPLACE(p_nombre, ' ', ''));
    v_num    VARCHAR2(10);
    v_u      NUMBER;
  BEGIN
    -- Direccion: vereda y kilometro si es rural; calle y carrera si es urbano
    IF v_rural THEN
      v_dir := 'Vereda ' ||
               CASE MOD(LENGTH(p_nombre), 6)
                 WHEN 0 THEN 'La Floresta' WHEN 1 THEN 'El Agrado' WHEN 2 THEN 'Boquia'
                 WHEN 3 THEN 'La Cabana'   WHEN 4 THEN 'El Caimo'  ELSE 'Pueblo Tapao' END ||
               ', km ' || TRUNC(DBMS_RANDOM.VALUE(1, 15)) || ' via ' || p_municipio;
    ELSE
      v_dir := 'Carrera ' || TRUNC(DBMS_RANDOM.VALUE(1, 30)) || ' # ' ||
               TRUNC(DBMS_RANDOM.VALUE(1, 50)) || '-' || TRUNC(DBMS_RANDOM.VALUE(1, 99)) ||
               ', ' || p_municipio;
    END IF;

    INSERT INTO alojamiento (nombre_comercial, direccion, estrellas, telefono, correo,
                             id_municipio, id_tipo)
    VALUES (p_nombre, v_dir, p_estrellas,
            '606' || TRUNC(DBMS_RANDOM.VALUE(7300000, 7499999)),
            'reservas@' || v_slug || '.turismouq.co',
            (SELECT id_municipio FROM municipio        WHERE nombre = p_municipio),
            (SELECT id_tipo      FROM tipo_alojamiento WHERE nombre = p_tipo))
    RETURNING id_alojamiento INTO v_id;

    -- Habitaciones del alojamiento
    FOR i IN 1 .. p_num_hab LOOP
      v_u := DBMS_RANDOM.VALUE;
      IF p_tipo IN ('Hotel', 'Hostal', 'Ecohotel') THEN
        v_num := TO_CHAR((TRUNC((i - 1) / 10) + 1) * 100 + MOD(i - 1, 10) + 1);  -- 101..110, 201..
      ELSIF p_tipo = 'Glamping' THEN
        v_num := 'D' || i;
      ELSE
        v_num := 'H' || i;
      END IF;

      IF p_tipo = 'Hotel' THEN
        IF    v_u < 0.30 THEN hab(v_id, v_num, 'SENCILLA', 1, 'Habitacion sencilla con escritorio');
        ELSIF v_u < 0.75 THEN hab(v_id, v_num, 'DOBLE',    2, 'Habitacion doble con vista a la ciudad');
        ELSIF v_u < 0.90 THEN hab(v_id, v_num, 'DOBLE',    3, 'Habitacion doble con cama adicional');
        ELSE                  hab(v_id, v_num, 'SUITE',    4, 'Suite con sala y balcon');
        END IF;
      ELSIF p_tipo = 'Hostal' THEN
        IF    v_u < 0.35 THEN hab(v_id, v_num, 'SENCILLA', 1, 'Habitacion sencilla con bano compartido');
        ELSIF v_u < 0.80 THEN hab(v_id, v_num, 'DOBLE',    2, 'Habitacion doble con bano privado');
        ELSE                  hab(v_id, v_num, 'SUITE',    6, 'Habitacion familiar con camarotes');
        END IF;
      ELSIF p_tipo = 'Glamping' THEN
        IF    v_u < 0.60 THEN hab(v_id, v_num, 'CABANA',   2, 'Domo para pareja con jacuzzi');
        ELSE                  hab(v_id, v_num, 'CABANA',   4, 'Domo familiar con malla catamaran');
        END IF;
      ELSIF p_tipo = 'Ecohotel' THEN
        IF    v_u < 0.50 THEN hab(v_id, v_num, 'DOBLE',    2, 'Habitacion doble en guadua');
        ELSIF v_u < 0.75 THEN hab(v_id, v_num, 'SUITE',    3, 'Suite con terraza al bosque');
        ELSE                  hab(v_id, v_num, 'CABANA',   4, 'Cabana independiente junto al rio');
        END IF;
      ELSE  -- Finca cafetera
        IF    v_u < 0.50 THEN hab(v_id, v_num, 'DOBLE',    2, 'Habitacion doble con vista al cafetal');
        ELSIF v_u < 0.80 THEN hab(v_id, v_num, 'SUITE',    4, 'Habitacion familiar en la casa principal');
        ELSE                  hab(v_id, v_num, 'CABANA',   6, 'Cabana para grupos junto a la piscina');
        END IF;
      END IF;
    END LOOP;
  END aloj;

BEGIN
  DBMS_RANDOM.SEED(20261004);

  --      nombre comercial                  municipio     tipo             estrellas  habitaciones
  -- Armenia (12): la capital concentra los hoteles grandes
  aloj('Hotel Mirador del Eje',            'Armenia',    'Hotel',          4, 40);
  aloj('Hotel Plaza Cafetera',             'Armenia',    'Hotel',          4, 36);
  aloj('Hotel Avenida Centenario',         'Armenia',    'Hotel',          3, 32);
  aloj('Hotel Ciudad Milagro',             'Armenia',    'Hotel',          3, 28);
  aloj('Hotel Torre del Quindio',          'Armenia',    'Hotel',          5, 24);
  aloj('Hotel Parque Sucre',               'Armenia',    'Hotel',          3, 20);
  aloj('Hotel Los Fundadores',             'Armenia',    'Hotel',          4, 18);
  aloj('Hotel Cielo Verde',                'Armenia',    'Hotel',          2, 15);
  aloj('Hostal La Estacion',               'Armenia',    'Hostal',         2, 12);
  aloj('Hostal Ruta Cafetera',             'Armenia',    'Hostal',         1,  8);
  aloj('Ecohotel Bosque de Guaduas',       'Armenia',    'Ecohotel',       4, 10);
  aloj('Finca El Retiro',                  'Armenia',    'Finca cafetera', 3,  5);
  -- Salento (10): destino mas turistico, mezcla de glamping, hostales y fincas
  aloj('Hotel Calle Real',                 'Salento',    'Hotel',          3, 14);
  aloj('Hostal Palma de Cera',             'Salento',    'Hostal',         2, 14);
  aloj('Hostal Mochileros del Cocora',     'Salento',    'Hostal',         1, 10);
  aloj('Glamping Valle de las Palmas',     'Salento',    'Glamping',       4,  6);
  aloj('Glamping Estrellas del Cocora',    'Salento',    'Glamping',       5,  4);
  aloj('Glamping Nido de Niebla',          'Salento',    'Glamping',       4,  5);
  aloj('Finca La Esperanza',               'Salento',    'Finca cafetera', 3,  6);
  aloj('Finca Los Arrayanes',              'Salento',    'Finca cafetera', 4,  4);
  aloj('Finca El Ocaso Dorado',            'Salento',    'Finca cafetera', 3,  8);
  aloj('Ecohotel Rio Quindio',             'Salento',    'Ecohotel',       4, 12);
  -- Filandia (8)
  aloj('Hotel Mirador de Filandia',        'Filandia',   'Hotel',          3, 12);
  aloj('Finca Colina Iluminada',           'Filandia',   'Finca cafetera', 4,  7);
  aloj('Finca Santa Barbara',              'Filandia',   'Finca cafetera', 3,  5);
  aloj('Finca La Cristalina',              'Filandia',   'Finca cafetera', 3,  3);
  aloj('Glamping Bambu y Luna',            'Filandia',   'Glamping',       4,  4);
  aloj('Glamping Cerro Bravo',             'Filandia',   'Glamping',       3,  3);
  aloj('Hostal Canastos y Bahareque',      'Filandia',   'Hostal',         2,  8);
  aloj('Ecohotel Barbas Bremen',           'Filandia',   'Ecohotel',       4,  9);
  -- Montenegro (7): cerca de los parques tematicos
  aloj('Hotel Parque Tematico',            'Montenegro', 'Hotel',          4, 22);
  aloj('Finca Villa Maria',                'Montenegro', 'Finca cafetera', 3,  8);
  aloj('Finca El Cafetal',                 'Montenegro', 'Finca cafetera', 3,  6);
  aloj('Finca La Pradera',                 'Montenegro', 'Finca cafetera', 2,  4);
  aloj('Finca Monte Alegre',               'Montenegro', 'Finca cafetera', 3,  5);
  aloj('Glamping Pueblo Tapao',            'Montenegro', 'Glamping',       3,  5);
  aloj('Ecohotel Guadual del Eje',         'Montenegro', 'Ecohotel',       3,  8);
  -- Quimbaya (6)
  aloj('Hotel Noche de Velas',             'Quimbaya',   'Hotel',          3, 18);
  aloj('Finca La Granja',                  'Quimbaya',   'Finca cafetera', 3,  7);
  aloj('Finca Los Naranjos',               'Quimbaya',   'Finca cafetera', 2,  5);
  aloj('Finca San Isidro',                 'Quimbaya',   'Finca cafetera', 3,  4);
  aloj('Glamping Panorama Verde',          'Quimbaya',   'Glamping',       4,  4);
  aloj('Hostal El Viajero',                'Quimbaya',   'Hostal',         2,  7);
  -- Calarca (5)
  aloj('Hotel Jardin Botanico',            'Calarca',    'Hotel',          3, 16);
  aloj('Finca El Mirador',                 'Calarca',    'Finca cafetera', 3,  5);
  aloj('Finca La Bella',                   'Calarca',    'Finca cafetera', 2,  4);
  aloj('Ecohotel Mariposario',             'Calarca',    'Ecohotel',       4,  7);
  aloj('Glamping Alto del Cielo',          'Calarca',    'Glamping',       3,  3);
  -- Circasia (4)
  aloj('Finca El Bosque',                  'Circasia',   'Finca cafetera', 3,  6);
  aloj('Finca La Montana',                 'Circasia',   'Finca cafetera', 2,  3);
  aloj('Glamping Hojas de Cafe',           'Circasia',   'Glamping',       3,  5);
  aloj('Hostal Puerta del Quindio',        'Circasia',   'Hostal',         2, 11);
  -- La Tebaida (3)
  aloj('Hotel Ruta del Eden',              'La Tebaida', 'Hotel',          3, 20);
  aloj('Finca Las Palmas',                 'La Tebaida', 'Finca cafetera', 3,  6);
  aloj('Finca Piscina Azul',               'La Tebaida', 'Finca cafetera', 2,  5);
  -- Buenavista (2), Pijao (1), Cordoba (1), Genova (1): municipios pequenos
  aloj('Glamping Mirador de Buenavista',   'Buenavista', 'Glamping',       4,  6);
  aloj('Finca Balcon del Quindio',         'Buenavista', 'Finca cafetera', 3,  4);
  aloj('Finca Pueblo Lento',               'Pijao',      'Finca cafetera', 3,  3);
  aloj('Finca Rio Verde',                  'Cordoba',    'Finca cafetera', 2,  3);
  aloj('Ecohotel Cordillera Central',      'Genova',     'Ecohotel',       3,  6);

  COMMIT;
END;
/


-- =====================================================================
-- 4. SERVICIOS (unos 190 repartidos en los 60 alojamientos)
--    Catalogo base con los tipos de alojamiento que pueden ofrecer cada
--    servicio. Cada alojamiento toma al azar una parte de su catalogo y
--    ajusta el precio (+-20 %): asi el "Desayuno" de un hotel y el de otro
--    son servicios distintos, con precios distintos (regla D19).
-- =====================================================================
DECLARE
  TYPE t_srv IS RECORD (nombre VARCHAR2(60), precio NUMBER, descr VARCHAR2(200), tipos VARCHAR2(100));
  TYPE t_cat IS TABLE OF t_srv INDEX BY PLS_INTEGER;
  v_cat  t_cat;
  v_n    PLS_INTEGER := 0;
  v_key  VARCHAR2(20);

  PROCEDURE agregar (p_nombre VARCHAR2, p_precio NUMBER, p_descr VARCHAR2, p_tipos VARCHAR2) IS
    v_r t_srv;
  BEGIN
    v_r.nombre := p_nombre;  v_r.precio := p_precio;
    v_r.descr  := p_descr;   v_r.tipos  := p_tipos;
    v_n := v_n + 1;
    v_cat(v_n) := v_r;
  END agregar;
BEGIN
  DBMS_RANDOM.SEED(20261005);

  --       nombre                          precio  descripcion                                      tipos que lo ofrecen
  agregar('Desayuno tipico quindiano',      22000, 'Arepa, huevos, cafe de origen y fruta',          '|FINCA|GLAMPING|HOSTAL|ECOHOTEL|');
  agregar('Desayuno buffet',                35000, 'Buffet continental y tipico',                    '|HOTEL|');
  agregar('Tour del cafe',                  85000, 'Recorrido por el cafetal y proceso del grano',   '|FINCA|GLAMPING|HOSTAL|ECOHOTEL|');
  agregar('Transporte aeropuerto El Eden',  70000, 'Traslado privado desde o hacia el aeropuerto',   '|HOTEL|FINCA|ECOHOTEL|GLAMPING|');
  agregar('Spa y masajes',                 150000, 'Masaje relajante de 60 minutos',                 '|HOTEL|GLAMPING|');
  agregar('Alquiler de bicicletas',         40000, 'Bicicleta todo terreno por dia',                 '|HOSTAL|ECOHOTEL|FINCA|');
  agregar('Cabalgata',                      90000, 'Cabalgata guiada de dos horas',                  '|FINCA|ECOHOTEL|');
  agregar('Avistamiento de aves',           75000, 'Caminata guiada al amanecer',                    '|ECOHOTEL|GLAMPING|');
  agregar('Tour Valle del Cocora',         110000, 'Excursion de dia completo con guia',             '|HOSTAL|GLAMPING|HOTEL|');
  agregar('Cena romantica',                180000, 'Cena para dos con decoracion especial',          '|GLAMPING|HOTEL|');
  agregar('Lavanderia',                     25000, 'Lavado y planchado por bolsa',                   '|HOTEL|HOSTAL|');
  agregar('Jacuzzi privado',               120000, 'Uso exclusivo por dos horas',                    '|GLAMPING|');

  FOR a IN (SELECT al.id_alojamiento, ta.nombre AS tipo
              FROM alojamiento al
              JOIN tipo_alojamiento ta ON ta.id_tipo = al.id_tipo
             ORDER BY al.id_alojamiento)
  LOOP
    -- Primera palabra del tipo en mayusculas: FINCA, HOTEL, GLAMPING, HOSTAL, ECOHOTEL
    v_key := '|' || UPPER(SUBSTR(a.tipo, 1, INSTR(a.tipo || ' ', ' ') - 1)) || '|';
    FOR i IN 1 .. v_n LOOP
      IF INSTR(v_cat(i).tipos, v_key) > 0 AND DBMS_RANDOM.VALUE < 0.60 THEN
        INSERT INTO servicio (nombre, descripcion, precio, id_alojamiento)
        VALUES (v_cat(i).nombre, v_cat(i).descr,
                ROUND(v_cat(i).precio * DBMS_RANDOM.VALUE(0.80, 1.20), -3),
                a.id_alojamiento);
      END IF;
    END LOOP;
  END LOOP;
  COMMIT;
END;
/


-- =====================================================================
-- 5. TEMPORADAS (77 tramos, del 01-ene-2024 al 11-ene-2027)
--    Fechas reales de Colombia: Semana Santa, vacaciones de mitad de anio,
--    temporada decembrina (hasta el lunes festivo de Reyes), receso escolar
--    de octubre y TODOS los puentes festivos (Ley Emiliani). Lo que no es
--    alta se reparte entre media (enero, agosto, inicio de diciembre,
--    receso de octubre) y baja (el resto).
--    Los puentes dejan muchas estadias que cruzan temporadas (decision de
--    diseno 1): quien llega un jueves y sale un martes paga noches de
--    temporada baja y noches de temporada alta.
--    Se cubre hasta el 11-ene-2027 para que una reserva de fin de 2026
--    tenga tarifa en todas sus noches.
-- =====================================================================
DECLARE
  PROCEDURE ins_temp (p_nombre VARCHAR2, p_categoria VARCHAR2, p_ini DATE, p_fin DATE) IS
  BEGIN
    INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin)
    VALUES (p_nombre, p_categoria, EXTRACT(YEAR FROM p_ini), p_ini, p_fin);
  END ins_temp;
BEGIN
  ins_temp('Temporada decembrina 2023-2024 (tramo enero)', 'ALTA', DATE '2024-01-01', DATE '2024-01-08');
  ins_temp('Temporada media de enero (desde 09-ene)', 'MEDIA', DATE '2024-01-09', DATE '2024-01-31');
  ins_temp('Temporada baja (desde 01-feb)', 'BAJA', DATE '2024-02-01', DATE '2024-03-22');
  ins_temp('Semana Santa', 'ALTA', DATE '2024-03-23', DATE '2024-03-31');
  ins_temp('Temporada baja (desde 01-abr)', 'BAJA', DATE '2024-04-01', DATE '2024-05-10');
  ins_temp('Puente Ascension', 'ALTA', DATE '2024-05-11', DATE '2024-05-13');
  ins_temp('Temporada baja (desde 14-may)', 'BAJA', DATE '2024-05-14', DATE '2024-05-31');
  ins_temp('Puente Corpus Christi', 'ALTA', DATE '2024-06-01', DATE '2024-06-03');
  ins_temp('Temporada baja (desde 04-jun)', 'BAJA', DATE '2024-06-04', DATE '2024-06-07');
  ins_temp('Puente Sagrado Corazon', 'ALTA', DATE '2024-06-08', DATE '2024-06-10');
  ins_temp('Temporada baja (desde 11-jun)', 'BAJA', DATE '2024-06-11', DATE '2024-06-14');
  ins_temp('Vacaciones de mitad de ano', 'ALTA', DATE '2024-06-15', DATE '2024-07-20');
  ins_temp('Temporada media de agosto (desde 21-jul)', 'MEDIA', DATE '2024-07-21', DATE '2024-08-16');
  ins_temp('Puente Asuncion', 'ALTA', DATE '2024-08-17', DATE '2024-08-19');
  ins_temp('Temporada media de agosto (desde 20-ago)', 'MEDIA', DATE '2024-08-20', DATE '2024-08-31');
  ins_temp('Temporada baja (desde 01-sep)', 'BAJA', DATE '2024-09-01', DATE '2024-10-04');
  ins_temp('Receso escolar de octubre', 'MEDIA', DATE '2024-10-05', DATE '2024-10-11');
  ins_temp('Puente Dia de la Raza', 'ALTA', DATE '2024-10-12', DATE '2024-10-14');
  ins_temp('Temporada baja (desde 15-oct)', 'BAJA', DATE '2024-10-15', DATE '2024-11-01');
  ins_temp('Puente Todos los Santos', 'ALTA', DATE '2024-11-02', DATE '2024-11-04');
  ins_temp('Temporada baja (desde 05-nov)', 'BAJA', DATE '2024-11-05', DATE '2024-11-08');
  ins_temp('Puente Independencia de Cartagena', 'ALTA', DATE '2024-11-09', DATE '2024-11-11');
  ins_temp('Temporada baja (desde 12-nov)', 'BAJA', DATE '2024-11-12', DATE '2024-11-30');
  ins_temp('Temporada media de diciembre (desde 01-dic)', 'MEDIA', DATE '2024-12-01', DATE '2024-12-14');
  ins_temp('Temporada decembrina 2024-2025', 'ALTA', DATE '2024-12-15', DATE '2025-01-06');
  ins_temp('Temporada media de enero (desde 07-ene)', 'MEDIA', DATE '2025-01-07', DATE '2025-01-31');
  ins_temp('Temporada baja (desde 01-feb)', 'BAJA', DATE '2025-02-01', DATE '2025-03-21');
  ins_temp('Puente San Jose', 'ALTA', DATE '2025-03-22', DATE '2025-03-24');
  ins_temp('Temporada baja (desde 25-mar)', 'BAJA', DATE '2025-03-25', DATE '2025-04-11');
  ins_temp('Semana Santa', 'ALTA', DATE '2025-04-12', DATE '2025-04-20');
  ins_temp('Temporada baja (desde 21-abr)', 'BAJA', DATE '2025-04-21', DATE '2025-05-30');
  ins_temp('Puente Ascension', 'ALTA', DATE '2025-05-31', DATE '2025-06-02');
  ins_temp('Temporada baja (desde 03-jun)', 'BAJA', DATE '2025-06-03', DATE '2025-06-13');
  ins_temp('Vacaciones de mitad de ano', 'ALTA', DATE '2025-06-14', DATE '2025-07-20');
  ins_temp('Temporada media de agosto (desde 21-jul)', 'MEDIA', DATE '2025-07-21', DATE '2025-08-15');
  ins_temp('Puente Asuncion', 'ALTA', DATE '2025-08-16', DATE '2025-08-18');
  ins_temp('Temporada media de agosto (desde 19-ago)', 'MEDIA', DATE '2025-08-19', DATE '2025-08-31');
  ins_temp('Temporada baja (desde 01-sep)', 'BAJA', DATE '2025-09-01', DATE '2025-10-03');
  ins_temp('Receso escolar de octubre', 'MEDIA', DATE '2025-10-04', DATE '2025-10-10');
  ins_temp('Puente Dia de la Raza', 'ALTA', DATE '2025-10-11', DATE '2025-10-13');
  ins_temp('Temporada baja (desde 14-oct)', 'BAJA', DATE '2025-10-14', DATE '2025-10-31');
  ins_temp('Puente Todos los Santos', 'ALTA', DATE '2025-11-01', DATE '2025-11-03');
  ins_temp('Temporada baja (desde 04-nov)', 'BAJA', DATE '2025-11-04', DATE '2025-11-14');
  ins_temp('Puente Independencia de Cartagena', 'ALTA', DATE '2025-11-15', DATE '2025-11-17');
  ins_temp('Temporada baja (desde 18-nov)', 'BAJA', DATE '2025-11-18', DATE '2025-11-30');
  ins_temp('Temporada media de diciembre (desde 01-dic)', 'MEDIA', DATE '2025-12-01', DATE '2025-12-05');
  ins_temp('Puente Velitas', 'ALTA', DATE '2025-12-06', DATE '2025-12-08');
  ins_temp('Temporada media de diciembre (desde 09-dic)', 'MEDIA', DATE '2025-12-09', DATE '2025-12-14');
  ins_temp('Temporada decembrina 2025-2026', 'ALTA', DATE '2025-12-15', DATE '2026-01-12');
  ins_temp('Temporada media de enero (desde 13-ene)', 'MEDIA', DATE '2026-01-13', DATE '2026-01-31');
  ins_temp('Temporada baja (desde 01-feb)', 'BAJA', DATE '2026-02-01', DATE '2026-03-20');
  ins_temp('Puente San Jose', 'ALTA', DATE '2026-03-21', DATE '2026-03-23');
  ins_temp('Temporada baja (desde 24-mar)', 'BAJA', DATE '2026-03-24', DATE '2026-03-27');
  ins_temp('Semana Santa', 'ALTA', DATE '2026-03-28', DATE '2026-04-05');
  ins_temp('Temporada baja (desde 06-abr)', 'BAJA', DATE '2026-04-06', DATE '2026-04-30');
  ins_temp('Puente Dia del Trabajo', 'ALTA', DATE '2026-05-01', DATE '2026-05-03');
  ins_temp('Temporada baja (desde 04-may)', 'BAJA', DATE '2026-05-04', DATE '2026-05-15');
  ins_temp('Puente Ascension', 'ALTA', DATE '2026-05-16', DATE '2026-05-18');
  ins_temp('Temporada baja (desde 19-may)', 'BAJA', DATE '2026-05-19', DATE '2026-06-05');
  ins_temp('Puente Corpus Christi', 'ALTA', DATE '2026-06-06', DATE '2026-06-08');
  ins_temp('Temporada baja (desde 09-jun)', 'BAJA', DATE '2026-06-09', DATE '2026-06-12');
  ins_temp('Vacaciones de mitad de ano', 'ALTA', DATE '2026-06-13', DATE '2026-07-20');
  ins_temp('Temporada media de agosto (desde 21-jul)', 'MEDIA', DATE '2026-07-21', DATE '2026-08-06');
  ins_temp('Puente Batalla de Boyaca', 'ALTA', DATE '2026-08-07', DATE '2026-08-09');
  ins_temp('Temporada media de agosto (desde 10-ago)', 'MEDIA', DATE '2026-08-10', DATE '2026-08-14');
  ins_temp('Puente Asuncion', 'ALTA', DATE '2026-08-15', DATE '2026-08-17');
  ins_temp('Temporada media de agosto (desde 18-ago)', 'MEDIA', DATE '2026-08-18', DATE '2026-08-31');
  ins_temp('Temporada baja (desde 01-sep)', 'BAJA', DATE '2026-09-01', DATE '2026-10-02');
  ins_temp('Receso escolar de octubre', 'MEDIA', DATE '2026-10-03', DATE '2026-10-09');
  ins_temp('Puente Dia de la Raza', 'ALTA', DATE '2026-10-10', DATE '2026-10-12');
  ins_temp('Temporada baja (desde 13-oct)', 'BAJA', DATE '2026-10-13', DATE '2026-10-30');
  ins_temp('Puente Todos los Santos', 'ALTA', DATE '2026-10-31', DATE '2026-11-02');
  ins_temp('Temporada baja (desde 03-nov)', 'BAJA', DATE '2026-11-03', DATE '2026-11-13');
  ins_temp('Puente Independencia de Cartagena', 'ALTA', DATE '2026-11-14', DATE '2026-11-16');
  ins_temp('Temporada baja (desde 17-nov)', 'BAJA', DATE '2026-11-17', DATE '2026-11-30');
  ins_temp('Temporada media de diciembre (desde 01-dic)', 'MEDIA', DATE '2026-12-01', DATE '2026-12-14');
  ins_temp('Temporada decembrina 2026-2027', 'ALTA', DATE '2026-12-15', DATE '2027-01-11');
  COMMIT;
END;
/


-- =====================================================================
-- 6. CALENDARIO: un dia por fila con su temporada.
--    CONNECT BY LEVEL genera la lista de dias. El LEFT JOIN es a proposito:
--      * si algun dia no cae en ninguna temporada, id_temporada queda NULL
--        y Oracle rechaza la fila (ORA-01400, NOT NULL)  -> detecta huecos;
--      * si un dia cae en dos temporadas, aparece dos veces y Oracle
--        rechaza el duplicado (ORA-00001, PK)            -> detecta solapes.
-- =====================================================================
INSERT INTO calendario (fecha, id_temporada)
SELECT d.fecha, t.id_temporada
  FROM (SELECT DATE '2024-01-01' + LEVEL - 1 AS fecha
          FROM dual
       CONNECT BY LEVEL <= DATE '2027-01-11' - DATE '2024-01-01' + 1) d
  LEFT JOIN temporada t
    ON d.fecha BETWEEN t.fecha_inicio AND t.fecha_fin;
COMMIT;


-- =====================================================================
-- 7. TARIFAS: una por cada combinacion habitacion x temporada (cruce).
--    precio = precio base de la habitacion x factor de la temporada
--    * Precio base: segun tipo de habitacion, tipo de alojamiento y
--      estrellas, mas una variacion propia de cada habitacion (0-14 %).
--    * Factor de temporada PROPIO DE CADA ALOJAMIENTO: en alta unos suben
--      15 % y otros hasta 60 %; en baja bajan entre 5 % y 20 %. Asi la
--      tarifa NO es un porcentaje fijo (lo pide el enunciado).
--    * Semana Santa y la temporada decembrina cuestan 10 % mas que un
--      puente cualquiera.
--    ORA_HASH convierte un ID en un numero "aleatorio" pero fijo, para que
--    el resultado sea siempre el mismo. ROUND(x, -3) redondea a miles.
-- =====================================================================
INSERT INTO tarifa (precio_noche, id_temporada, id_habitacion)
SELECT ROUND(
         -- precio base de la habitacion
         CASE h.tipo_habitacion
           WHEN 'SENCILLA' THEN 110000
           WHEN 'DOBLE'    THEN 170000
           WHEN 'SUITE'    THEN 300000
           ELSE                 260000            -- CABANA
         END
       * CASE ta.nombre
           WHEN 'Hotel'    THEN 0.85 + 0.12 * a.estrellas
           WHEN 'Glamping' THEN 1.35
           WHEN 'Hostal'   THEN 0.45
           WHEN 'Ecohotel' THEN 1.15
           ELSE                 1.00              -- Finca cafetera
         END
       * (1 + MOD(ORA_HASH(h.id_habitacion), 15) / 100)
         -- factor de la temporada, distinto para cada alojamiento
       * CASE t.categoria
           WHEN 'ALTA'  THEN 1.15 + MOD(ORA_HASH(a.id_alojamiento),      46) / 100
           WHEN 'MEDIA' THEN 1.00 + MOD(ORA_HASH(a.id_alojamiento * 7),  16) / 100
           ELSE              0.80 + MOD(ORA_HASH(a.id_alojamiento * 13), 16) / 100
         END
       * CASE WHEN t.nombre = 'Semana Santa'
                OR t.nombre LIKE 'Temporada decembrina%' THEN 1.10 ELSE 1 END
       , -3) AS precio_noche,
       t.id_temporada,
       h.id_habitacion
  FROM habitacion h
  JOIN alojamiento a       ON a.id_alojamiento = h.id_alojamiento
  JOIN tipo_alojamiento ta ON ta.id_tipo       = a.id_tipo
 CROSS JOIN temporada t;
COMMIT;


-- =====================================================================
-- 8. CLIENTES (3.000)
--    Ciudades de origen ponderadas: Bogota, Medellin y Cali aportan mas
--    turistas; cerca del 14 % son extranjeros (pasaporte o cedula de
--    extranjeria). Numeros de documento unicos por construccion.
-- =====================================================================
DECLARE
  TYPE t_txt IS TABLE OF VARCHAR2(60) INDEX BY PLS_INTEGER;
  TYPE t_ciu IS RECORD (ciudad VARCHAR2(60), depto VARCHAR2(60), pais VARCHAR2(60),
                        indicativo VARCHAR2(5), peso NUMBER);
  TYPE t_ciudades IS TABLE OF t_ciu INDEX BY PLS_INTEGER;

  v_nom   t_txt;   v_ape t_txt;   v_dom t_txt;
  v_ciu   t_ciudades;
  v_nc    PLS_INTEGER := 0;
  v_peso_total NUMBER := 0;
  v_u     NUMBER;  v_acum NUMBER;  v_c PLS_INTEGER;
  v_n1    VARCHAR2(30); v_n2 VARCHAR2(30); v_a1 VARCHAR2(30); v_a2 VARCHAR2(30);
  v_tdoc  VARCHAR2(3);  v_ndoc VARCHAR2(10); v_tel VARCHAR2(20);
  v_nombres VARCHAR2(80); v_correo VARCHAR2(100);

  PROCEDURE ciu (p_ciudad VARCHAR2, p_depto VARCHAR2, p_pais VARCHAR2, p_ind VARCHAR2, p_peso NUMBER) IS
    v_r t_ciu;
  BEGIN
    v_r.ciudad := p_ciudad;  v_r.depto := p_depto;  v_r.pais := p_pais;
    v_r.indicativo := p_ind; v_r.peso := p_peso;
    v_nc := v_nc + 1;
    v_ciu(v_nc) := v_r;
    v_peso_total := v_peso_total + p_peso;
  END ciu;

  PROCEDURE lista (p_lista IN OUT t_txt, p_csv VARCHAR2) IS
    v_resto VARCHAR2(4000) := p_csv || ',';
    v_pos   PLS_INTEGER;
  BEGIN
    LOOP
      -- NVL: cuando v_resto queda vacio, Oracle lo trata como NULL e INSTR
      -- devuelve NULL (no 0); sin NVL el ciclo nunca terminaria.
      v_pos := NVL(INSTR(v_resto, ','), 0);
      EXIT WHEN v_pos = 0;
      p_lista(p_lista.COUNT + 1) := TRIM(SUBSTR(v_resto, 1, v_pos - 1));
      v_resto := SUBSTR(v_resto, v_pos + 1);
    END LOOP;
  END lista;
BEGIN
  DBMS_RANDOM.SEED(20261006);

  lista(v_nom, 'Juan,Maria,Carlos,Ana,Luis,Laura,Andres,Camila,Jorge,Valentina,Diego,Daniela,' ||
               'Felipe,Natalia,Santiago,Paula,Alejandro,Sofia,Sebastian,Juliana,Ricardo,Carolina,' ||
               'Mateo,Isabella,Julian,Manuela,Oscar,Lucia,Hernan,Gloria,David,Monica,Esteban,Diana,' ||
               'Mauricio,Adriana,Nicolas,Sara,Fernando,Patricia');
  lista(v_ape, 'Garcia,Rodriguez,Martinez,Lopez,Gonzalez,Hernandez,Perez,Sanchez,Ramirez,Torres,' ||
               'Gomez,Diaz,Vargas,Rojas,Moreno,Jimenez,Castro,Ortiz,Ruiz,Alvarez,Giraldo,Restrepo,' ||
               'Osorio,Cardona,Mejia,Arango,Valencia,Henao,Ospina,Zapata,Echeverri,Velez,Quintero,' ||
               'Londono,Marin,Salazar,Agudelo,Botero,Duque,Correa');
  lista(v_dom, 'gmail.com,hotmail.com,outlook.com,yahoo.com');

  --  ciudad              departamento / estado      pais              ind.  peso
  ciu('Bogota',          'Bogota D.C.',             'Colombia',       '57', 22);
  ciu('Medellin',        'Antioquia',               'Colombia',       '57', 13);
  ciu('Cali',            'Valle del Cauca',         'Colombia',       '57', 10);
  ciu('Pereira',         'Risaralda',               'Colombia',       '57',  7);
  ciu('Armenia',         'Quindio',                 'Colombia',       '57',  5);
  ciu('Manizales',       'Caldas',                  'Colombia',       '57',  5);
  ciu('Ibague',          'Tolima',                  'Colombia',       '57',  4);
  ciu('Barranquilla',    'Atlantico',               'Colombia',       '57',  3);
  ciu('Bucaramanga',     'Santander',               'Colombia',       '57',  3);
  ciu('Cartagena',       'Bolivar',                 'Colombia',       '57',  2);
  ciu('Cucuta',          'Norte de Santander',      'Colombia',       '57',  2);
  ciu('Villavicencio',   'Meta',                    'Colombia',       '57',  2);
  ciu('Neiva',           'Huila',                   'Colombia',       '57',  2);
  ciu('Tulua',           'Valle del Cauca',         'Colombia',       '57',  2);
  ciu('Calarca',         'Quindio',                 'Colombia',       '57',  1);
  ciu('Dosquebradas',    'Risaralda',               'Colombia',       '57',  1);
  ciu('Popayan',         'Cauca',                   'Colombia',       '57',  1);
  ciu('Pasto',           'Narino',                  'Colombia',       '57',  1);
  ciu('Miami',           'Florida',                 'Estados Unidos', '1',   3);
  ciu('Nueva York',      'Nueva York',              'Estados Unidos', '1',   2);
  ciu('Madrid',          'Comunidad de Madrid',     'Espana',         '34',  2);
  ciu('Ciudad de Mexico','Ciudad de Mexico',        'Mexico',         '52',  1);
  ciu('Buenos Aires',    'Buenos Aires',            'Argentina',      '54',  1);
  ciu('Toronto',         'Ontario',                 'Canada',         '1',   1);
  ciu('Berlin',          'Berlin',                  'Alemania',       '49',  1);
  ciu('Paris',           'Ile-de-France',           'Francia',        '33',  1);
  ciu('Quito',           'Pichincha',               'Ecuador',        '593', 1);
  ciu('Santiago',        'Region Metropolitana',    'Chile',          '56',  1);

  FOR i IN 1 .. 3000 LOOP
    -- Ciudad de origen segun su peso (seleccion ponderada)
    v_u := DBMS_RANDOM.VALUE * v_peso_total;
    v_acum := 0; v_c := 0;
    LOOP
      v_c := v_c + 1;
      v_acum := v_acum + v_ciu(v_c).peso;
      EXIT WHEN v_acum >= v_u OR v_c = v_nc;
    END LOOP;

    v_n1 := v_nom(TRUNC(DBMS_RANDOM.VALUE(1, v_nom.COUNT + 1)));
    v_n2 := v_nom(TRUNC(DBMS_RANDOM.VALUE(1, v_nom.COUNT + 1)));
    v_a1 := v_ape(TRUNC(DBMS_RANDOM.VALUE(1, v_ape.COUNT + 1)));
    v_a2 := v_ape(TRUNC(DBMS_RANDOM.VALUE(1, v_ape.COUNT + 1)));

    -- Documento: CC para colombianos (8 o 10 digitos), PAS o CE para extranjeros.
    -- El termino i * salto garantiza que no se repita ningun numero.
    IF v_ciu(v_c).pais = 'Colombia' THEN
      v_tdoc := 'CC';
      IF DBMS_RANDOM.VALUE < 0.5 THEN
        v_ndoc := TO_CHAR(10000000 + i * 29000 + TRUNC(DBMS_RANDOM.VALUE(0, 999)));
      ELSE
        v_ndoc := TO_CHAR(1000000000 + i * 190000 + TRUNC(DBMS_RANDOM.VALUE(0, 9999)));
      END IF;
      v_tel := TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(3000000000, 3249999999)));
    ELSE
      IF DBMS_RANDOM.VALUE < 0.85 THEN
        v_tdoc := 'PAS';
        v_ndoc := CHR(65 + MOD(i, 26)) || CHR(65 + MOD(i * 7, 26)) || TO_CHAR(1000000 + i * 97);
      ELSE
        v_tdoc := 'CE';
        v_ndoc := TO_CHAR(100000 + i * 31);
      END IF;
      v_tel := '+' || v_ciu(v_c).indicativo || ' ' || TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(200000000, 999999999)));
    END IF;

    -- Nombre (30 % con segundo nombre) y correo unico (lleva el consecutivo i).
    -- Se calculan en PL/SQL ANTES del INSERT: dentro de una sentencia SQL no se
    -- puede indexar una lista PL/SQL con una funcion como DBMS_RANDOM (PLS-00425).
    IF DBMS_RANDOM.VALUE < 0.3 AND v_n2 <> v_n1 THEN
      v_nombres := v_n1 || ' ' || v_n2;
    ELSE
      v_nombres := v_n1;
    END IF;
    v_correo := LOWER(v_n1 || '.' || v_a1) || i || '@' ||
                v_dom(TRUNC(DBMS_RANDOM.VALUE(1, v_dom.COUNT + 1)));

    INSERT INTO cliente (tipo_documento, numero_documento, nombres, apellidos, correo, telefono,
                         ciudad_origen, departamento_origen, pais_origen)
    VALUES (v_tdoc, v_ndoc, v_nombres, v_a1 || ' ' || v_a2, v_correo, v_tel,
            v_ciu(v_c).ciudad, v_ciu(v_c).depto, v_ciu(v_c).pais);
  END LOOP;
  COMMIT;
END;
/


-- =====================================================================
-- 9. USUARIOS DEL SISTEMA (12): 3 administradores y 9 encargados.
--    Hay al menos un encargado por cada tipo de alojamiento.
--    Regla D20: el ADMIN no tiene alojamiento; el ENCARGADO tiene uno.
-- =====================================================================
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('admin.cgiraldo', 'Cesar Arturo Giraldo Velez', 'cgiraldo@turismouq.co', 'ADMIN', 'S', DATE '2023-12-01', NULL);
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('admin.mlondono', 'Marta Londono Arias', 'mlondono@turismouq.co', 'ADMIN', 'S', DATE '2023-12-01', NULL);
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('admin.jtorres', 'Julian Torres Mejia', 'jtorres@turismouq.co', 'ADMIN', 'N', DATE '2024-02-15', NULL);

INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.mirador', 'Laura Restrepo Gil', 'lrestrepo@turismouq.co', 'ENCARGADO', 'S', DATE '2023-12-10',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador del Eje'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.plaza', 'Andres Cardona Rios', 'acardona@turismouq.co', 'ENCARGADO', 'S', DATE '2023-12-10',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Plaza Cafetera'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.esperanza', 'Gloria Henao Mejia', 'ghenao@turismouq.co', 'ENCARGADO', 'S', DATE '2023-12-12',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Esperanza'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.villamaria', 'Hernan Osorio Duque', 'hosorio@turismouq.co', 'ENCARGADO', 'S', DATE '2024-01-05',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Villa Maria'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.palmas', 'Camila Zapata Botero', 'czapata@turismouq.co', 'ENCARGADO', 'S', DATE '2023-12-15',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Valle de las Palmas'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.bambu', 'Felipe Arango Marin', 'farango@turismouq.co', 'ENCARGADO', 'S', DATE '2024-03-01',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Bambu y Luna'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.palmacera', 'Sofia Quintero Ospina', 'squintero@turismouq.co', 'ENCARGADO', 'S', DATE '2023-12-20',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Palma de Cera'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.estacion', 'Diego Salazar Correa', 'dsalazar@turismouq.co', 'ENCARGADO', 'N', DATE '2024-01-20',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal La Estacion'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, rol, activo, fecha_creacion, id_alojamiento)
  VALUES ('enc.rioquindio', 'Natalia Echeverri Velez', 'necheverri@turismouq.co', 'ENCARGADO', 'S', DATE '2023-12-18',
          (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Rio Quindio'));
COMMIT;


-- =====================================================================
-- 10. RESERVAS (26.000), SUS HABITACIONES Y SUS SERVICIOS
--     Para cada reserva el generador:
--       1. Escoge la fecha de check-in con estacionalidad: acepta el dia
--          con una probabilidad mayor en temporada alta, en viernes y
--          sabado, y en 2026 (la plataforma crece cada anio).
--       2. Escoge cuantas noches (estadias mas largas en temporada alta).
--       3. Escoge el alojamiento segun su "popularidad" (municipio, tipo,
--          tamano y un factor propio): reparto desigual a proposito.
--       4. Decide el estado segun las fechas frente al corte (31-dic-2026).
--       5. Escoge 1 a 4 habitaciones LIBRES (no solapadas con otra reserva
--          activa). Algunas lineas llegan un dia despues que el resto del
--          grupo (decision de diseno 2). Las canceladas no ocupan.
--       6. Calcula el valor de cada habitacion NOCHE POR NOCHE con la
--          tarifa vigente de cada dia (JOIN calendario + tarifa) y lo
--          guarda congelado en valor_estadia (decision de diseno 1).
--       7. Agrega servicios del alojamiento con cantidades coherentes.
--     Se generan 26.000 (no 25.000) para tener margen sobre el minimo.
-- =====================================================================
DECLARE
  c_base      CONSTANT DATE := DATE '2024-01-01';    -- primer dia del calendario
  c_hoy       CONSTANT DATE := DATE '2026-12-31';    -- fecha de corte del generador
  c_ultimo_ci CONSTANT DATE := DATE '2026-12-31';    -- ultimo check-in posible
  c_total     CONSTANT PLS_INTEGER := 26000;

  TYPE t_num  IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;
  TYPE t_txt  IS TABLE OF VARCHAR2(10) INDEX BY PLS_INTEGER;
  TYPE t_bool IS TABLE OF BOOLEAN      INDEX BY PLS_INTEGER;

  -- Categoria (ALTA/MEDIA/BAJA) de cada dia; el indice es dias desde c_base
  v_cat     t_txt;
  -- Alojamientos: id, peso acumulado y posicion de sus habitaciones y servicios
  a_id      t_num;  a_peso    t_num;
  a_hab_ini t_num;  a_hab_cnt t_num;
  a_srv_ini t_num;  a_srv_cnt t_num;
  v_peso_total NUMBER := 0;
  -- Habitaciones y servicios en listas planas
  r_id t_num;  r_cap t_num;
  s_id t_num;  s_precio t_num;  s_clase t_txt;   -- D = desayuno, T = transporte, O = otro
  -- Clientes
  cl_id t_num;
  -- Ocupacion: clave = id_habitacion * 2000 + dia  ->  TRUE si esta ocupada
  ocupado t_bool;

  -- Lineas de la reserva en construccion
  l_hab t_num;  l_cap t_num;  l_ci t_num;
  v_lineas PLS_INTEGER;

  v_creadas  PLS_INTEGER := 0;
  v_intentos PLS_INTEGER := 0;
  i PLS_INTEGER := 0;  k PLS_INTEGER := 0;  s PLS_INTEGER := 0;
  v_u NUMBER;  v_p NUMBER;  v_peso NUMBER;
  v_ci_off PLS_INTEGER;  v_co_off PLS_INTEGER;  v_lci PLS_INTEGER;
  v_ci DATE;  v_co DATE;  v_fr DATE;  v_fc DATE;  v_lim DATE;  v_ini DATE;  v_fin DATE;
  v_noches PLS_INTEGER;  v_a PLS_INTEGER;  v_nhab PLS_INTEGER;  v_x PLS_INTEGER;
  v_estado VARCHAR2(12);
  v_ok BOOLEAN;  v_rep BOOLEAN;
  v_cli NUMBER;  v_id_res NUMBER;  v_val NUMBER;  v_hu NUMBER;  v_huesp NUMBER;  v_cant NUMBER;

  FUNCTION clave (p_hab NUMBER, p_dia PLS_INTEGER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN p_hab * 2000 + p_dia;
  END clave;

  -- TRUE si la habitacion esta libre todas las noches de [p_ini, p_fin)
  FUNCTION libre (p_hab NUMBER, p_ini PLS_INTEGER, p_fin PLS_INTEGER) RETURN BOOLEAN IS
  BEGIN
    FOR d IN p_ini .. p_fin - 1 LOOP
      IF ocupado.EXISTS(clave(p_hab, d)) THEN
        RETURN FALSE;
      END IF;
    END LOOP;
    RETURN TRUE;
  END libre;

  PROCEDURE marcar (p_hab NUMBER, p_ini PLS_INTEGER, p_fin PLS_INTEGER) IS
  BEGIN
    FOR d IN p_ini .. p_fin - 1 LOOP
      ocupado(clave(p_hab, d)) := TRUE;
    END LOOP;
  END marcar;

BEGIN
  DBMS_RANDOM.SEED(20261007);

  -- ---- Carga en memoria: categoria de cada dia ----
  FOR d IN (SELECT c.fecha - c_base AS dia, t.categoria
              FROM calendario c JOIN temporada t ON t.id_temporada = c.id_temporada)
  LOOP
    v_cat(d.dia) := d.categoria;
  END LOOP;

  -- ---- Carga en memoria: alojamientos con su popularidad, habitaciones y servicios ----
  FOR a IN (SELECT al.id_alojamiento, m.nombre AS municipio, ta.nombre AS tipo,
                   (SELECT COUNT(*) FROM habitacion h WHERE h.id_alojamiento = al.id_alojamiento) AS nhab
              FROM alojamiento al
              JOIN municipio m         ON m.id_municipio = al.id_municipio
              JOIN tipo_alojamiento ta ON ta.id_tipo     = al.id_tipo
             ORDER BY al.id_alojamiento)
  LOOP
    i := i + 1;
    a_id(i) := a.id_alojamiento;
    v_peso := CASE a.municipio
                WHEN 'Salento'    THEN 1.6  WHEN 'Filandia'   THEN 1.3  WHEN 'Montenegro' THEN 1.2
                WHEN 'Quimbaya'   THEN 1.1  WHEN 'Armenia'    THEN 1.0  WHEN 'Calarca'    THEN 0.8
                WHEN 'La Tebaida' THEN 0.8  WHEN 'Circasia'   THEN 0.7  WHEN 'Buenavista' THEN 0.6
                WHEN 'Pijao'      THEN 0.4  ELSE 0.3
              END
            * CASE a.tipo
                WHEN 'Glamping' THEN 1.3  WHEN 'Finca cafetera' THEN 1.2
                WHEN 'Hostal'   THEN 0.9  ELSE 1.0
              END
            * POWER(a.nhab, 0.6)                  -- mas habitaciones, mas reservas
            * DBMS_RANDOM.VALUE(0.5, 1.5);        -- factor propio del alojamiento
    v_peso_total := v_peso_total + v_peso;
    a_peso(i) := v_peso_total;                    -- peso ACUMULADO

    a_hab_ini(i) := k + 1;
    FOR h IN (SELECT id_habitacion, capacidad FROM habitacion
               WHERE id_alojamiento = a.id_alojamiento ORDER BY id_habitacion)
    LOOP
      k := k + 1;  r_id(k) := h.id_habitacion;  r_cap(k) := h.capacidad;
    END LOOP;
    a_hab_cnt(i) := k - a_hab_ini(i) + 1;

    a_srv_ini(i) := s + 1;
    FOR sv IN (SELECT id_servicio, precio, nombre FROM servicio
                WHERE id_alojamiento = a.id_alojamiento ORDER BY id_servicio)
    LOOP
      s := s + 1;  s_id(s) := sv.id_servicio;  s_precio(s) := sv.precio;
      s_clase(s) := CASE WHEN sv.nombre LIKE 'Desayuno%'   THEN 'D'
                         WHEN sv.nombre LIKE 'Transporte%' THEN 'T' ELSE 'O' END;
    END LOOP;
    a_srv_cnt(i) := s - a_srv_ini(i) + 1;
  END LOOP;

  SELECT id_cliente BULK COLLECT INTO cl_id FROM cliente ORDER BY id_cliente;

  -- ---- Generacion ----
  WHILE v_creadas < c_total AND v_intentos < 2000000 LOOP
    v_intentos := v_intentos + 1;

    -- 1. Fecha de check-in con estacionalidad (muestreo por rechazo)
    LOOP
      v_ci_off := TRUNC(DBMS_RANDOM.VALUE(0, c_ultimo_ci - c_base + 1));
      v_ci := c_base + v_ci_off;
      v_p := CASE v_cat(v_ci_off) WHEN 'ALTA' THEN 1 WHEN 'MEDIA' THEN 0.55 ELSE 0.30 END
           * CASE EXTRACT(YEAR FROM v_ci) WHEN 2024 THEN 0.75 WHEN 2025 THEN 0.90 ELSE 1 END
           -- dia de la semana: 0 = lunes ... 6 = domingo (el 01-ene-2024 fue lunes)
           * CASE MOD(v_ci_off, 7) WHEN 4 THEN 1.00 WHEN 5 THEN 0.85 WHEN 3 THEN 0.65
                                   WHEN 6 THEN 0.50 WHEN 1 THEN 0.40 ELSE 0.45 END
           -- lo futuro todavia no se ha reservado completo
           * CASE WHEN v_ci > c_hoy THEN 0.55 ELSE 1 END;
      EXIT WHEN DBMS_RANDOM.VALUE < v_p;
    END LOOP;

    -- 2. Numero de noches
    v_u := DBMS_RANDOM.VALUE;
    IF v_cat(v_ci_off) = 'ALTA' THEN
      v_noches := CASE WHEN v_u < 0.10 THEN 1 WHEN v_u < 0.35 THEN 2 WHEN v_u < 0.60 THEN 3
                       WHEN v_u < 0.75 THEN 4 WHEN v_u < 0.87 THEN 5 WHEN v_u < 0.95 THEN 6 ELSE 7 END;
    ELSE
      v_noches := CASE WHEN v_u < 0.25 THEN 1 WHEN v_u < 0.63 THEN 2 WHEN v_u < 0.83 THEN 3
                       WHEN v_u < 0.92 THEN 4 WHEN v_u < 0.97 THEN 5 ELSE 6 END;
    END IF;
    v_co_off := v_ci_off + v_noches;
    v_co := c_base + v_co_off;

    -- 3. Alojamiento segun popularidad (seleccion ponderada con pesos acumulados)
    v_u := DBMS_RANDOM.VALUE * v_peso_total;
    v_a := 1;
    WHILE a_peso(v_a) < v_u LOOP
      v_a := v_a + 1;
    END LOOP;

    -- 4. Estado segun las fechas frente a hoy
    v_u := DBMS_RANDOM.VALUE;
    IF v_co <= c_hoy THEN                      -- estadia ya terminada
      v_estado := CASE WHEN v_u < 0.88 THEN 'COMPLETADA' ELSE 'CANCELADA' END;
    ELSIF v_ci <= c_hoy THEN                   -- huesped alojado hoy
      v_estado := 'CONFIRMADA';
    ELSE                                       -- estadia futura
      v_estado := CASE WHEN v_u < 0.55 THEN 'CONFIRMADA'
                       WHEN v_u < 0.88 THEN 'PENDIENTE' ELSE 'CANCELADA' END;
    END IF;

    -- 5. Habitaciones libres (1 a 4)
    v_u := DBMS_RANDOM.VALUE;
    v_nhab := CASE WHEN v_u < 0.84 THEN 1 WHEN v_u < 0.95 THEN 2 WHEN v_u < 0.99 THEN 3 ELSE 4 END;
    IF a_hab_cnt(v_a) < 3 THEN v_nhab := 1; END IF;
    v_nhab := LEAST(v_nhab, a_hab_cnt(v_a));

    v_lineas := 0;
    FOR j IN 1 .. v_nhab LOOP
      v_lci := v_ci_off;
      IF j > 1 AND v_noches >= 2 AND DBMS_RANDOM.VALUE < 0.15 THEN
        v_lci := v_ci_off + 1;                 -- este integrante llega un dia despues
      END IF;
      v_ok := FALSE;
      FOR intento IN 1 .. 8 LOOP
        v_x := a_hab_ini(v_a) + TRUNC(DBMS_RANDOM.VALUE(0, a_hab_cnt(v_a)));
        v_rep := FALSE;
        FOR y IN 1 .. v_lineas LOOP
          IF l_hab(y) = r_id(v_x) THEN v_rep := TRUE; END IF;
        END LOOP;
        IF NOT v_rep AND (v_estado = 'CANCELADA' OR libre(r_id(v_x), v_lci, v_co_off)) THEN
          v_lineas := v_lineas + 1;
          l_hab(v_lineas) := r_id(v_x);  l_cap(v_lineas) := r_cap(v_x);  l_ci(v_lineas) := v_lci;
          v_ok := TRUE;
          EXIT;
        END IF;
      END LOOP;
      EXIT WHEN NOT v_ok AND j = 1;            -- ni una habitacion libre: se descarta
    END LOOP;

    IF v_lineas > 0 THEN
      -- Las reservas activas ocupan sus habitaciones; las canceladas no (regla D24)
      IF v_estado <> 'CANCELADA' THEN
        FOR y IN 1 .. v_lineas LOOP
          marcar(l_hab(y), l_ci(y), v_co_off);
        END LOOP;
      END IF;

      -- 6. Fecha en que se hizo la reserva (con mas anticipacion en temporada alta)
      v_fr := v_ci - CASE WHEN v_cat(v_ci_off) = 'ALTA' THEN TRUNC(DBMS_RANDOM.VALUE(5, 121))
                          ELSE TRUNC(DBMS_RANDOM.VALUE(0, 61)) END;
      v_fr := LEAST(GREATEST(v_fr, c_base), c_hoy);

      -- 7. Fecha de cancelacion: entre la reserva y el check-in, nunca despues de hoy.
      --    60 % cancela con 5 o mas dias de anticipacion (tiene reembolso).
      v_fc := NULL;
      IF v_estado = 'CANCELADA' THEN
        v_lim := LEAST(v_ci - 5, c_hoy);
        IF v_lim >= v_fr AND DBMS_RANDOM.VALUE < 0.60 THEN
          v_fc := v_fr + TRUNC(DBMS_RANDOM.VALUE(0, v_lim - v_fr + 1));
        ELSE
          v_ini := GREATEST(v_fr, v_ci - 4);
          v_fin := LEAST(v_ci, c_hoy);
          IF v_fin >= v_ini THEN
            v_fc := v_ini + TRUNC(DBMS_RANDOM.VALUE(0, v_fin - v_ini + 1));
          ELSE
            v_fc := v_fr + TRUNC(DBMS_RANDOM.VALUE(0, c_hoy - v_fr + 1));
          END IF;
        END IF;
      END IF;

      -- 8. Cliente: unos pocos clientes concentran muchas reservas (asimetria)
      v_cli := cl_id(1 + TRUNC(cl_id.COUNT * POWER(DBMS_RANDOM.VALUE, 1.7)));

      INSERT INTO reserva (fecha_reserva, fecha_checkin, fecha_checkout, estado,
                           fecha_cancelacion, id_alojamiento, id_cliente)
      VALUES (v_fr, v_ci, v_co, v_estado, v_fc, a_id(v_a), v_cli)
      RETURNING id_reserva INTO v_id_res;

      -- 9. Lineas de habitacion con su valor calculado noche por noche
      v_huesp := 0;
      FOR y IN 1 .. v_lineas LOOP
        v_hu := CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN l_cap(y)
                     ELSE TRUNC(DBMS_RANDOM.VALUE(1, l_cap(y) + 1)) END;

        SELECT SUM(t.precio_noche)
          INTO v_val
          FROM calendario c
          JOIN tarifa t ON t.id_temporada = c.id_temporada
         WHERE t.id_habitacion = l_hab(y)
           AND c.fecha >= c_base + l_ci(y)
           AND c.fecha <  v_co;

        INSERT INTO reserva_habitacion (fecha_checkin, fecha_checkout, num_huespedes,
                                        valor_estadia, id_reserva, id_habitacion)
        VALUES (c_base + l_ci(y), v_co, v_hu, v_val, v_id_res, l_hab(y));
        v_huesp := v_huesp + v_hu;
      END LOOP;

      -- 10. Servicios del alojamiento (cada uno con 55 % de probabilidad)
      FOR z IN a_srv_ini(v_a) .. a_srv_ini(v_a) + a_srv_cnt(v_a) - 1 LOOP
        IF DBMS_RANDOM.VALUE < 0.55 THEN
          v_cant := CASE s_clase(z)
                      WHEN 'D' THEN LEAST(v_huesp * v_noches, 999)       -- desayunos: huespedes x noches
                      WHEN 'T' THEN TRUNC(DBMS_RANDOM.VALUE(1, 3))       -- traslado: ida y/o vuelta
                      ELSE          TRUNC(DBMS_RANDOM.VALUE(1, v_huesp + 1))
                    END;
          INSERT INTO reserva_servicio (cantidad, precio_unitario, id_reserva, id_servicio)
          VALUES (v_cant, s_precio(z), v_id_res, s_id(z));
        END IF;
      END LOOP;

      v_creadas := v_creadas + 1;
      IF MOD(v_creadas, 5000) = 0 THEN
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Reservas creadas: ' || v_creadas);
      END IF;
    END IF;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Total reservas: ' || v_creadas || ' (intentos: ' || v_intentos || ')');
END;
/


-- =====================================================================
-- 11. GARANTIA DE VOLUMEN: al menos 40.000 lineas de RESERVA_SERVICIO.
--     Si el azar dejo menos, agrega servicios a reservas activas escogidas
--     al azar (un servicio que esa reserva aun no tenga). Corre ANTES de
--     los pagos, para que los pagos cubran tambien estos servicios.
-- =====================================================================
DECLARE
  TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_ids  t_num;
  v_id   NUMBER;
  v_n    NUMBER;
  v_vuelta PLS_INTEGER := 0;
BEGIN
  DBMS_RANDOM.SEED(20261008);
  SELECT COUNT(*) INTO v_n FROM reserva_servicio;
  SELECT id_reserva BULK COLLECT INTO v_ids FROM reserva WHERE estado <> 'CANCELADA';

  WHILE v_n < 40000 AND v_vuelta < 200000 LOOP
    v_vuelta := v_vuelta + 1;
    v_id := v_ids(TRUNC(DBMS_RANDOM.VALUE(1, v_ids.COUNT + 1)));   -- reserva al azar
    INSERT INTO reserva_servicio (cantidad, precio_unitario, id_reserva, id_servicio)
    SELECT 1, s.precio, r.id_reserva, s.id_servicio
      FROM reserva r
      JOIN servicio s ON s.id_alojamiento = r.id_alojamiento
     WHERE r.id_reserva = v_id
       AND NOT EXISTS (SELECT 1 FROM reserva_servicio rs
                        WHERE rs.id_reserva = r.id_reserva AND rs.id_servicio = s.id_servicio)
       AND ROWNUM = 1;
    v_n := v_n + SQL%ROWCOUNT;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Lineas de servicios: ' || v_n);
END;
/


-- =====================================================================
-- 12. PAGOS
--     total de la reserva = suma de estadias + suma de servicios (D11)
--     * COMPLETADA: pago unico (a veces precedido de un intento FALLIDO)
--                   o anticipo al reservar + saldo al llegar.
--     * CONFIRMADA: si el huesped ya llego, anticipo + saldo pagados;
--                   si es futura, anticipo EXITOSO y saldo PENDIENTE
--                   fechado el dia del check-in (regla D25).
--     * PENDIENTE : la mitad tiene un pago PSE aun PENDIENTE.
--     * CANCELADA : el 70 % alcanzo a pagar anticipo. Con 5 o mas dias de
--                   anticipacion se le reembolsa el 80 % (regla D14): el
--                   reembolso es un pago nuevo REEMBOLSADO (regla D15).
-- =====================================================================
DECLARE
  c_hoy CONSTANT DATE := DATE '2026-12-31';
  v_ant  NUMBER;  v_fecha DATE;  v_met VARCHAR2(20);

  -- Metodo de pago al azar; el efectivo solo se usa al llegar al alojamiento
  FUNCTION metodo (p_permite_efectivo BOOLEAN) RETURN VARCHAR2 IS
    v_u NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    RETURN CASE WHEN v_u < 0.30 THEN 'TARJETA_CREDITO'
                WHEN v_u < 0.55 THEN 'PSE'
                WHEN v_u < 0.75 THEN 'TRANSFERENCIA'
                WHEN v_u < 0.90 THEN 'TARJETA_DEBITO'
                WHEN p_permite_efectivo THEN 'EFECTIVO'
                ELSE 'TARJETA_CREDITO' END;
  END metodo;

  PROCEDURE pagar (p_res NUMBER, p_fecha DATE, p_monto NUMBER, p_metodo VARCHAR2, p_estado VARCHAR2) IS
  BEGIN
    INSERT INTO pago (fecha_pago, monto, metodo, estado, id_reserva)
    VALUES (p_fecha, p_monto, p_metodo, p_estado, p_res);
  END pagar;
BEGIN
  DBMS_RANDOM.SEED(20261009);

  FOR r IN (SELECT re.id_reserva, re.fecha_reserva, re.fecha_checkin, re.fecha_cancelacion, re.estado,
                   (SELECT SUM(rh.valor_estadia) FROM reserva_habitacion rh
                     WHERE rh.id_reserva = re.id_reserva)
                 + NVL((SELECT SUM(rs.cantidad * rs.precio_unitario) FROM reserva_servicio rs
                         WHERE rs.id_reserva = re.id_reserva), 0) AS total
              FROM reserva re
             ORDER BY re.id_reserva)
  LOOP
    -- Anticipo entre 30 % y 50 % del total, redondeado a miles
    v_ant := ROUND(r.total * DBMS_RANDOM.VALUE(0.30, 0.50), -3);

    IF r.estado = 'COMPLETADA' THEN
      IF DBMS_RANDOM.VALUE < 0.5 THEN
        -- Pago unico, al reservar o al llegar
        v_fecha := CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN r.fecha_reserva ELSE r.fecha_checkin END;
        v_met := metodo(v_fecha = r.fecha_checkin);
        IF DBMS_RANDOM.VALUE < 0.06 THEN
          pagar(r.id_reserva, v_fecha, r.total, v_met, 'FALLIDO');   -- primer intento rechazado
          v_met := metodo(v_fecha = r.fecha_checkin);
        END IF;
        pagar(r.id_reserva, v_fecha, r.total, v_met, 'EXITOSO');
      ELSE
        -- Anticipo + saldo
        pagar(r.id_reserva, r.fecha_reserva, v_ant,           metodo(FALSE), 'EXITOSO');
        pagar(r.id_reserva, r.fecha_checkin, r.total - v_ant, metodo(TRUE),  'EXITOSO');
      END IF;

    ELSIF r.estado = 'CONFIRMADA' THEN
      IF r.fecha_checkin <= c_hoy THEN
        pagar(r.id_reserva, r.fecha_reserva, v_ant,           metodo(FALSE), 'EXITOSO');
        pagar(r.id_reserva, r.fecha_checkin, r.total - v_ant, metodo(TRUE),  'EXITOSO');
      ELSIF DBMS_RANDOM.VALUE < 0.3 THEN
        pagar(r.id_reserva, r.fecha_reserva, r.total, metodo(FALSE), 'EXITOSO');
      ELSE
        pagar(r.id_reserva, r.fecha_reserva, v_ant,           metodo(FALSE), 'EXITOSO');
        pagar(r.id_reserva, r.fecha_checkin, r.total - v_ant, metodo(TRUE),  'PENDIENTE');
      END IF;

    ELSIF r.estado = 'PENDIENTE' THEN
      IF DBMS_RANDOM.VALUE < 0.5 THEN
        pagar(r.id_reserva, r.fecha_reserva, v_ant, 'PSE', 'PENDIENTE');
      END IF;

    ELSE  -- CANCELADA
      IF DBMS_RANDOM.VALUE < 0.7 THEN
        v_met := metodo(FALSE);
        pagar(r.id_reserva, r.fecha_reserva, v_ant, v_met, 'EXITOSO');
        IF r.fecha_checkin - r.fecha_cancelacion >= 5 THEN
          pagar(r.id_reserva, r.fecha_cancelacion, ROUND(v_ant * 0.8, 2), v_met, 'REEMBOLSADO');
        END IF;
      END IF;
    END IF;
  END LOOP;
  COMMIT;
END;
/


-- =====================================================================
-- 13. RESENAS: 45 % de las reservas COMPLETADAS (minimo exigido: 40 %).
--     Cada alojamiento tiene una "calidad" propia entre 3.0 y 4.8 y cada
--     resena la varia al azar: hay alojamientos muy bien calificados y
--     otros flojos (asimetria). La fecha es posterior al check-out y
--     nunca posterior a hoy (regla D17). 35 % sin comentario (opcional).
-- =====================================================================
DECLARE
  c_hoy  CONSTANT DATE := DATE '2026-12-31';
  v_cal  NUMBER;
  v_com  VARCHAR2(500);
  v_n    PLS_INTEGER;
BEGIN
  DBMS_RANDOM.SEED(20261010);
  FOR r IN (SELECT re.id_reserva, re.fecha_checkout,
                   3.0 + MOD(ORA_HASH(re.id_alojamiento * 31), 19) / 10 AS calidad
              FROM reserva re
             WHERE re.estado = 'COMPLETADA'
             ORDER BY re.id_reserva)
  LOOP
    IF DBMS_RANDOM.VALUE < 0.45 THEN
      v_cal := GREATEST(1, LEAST(5, ROUND(r.calidad + DBMS_RANDOM.NORMAL * 0.9)));
      v_n   := TRUNC(DBMS_RANDOM.VALUE(1, 4));
      v_com := NULL;
      IF DBMS_RANDOM.VALUE < 0.65 THEN
        v_com := CASE v_cal
          WHEN 5 THEN CASE v_n WHEN 1 THEN 'Excelente experiencia, volveremos sin duda'
                               WHEN 2 THEN 'El paisaje cafetero es espectacular'
                               ELSE        'Atencion de primera, todo impecable' END
          WHEN 4 THEN CASE v_n WHEN 1 THEN 'Muy buena estadia, lo recomiendo'
                               WHEN 2 THEN 'Buena relacion calidad precio'
                               ELSE        'Lindo lugar, el desayuno puede mejorar' END
          WHEN 3 THEN CASE v_n WHEN 1 THEN 'Aceptable, pero el servicio puede mejorar'
                               WHEN 2 THEN 'Cumple, nada especial'
                               ELSE        'Bien ubicado pero algo ruidoso' END
          WHEN 2 THEN CASE v_n WHEN 1 THEN 'La habitacion no correspondia a las fotos'
                               WHEN 2 THEN 'Mucho ruido en la noche'
                               ELSE        'Falta mantenimiento en las instalaciones' END
          ELSE        CASE v_n WHEN 1 THEN 'Muy mala experiencia'
                               WHEN 2 THEN 'No lo recomiendo'
                               ELSE        'Cobros adicionales no informados' END
        END;
      END IF;
      INSERT INTO resena (calificacion, comentario, fecha_resena, id_reserva)
      VALUES (v_cal, v_com,
              LEAST(r.fecha_checkout + TRUNC(DBMS_RANDOM.VALUE(0, 15)), c_hoy),
              r.id_reserva);
    END IF;
  END LOOP;
  COMMIT;
END;
/


-- =====================================================================
-- 14. ESTADISTICAS: actualiza las estadisticas del optimizador para que
--     los planes de ejecucion (Entrega 3) reflejen el volumen real.
-- =====================================================================
BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER);
END;
/


-- =====================================================================
-- 15. VERIFICACION DEL VOLUMEN MINIMO
-- =====================================================================
SELECT 'MUNICIPIO' AS tabla, (SELECT COUNT(*) FROM municipio) AS filas, 12 AS minimo FROM dual
UNION ALL SELECT 'TIPO_ALOJAMIENTO',   (SELECT COUNT(*) FROM tipo_alojamiento),   4     FROM dual
UNION ALL SELECT 'ALOJAMIENTO',        (SELECT COUNT(*) FROM alojamiento),        60    FROM dual
UNION ALL SELECT 'HABITACION',         (SELECT COUNT(*) FROM habitacion),         400   FROM dual
UNION ALL SELECT 'TEMPORADA',          (SELECT COUNT(*) FROM temporada),          6     FROM dual
UNION ALL SELECT 'CALENDARIO',         (SELECT COUNT(*) FROM calendario),         (SELECT MAX(fecha_fin) - MIN(fecha_inicio) + 1 FROM temporada) FROM dual
UNION ALL SELECT 'TARIFA',             (SELECT COUNT(*) FROM tarifa),             (SELECT COUNT(*) FROM habitacion) * (SELECT COUNT(*) FROM temporada) FROM dual
UNION ALL SELECT 'CLIENTE',            (SELECT COUNT(*) FROM cliente),            3000  FROM dual
UNION ALL SELECT 'RESERVA',            (SELECT COUNT(*) FROM reserva),            25000 FROM dual
UNION ALL SELECT 'RESERVA_HABITACION', (SELECT COUNT(*) FROM reserva_habitacion), 25000 FROM dual
UNION ALL SELECT 'PAGO',               (SELECT COUNT(*) FROM pago),               25000 FROM dual
UNION ALL SELECT 'SERVICIO',           (SELECT COUNT(*) FROM servicio),           30    FROM dual
UNION ALL SELECT 'RESERVA_SERVICIO',   (SELECT COUNT(*) FROM reserva_servicio),   40000 FROM dual
UNION ALL SELECT 'RESENA',             (SELECT COUNT(*) FROM resena),             (SELECT CEIL(0.4 * COUNT(*)) FROM reserva WHERE estado = 'COMPLETADA') FROM dual
UNION ALL SELECT 'USUARIO_SISTEMA',    (SELECT COUNT(*) FROM usuario_sistema),    10    FROM dual;

-- Asimetria: reservas por municipio (deben ser muy distintas entre si)
SELECT m.nombre AS municipio, COUNT(*) AS reservas
  FROM reserva r
  JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
  JOIN municipio m   ON m.id_municipio   = a.id_municipio
 GROUP BY m.nombre
 ORDER BY reservas DESC;

-- Control de la regla L9: reservas activas solapadas en la misma habitacion (debe dar 0)
SELECT COUNT(*) AS solapes
  FROM reserva_habitacion x
  JOIN reserva rx ON rx.id_reserva = x.id_reserva
  JOIN reserva_habitacion y ON y.id_habitacion = x.id_habitacion
                           AND y.id_reserva_hab > x.id_reserva_hab
                           AND y.fecha_checkin  < x.fecha_checkout
                           AND x.fecha_checkin  < y.fecha_checkout
  JOIN reserva ry ON ry.id_reserva = y.id_reserva
 WHERE rx.estado <> 'CANCELADA'
   AND ry.estado <> 'CANCELADA';
