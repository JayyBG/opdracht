-- GridWatch 2030 – databaseschema en voorbeelddata.
-- Wordt alleen uitgevoerd bij de eerste start (lege database-volume).
-- Gebruikers worden door de webapp aangemaakt, zodat wachtwoorden gehasht worden opgeslagen.

CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50)  UNIQUE NOT NULL,
    password_hash TEXT         NOT NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'operator'
);

CREATE TABLE stations (
    id          SERIAL PRIMARY KEY,
    naam          VARCHAR(100) NOT NULL,
    soort         VARCHAR(40)  NOT NULL
                  CHECK (soort IN ('Windpark', 'Windpark op zee', 'Zonnepark', 'Gascentrale',
                                   'Biomassacentrale', 'Batterijopslag', 'Hoogspanningsstation')),
    locatie       VARCHAR(100) NOT NULL,
    status        VARCHAR(20)  NOT NULL DEFAULT 'OK'
                  CHECK (status IN ('OK', 'WAARSCHUWING', 'STORING', 'ONDERHOUD', 'OFFLINE')),
    capaciteit_mw DOUBLE PRECISION NOT NULL,
    aansluiting_kv INT          NOT NULL,
    vermogen_mw   DOUBLE PRECISION,
    temperatuur   DOUBLE PRECISION
);

CREATE TABLE alerts (
    id           SERIAL PRIMARY KEY,
    station_id   INT REFERENCES stations(id),
    tijdstip     TIMESTAMPTZ NOT NULL DEFAULT now(),
    type         VARCHAR(20) NOT NULL CHECK (type IN ('storing', 'onderhoud')),
    ernst        VARCHAR(10) NOT NULL DEFAULT 'middel' CHECK (ernst IN ('laag', 'middel', 'hoog')),
    beschrijving TEXT        NOT NULL,
    status       VARCHAR(10) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'gesloten')),
    gemeld_door  VARCHAR(50)
);

CREATE TABLE sensor_data (
    id          BIGSERIAL PRIMARY KEY,
    station_id  INT REFERENCES stations(id),
    tijdstip    TIMESTAMPTZ NOT NULL DEFAULT now(),
    vermogen_mw DOUBLE PRECISION,
    temperatuur DOUBLE PRECISION,
    spanning_kv DOUBLE PRECISION
);
CREATE INDEX sensor_data_station_tijd ON sensor_data (station_id, tijdstip DESC);

CREATE TABLE events (
    id           BIGSERIAL PRIMARY KEY,
    tijdstip     TIMESTAMPTZ NOT NULL DEFAULT now(),
    niveau       VARCHAR(10) NOT NULL,
    type         VARCHAR(50) NOT NULL,
    beschrijving TEXT        NOT NULL
);

-- Energievoorzieningen (fictieve gegevens). De tabel heet 'stations' zodat de API
-- de endpoints uit de opdracht volgt (/api/stations, /api/station/<id>).
INSERT INTO stations (naam, soort, locatie, status, capaciteit_mw, aansluiting_kv, vermogen_mw, temperatuur) VALUES
    ('Windpark Eemshaven',              'Windpark',             'Eemshaven, Groningen',          'OK',           300,  220, 215, 31),
    ('Zonnepark Midden-Groningen',      'Zonnepark',            'Midden-Groningen, Groningen',   'OK',           110,  110,  64, 38),
    ('Windpark Borssele',               'Windpark op zee',      'Noordzee, voor de kust van Zeeland', 'ONDERHOUD', 750, 380,   0, 22),
    ('Gascentrale Maasvlakte',          'Gascentrale',          'Maasvlakte, Zuid-Holland',      'OK',           800,  380, 410, 46),
    ('Hoogspanningsstation Diemen',     'Hoogspanningsstation', 'Diemen, Noord-Holland',         'OK',          1500,  380, 640, 33),
    ('Batterijopslag Vlissingen',       'Batterijopslag',       'Vlissingen, Zeeland',           'WAARSCHUWING',  50,  150,  18, 58),
    ('Biomassacentrale Geertruidenberg','Biomassacentrale',     'Geertruidenberg, Noord-Brabant','OK',           250,  150, 160, 44),
    ('Windpark Zeewolde',               'Windpark',             'Zeewolde, Flevoland',           'OK',           320,  150, 240, 30),
    ('Hoogspanningsstation Eindhoven',  'Hoogspanningsstation', 'Eindhoven, Noord-Brabant',      'STORING',      900,  380,  90, 71),
    ('Zonnepark Hengelo',               'Zonnepark',            'Hengelo, Overijssel',           'OK',            60,  110,  41, 36),
    ('Hoogspanningsstation Krimpen',    'Hoogspanningsstation', 'Krimpen aan den IJssel, Zuid-Holland', 'OK',  1200,  380, 520, 32),
    ('Hoogspanningsstation Meeden',     'Hoogspanningsstation', 'Meeden, Groningen',             'OFFLINE',     1000,  380,   0, 18),
    ('Windpark Wieringermeer',          'Windpark',             'Wieringermeer, Noord-Holland',  'OK',           300,  150, 180, 29);

INSERT INTO alerts (station_id, tijdstip, type, ernst, beschrijving, status, gemeld_door) VALUES
    (9,  now() - interval '2 hours',   'storing',   'hoog',   'Temperatuur transformator boven drempelwaarde (71 °C)',          'open',     'systeem'),
    (12, now() - interval '40 minutes','storing',   'hoog',   'Installatie niet bereikbaar, geen meetgegevens ontvangen',        'open',     'systeem'),
    (6,  now() - interval '1 day',     'storing',   'laag',   'Batterijtemperatuur kortstondig boven 55 °C, vermogen beperkt',   'gesloten', 'operator'),
    (3,  now() - interval '3 hours',   'onderhoud', 'middel', 'Gepland onderhoud aan de exportkabel, park tijdelijk uit bedrijf','open',     'admin'),
    (2,  now() - interval '5 hours',   'onderhoud', 'laag',   'Inspectie van de omvormers gepland',                              'open',     'operator');

-- 24 uur aan historische meetgegevens per installatie.
INSERT INTO sensor_data (station_id, tijdstip, vermogen_mw, temperatuur, spanning_kv)
SELECT s.id,
       now() - make_interval(hours => n),
       CASE WHEN s.status IN ('OFFLINE', 'ONDERHOUD') THEN 0
            ELSE round(LEAST(s.capaciteit_mw, s.vermogen_mw * (0.85 + random() * 0.3))::numeric, 1)::double precision END,
       round((s.temperatuur + (random() - 0.5) * 6)::numeric, 1)::double precision,
       CASE WHEN s.status IN ('OFFLINE', 'ONDERHOUD') THEN 0
            ELSE round((s.aansluiting_kv + (random() - 0.5) * s.aansluiting_kv * 0.02)::numeric, 1)::double precision END
FROM stations s, generate_series(1, 24) AS n;
