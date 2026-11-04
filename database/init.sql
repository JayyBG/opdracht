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
    naam        VARCHAR(100) NOT NULL,
    locatie     VARCHAR(100) NOT NULL,
    status      VARCHAR(20)  NOT NULL DEFAULT 'OK'
                CHECK (status IN ('OK', 'WAARSCHUWING', 'STORING', 'ONDERHOUD', 'OFFLINE')),
    vermogen_mw DOUBLE PRECISION,
    temperatuur DOUBLE PRECISION
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

INSERT INTO stations (naam, locatie, status, vermogen_mw, temperatuur) VALUES
    ('Station Arnhem',          'Arnhem, Gelderland',            'OK',           220, 34),
    ('Station Zwolle',          'Zwolle, Overijssel',            'OK',           180, 31),
    ('Station Eemshaven',       'Eemshaven, Groningen',          'ONDERHOUD',    310, 29),
    ('Station Maasvlakte',      'Rotterdam, Zuid-Holland',       'OK',           410, 36),
    ('Station Diemen',          'Diemen, Noord-Holland',         'OK',           265, 33),
    ('Station Geertruidenberg', 'Geertruidenberg, Noord-Brabant','WAARSCHUWING', 195, 58),
    ('Station Borssele',        'Borssele, Zeeland',             'OK',           300, 35),
    ('Station Hengelo',         'Hengelo, Overijssel',           'OK',           140, 30),
    ('Station Eindhoven',       'Eindhoven, Noord-Brabant',      'STORING',       90, 71),
    ('Station Krimpen',         'Krimpen aan den IJssel',        'OK',           240, 32),
    ('Station Lelystad',        'Lelystad, Flevoland',           'OK',           160, 28),
    ('Station Meeden',          'Meeden, Groningen',             'OFFLINE',        0, 18),
    ('Station Doetinchem',      'Doetinchem, Gelderland',        'OK',           120, 30);

INSERT INTO alerts (station_id, tijdstip, type, ernst, beschrijving, status, gemeld_door) VALUES
    (9,  now() - interval '2 hours',  'storing',   'hoog',   'Temperatuur transformator boven drempelwaarde (71 °C)', 'open',     'systeem'),
    (12, now() - interval '40 minutes','storing',  'hoog',   'Station niet bereikbaar, geen meetgegevens ontvangen',   'open',     'systeem'),
    (6,  now() - interval '1 day',    'storing',   'laag',   'Kortstondige spanningsdip gemeten',                      'gesloten', 'operator'),
    (3,  now() - interval '3 hours',  'onderhoud', 'middel', 'Gepland onderhoud schakelinstallatie',                   'open',     'admin'),
    (2,  now() - interval '5 hours',  'onderhoud', 'laag',   'Inspectie koelsysteem gepland',                          'open',     'operator');

-- 24 uur aan historische meetgegevens per station.
INSERT INTO sensor_data (station_id, tijdstip, vermogen_mw, temperatuur, spanning_kv)
SELECT s.id,
       now() - make_interval(hours => n),
       CASE WHEN s.status = 'OFFLINE' THEN 0
            ELSE round((s.vermogen_mw + (random() - 0.5) * 40)::numeric, 1)::double precision END,
       round((s.temperatuur + (random() - 0.5) * 6)::numeric, 1)::double precision,
       CASE WHEN s.status = 'OFFLINE' THEN 0
            ELSE round((380 + (random() - 0.5) * 8)::numeric, 1)::double precision END
FROM stations s, generate_series(1, 24) AS n;
