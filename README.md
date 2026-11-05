# GridWatch 2030 – demonstratieomgeving

Een Docker-omgeving voor het fictieve programma GridWatch 2030, over een betrouwbare en veilige energievoorziening. De omgeving bevat windparken, zonneparken, centrales, batterijopslag en hoogspanningsstations (fictieve gegevens). Je kunt er storingen, foutmeldingen en beveiligingsgebeurtenissen mee nabootsen. De omgeving maakt logs aan die het HBO-team (Cyber Security & Cloud) gebruikt voor monitoring en detectie.

Stack: **Python Flask + PostgreSQL + Docker Compose** (optie A uit de opdracht).

---

## 1. Installatieplan

### Vereisten
- Docker Desktop (of Docker Engine) met Docker Compose v2
- Poort **8080** vrij
- Voor de scenarioscripts: `bash` en `curl`. Op macOS en Linux zit dat er standaard in. Op Windows gebruik je Git Bash of WSL.

### Starten
```bash
docker compose up -d --build
```
Open daarna **http://localhost:8080**.

Bij de eerste start maakt de database automatisch de tabellen en voorbeelddata aan. Dat duurt ongeveer 10 seconden.

### Testaccounts
| Gebruiker | Wachtwoord | Rol |
|---|---|---|
| `admin` | `GridWatch2030!` | admin |
| `operator` | `Operator2030!` | operator |

Wachtwoorden wijzigen? Kopieer `.env.example` naar `.env`, pas de waarden aan en verwijder de database-volume (zie hieronder).

### Handige commando's
| Doel | Commando |
|---|---|
| Status van de containers | `docker compose ps` |
| Logbestand live volgen | `tail -f logs/app.log` |
| Logs van een container | `docker logs -f webapp` / `docker logs -f database` |
| Stoppen | `docker compose down` |
| Volledig resetten (database leeg + opnieuw gevuld) | `docker compose down -v && docker compose up -d --build` |

---

## 2. Overzicht van containers

```
 browser / scripts / monitoring
            │  http://localhost:8080
            ▼
 ┌──────────────────────────┐      ┌──────────────────────────┐
 │ webapp                   │      │ database                 │
 │ Flask + Gunicorn         │─────▶│ PostgreSQL 16            │
 │ website + REST API       │ 5432 │ users, stations, alerts, │
 │ schrijft logs/app.log    │      │ sensor_data, events      │
 └──────────────────────────┘      └──────────────────────────┘
```

| Container | Image | Poort | Functie | Healthcheck | Logs |
|---|---|---|---|---|---|
| `webapp` | eigen build (`./webapp`) | 8080 → 5000 | Website, REST API, logging | `GET /health` elke 10 s | `logs/app.log` + `docker logs webapp` |
| `database` | `postgres:16-alpine` | 5432 (alleen intern) | Opslag van gebruikers en applicatiedata | `pg_isready` elke 5 s | `docker logs database` |

Beide containers hebben `restart: unless-stopped`. Als je een container met de hand stopt (`docker stop`), blijft hij uit tot je hem zelf weer start.

### Website
| Pagina | Wat je er kunt doen |
|---|---|
| `/login` | Inloggen |
| `/` | Dashboard: netstatus, opgewekt vermogen, duurzaam aandeel en overzicht van alle installaties |
| `/stations/<id>` | Details, grafieken, meldingen en de laatste metingen van één installatie |
| `/meldingen` | Onderhoudsmeldingen en storingen bekijken, en via een **formulier** een nieuwe melding invullen |
| `/meldingen?type=storing` | Storingenoverzicht |
| `/gebeurtenissen` | De laatste 200 gebeurtenissen uit de `events`-tabel, te filteren op INFO, WARN of ERROR |
| `/test` | Knoppen voor de testscenario's |

### REST API
De API heeft geen login nodig: het is een interne testomgeving. Alle antwoorden zijn JSON.

| Endpoint | Beschrijving |
|---|---|
| `GET /api/stations` | Alle installaties (energievoorzieningen) |
| `GET /api/station/<id>` | Eén installatie, met de laatste meting en open meldingen |
| `GET /api/alerts` | Meldingen. Filters: `?type=storing\|onderhoud`, `?status=open\|gesloten` |
| `GET /api/sensor-data` | Meetgegevens. Filters: `?station_id=1`, `?limit=50` (max 500) |
| `GET /api/grid-health` | Samenvatting van het net (de bonusopdracht) |
| `GET /health` | Healthcheck van de webapp en de database (wordt niet gelogd) |

Voorbeeld:
```bash
curl http://localhost:8080/api/grid-health
# {"stations_online": 12, "stations_offline": 1, "storingen": 2, "status": "WAARSCHUWING"}
```

### Database
| Tabel | Kolommen |
|---|---|
| `users` | id, username, password_hash, role |
| `stations` | id, naam, soort, locatie, status, capaciteit_mw, aansluiting_kv, vermogen_mw, temperatuur |
| `alerts` | id, station_id, tijdstip, type, ernst, beschrijving, status, gemeld_door |
| `sensor_data` | id, station_id, tijdstip, vermogen_mw, temperatuur, spanning_kv |
| `events` | id, tijdstip, niveau, type, beschrijving |

De tabel `stations` bevat de energievoorzieningen. `soort` is een van: Windpark, Windpark op zee, Zonnepark, Gascentrale, Biomassacentrale, Batterijopslag of Hoogspanningsstation. De naam `stations` volgt de API-endpoints uit de opdracht.

Wachtwoorden worden gehasht opgeslagen. Het schema en de voorbeelddata staan in `database/init.sql`.

---

## 3. Logging

Elke gebeurtenis is **één regel** in `logs/app.log`. Dezelfde regels gaan ook naar stdout, dus je ziet ze ook met `docker logs webapp`. Het formaat is:

```
JJJJ-MM-DD UU:MM:SS NIVEAU bericht sleutel=waarde ...
```

| Gebeurtenis | Niveau | Voorbeeldregel | Ook in `events`-tabel |
|---|---|---|---|
| Applicatie gestart | INFO | `2026-11-04 10:23:11 INFO Application started` | nee |
| Applicatie gestopt | INFO | `2026-11-04 10:23:43 INFO Application stopped` | nee |
| Succesvolle login | INFO | `INFO User admin logged in ip=172.20.0.1` | ja (`login_success`) |
| Mislukte login (fout wachtwoord) | WARN | `WARN Invalid password for user admin ip=172.20.0.1` | ja (`login_failed`) |
| Mislukte login (onbekende gebruiker) | WARN | `WARN Unknown user bob ip=172.20.0.1` | ja (`login_failed`) |
| Uitloggen | INFO | `INFO User admin logged out ip=172.20.0.1` | ja (`logout`) |
| API-verzoek | INFO / WARN (≥ 400) | `INFO GET /api/stations status=200 duration_ms=5 ip=172.20.0.1` | nee |
| Applicatiefout | ERROR | `ERROR Test exception generated type=RuntimeError path=/test/error user=admin ip=…` | ja (`application_error`) |
| Database onbereikbaar | ERROR | `ERROR Database connection failed path=/api/stations ip=… detail=…` | nee (de database is dan weg) |
| Melding aangemaakt | INFO | `INFO Alert created type=storing ernst=hoog station_id=1 user=admin ip=…` | ja (`alert_created`) |
| Ongeldige formulierinvoer | WARN | `WARN Invalid form input on /meldingen user=admin ip=…` | nee |
| Belasting gegenereerd | INFO / WARN (≥ 5000) | `INFO Generated 1000 sensor records duration_ms=18 user=admin ip=…` | ja (`load_generated`) |

Gebruikersinvoer wordt ontdaan van regeleinden en stuurtekens voordat hij in het log komt. Zo kun je geen nep-logregels injecteren.

---

## 4. Testscenario's

Je kunt elk scenario uitvoeren via de website (pagina **Testscenario's**) of met een script in `scripts/`. De scripts gebruiken standaard `http://localhost:8080` en het `admin`-account. Je kunt dat aanpassen met `BASE_URL`, `GW_USER` en `GW_PASSWORD`.

| # | Scenario | Uitvoeren | Verwacht resultaat in `logs/app.log` |
|---|---|---|---|
| 1 | **Inloggen** (onbekende gebruiker → fout wachtwoord → goed) | Knop op de testpagina, of `./scripts/scenario1-login-succes.sh` | `WARN Unknown user adminx`, `WARN Invalid password for user admin`, `INFO User admin logged in` |
| 2 | **Meerdere foute wachtwoorden** (brute force) | Knop op de testpagina (15 pogingen), of `./scripts/scenario2-foute-logins.sh [aantal]` (standaard 15; probeert `welkom123`, `test123`, `admin123`, …) | Per poging een regel `WARN Invalid password for user admin`. Er is bewust **geen** account-lockout, zodat het HBO-team detectie kan bouwen. |
| 3 | **Veel API-aanvragen in korte tijd** | Knop *Start API-verkeer*, of `./scripts/scenario3-api-verkeer.sh [aantal] [endpoint]` (standaard 50× `/api/stations`) | 50 regels `INFO GET /api/stations status=200` binnen enkele seconden |
| 4 | **Applicatiefout** | Knop *Genereer foutmelding*, of `./scripts/scenario4-applicatiefout.sh` | `ERROR Test exception generated type=RuntimeError …`. De gebruiker ziet een foutpagina (HTTP 500). |
| 5 | **Container handmatig gestopt** | Knoppen op de testpagina (database 30 s stoppen, database starten, webapp herstarten), `docker stop webapp` (en later `docker start webapp`), of `./scripts/scenario5-containeruitval.sh [container] [seconden]` | Webapp: `INFO Application stopped`, na de herstart `INFO Application started`. De healthcheck faalt tijdens de uitval. |
| 5b | **Database valt uit** | `./scripts/scenario5-containeruitval.sh database 30` | Bij elk verzoek `ERROR Database connection failed`. De API geeft HTTP 503 en `/health` meldt `degraded`. |
| 6 | **Hoge belasting** | Knop *Genereer sensorrecords*, of `./scripts/scenario6-hoge-belasting.sh [aantal]` (max 20000) | `INFO Generated 1000 sensor records duration_ms=…`. Dit geeft ook database-activiteit en CPU-gebruik. |

Alle scenario's zijn veilig en herhaalbaar. Ze werken alleen tegen deze lokale omgeving. **Voer ze nooit uit op echte systemen.**

---

## 5. Bewuste keuzes (input voor het HBO-team)
Deze omgeving is bedoeld om te testen en te monitoren. Een paar dingen zijn daarom expres eenvoudig gehouden:
- Er is geen account-lockout en geen rate limiting. Daardoor zijn brute-force- en verkeerspieken zichtbaar in de logs.
- De API heeft geen authenticatie.
- Er is geen HTTPS. Alles draait lokaal.
- Er is geen CSRF-token. De sessiecookie is wel `HttpOnly` en `SameSite=Lax`.

---

## 6. Problemen oplossen
- **Docker-logs of -knoppen op de testpagina geven een rechtenfout**: de webapp zit niet in de groep van de Docker-socket. Dat nummer verschilt per computer. Vraag het op met het commando hieronder, zet het als `DOCKER_GID=<nummer>` in `.env` en voer `docker compose up -d` uit.
  ```bash
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock alpine stat -c %g /var/run/docker.sock
  ```
- **Poort 8080 is al in gebruik**: verander in `docker-compose.yml` de regel `"8080:5000"` in bijvoorbeeld `"8081:5000"`.
- **Container `webapp` of `database` bestaat al**: verwijder de oude container met `docker rm -f webapp database`.
- **Linux: `Permission denied` op `logs/app.log`**: de webapp draait als gebruiker met uid 1000. Los het op met `sudo chown 1000 logs`.
- **Nieuwe wachtwoorden of `init.sql` worden niet gebruikt**: de database wordt maar één keer gevuld. Gebruik `docker compose down -v` om opnieuw te beginnen.

## Mappenstructuur
```
docker-compose.yml        Beide containers
.env.example              Optionele instellingen (wachtwoorden, secret key)
database/init.sql         Databaseschema + voorbeelddata
webapp/
  app.py                  Website, REST API en logging
  logsetup.py             Logformaat (bestand + stdout)
  gunicorn.conf.py        Webserver + start/stop-logregels
  templates/, static/     HTML en CSS
scripts/                  Scenarioscripts (bash + curl)
logs/                     app.log verschijnt hier na de start
```
