"""GridWatch 2030 – demonstratieomgeving: webapplicatie en REST API."""
import logging
import os
import random
import re
import time
from functools import wraps

import psycopg2
import psycopg2.extras
from flask import (Flask, abort, flash, g, jsonify, redirect, render_template,
                   request, session, url_for)
from werkzeug.exceptions import HTTPException
from werkzeug.security import check_password_hash, generate_password_hash

from logsetup import get_logger

log = get_logger()

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.environ.get("SECRET_KEY", "verander-mij-in-productie"),
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
)
app.json.sort_keys = False
app.json.ensure_ascii = False

DB_SETTINGS = dict(
    host=os.environ.get("DB_HOST", "database"),
    port=int(os.environ.get("DB_PORT", "5432")),
    dbname=os.environ.get("DB_NAME", "gridwatch"),
    user=os.environ.get("DB_USER", "gridwatch"),
    password=os.environ.get("DB_PASSWORD", "gridwatch"),
    connect_timeout=3,
)

ALERT_TYPES = ("storing", "onderhoud")
ALERT_LEVELS = ("laag", "middel", "hoog")


# --- Database -----------------------------------------------------------------

class DatabaseUnavailable(Exception):
    pass


def get_db():
    if "db" not in g:
        try:
            g.db = psycopg2.connect(**DB_SETTINGS, cursor_factory=psycopg2.extras.RealDictCursor)
        except psycopg2.OperationalError as exc:
            raise DatabaseUnavailable(" ".join(str(exc).split())) from exc
    return g.db


@app.teardown_appcontext
def close_db(exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def query(sql, params=(), one=False):
    with get_db().cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    if one:
        return rows[0] if rows else None
    return rows


def execute(sql, params=()):
    db = get_db()
    with db.cursor() as cur:
        cur.execute(sql, params)
    db.commit()


def seed_users():
    """Maak de standaardgebruikers aan (gehasht wachtwoord) als ze nog niet bestaan."""
    users = [
        ("admin", os.environ.get("ADMIN_PASSWORD", "GridWatch2030!"), "admin"),
        ("operator", os.environ.get("OPERATOR_PASSWORD", "Operator2030!"), "operator"),
    ]
    for _ in range(30):
        try:
            conn = psycopg2.connect(**DB_SETTINGS)
            break
        except psycopg2.OperationalError:
            time.sleep(1)
    else:
        log.error("Database connection failed during startup")
        return
    with conn, conn.cursor() as cur:
        for username, password, role in users:
            cur.execute(
                "INSERT INTO users (username, password_hash, role) VALUES (%s, %s, %s) "
                "ON CONFLICT (username) DO NOTHING",
                (username, generate_password_hash(password), role),
            )
    conn.close()


seed_users()


# --- Logging helpers ----------------------------------------------------------

def clean(value, limit=64):
    """Voorkom log-injectie: geen regeleinden of stuurtekens in logregels."""
    return re.sub(r"[\x00-\x1f\x7f]", "?", str(value))[:limit]


def client_ip():
    return request.remote_addr or "-"


def current_user():
    return session.get("user", "-")


def record(level, event_type, message):
    """Schrijf een gebeurtenis naar het logbestand en naar de events-tabel."""
    log.log(level, message)
    try:
        execute(
            "INSERT INTO events (niveau, type, beschrijving) VALUES (%s, %s, %s)",
            (logging.getLevelName(level), event_type, message),
        )
    except Exception:
        # Het logbestand is leidend; de database kan juist de storing zijn.
        if "db" in g:
            try:
                g.db.rollback()
            except Exception:
                pass


@app.before_request
def start_timer():
    g.start = time.perf_counter()


@app.after_request
def log_api_request(response):
    if request.path.startswith("/api/"):
        duration_ms = (time.perf_counter() - g.get("start", time.perf_counter())) * 1000
        level = logging.INFO if response.status_code < 400 else logging.WARNING
        log.log(level, f"{request.method} {clean(request.full_path.rstrip('?'), 200)} "
                       f"status={response.status_code} duration_ms={duration_ms:.0f} ip={client_ip()}")
    return response


# --- Foutafhandeling ----------------------------------------------------------

@app.errorhandler(DatabaseUnavailable)
def database_unavailable(exc):
    log.error(f"Database connection failed path={request.path} ip={client_ip()} detail={clean(exc, 200)}")
    if request.path.startswith("/api/"):
        return jsonify(error="database unavailable"), 503
    return render_template("error.html", title="Database niet bereikbaar",
                           message="De database reageert niet. Probeer het later opnieuw."), 503


@app.errorhandler(404)
def not_found(exc):
    if request.path.startswith("/api/"):
        return jsonify(error="not found"), 404
    return render_template("error.html", title="Niet gevonden",
                           message="Deze pagina bestaat niet."), 404


@app.errorhandler(Exception)
def unhandled_exception(exc):
    if isinstance(exc, HTTPException):
        return exc
    record(logging.ERROR, "application_error",
           f"{clean(exc, 200)} type={type(exc).__name__} path={request.path} "
           f"user={current_user()} ip={client_ip()}")
    if request.path.startswith("/api/"):
        return jsonify(error="internal server error"), 500
    return render_template("error.html", title="Er ging iets mis",
                           message=f"Applicatiefout: {exc}"), 500


# --- Authenticatie ------------------------------------------------------------

def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "user" not in session:
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapped


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        return render_template("login.html")

    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    user = query("SELECT * FROM users WHERE username = %s", (username,), one=True)

    if user and check_password_hash(user["password_hash"], password):
        session.clear()
        session["user"] = user["username"]
        session["role"] = user["role"]
        record(logging.INFO, "login_success", f"User {clean(username)} logged in ip={client_ip()}")
        return redirect(url_for("dashboard"))

    if user:
        record(logging.WARNING, "login_failed", f"Invalid password for user {clean(username)} ip={client_ip()}")
    else:
        record(logging.WARNING, "login_failed", f"Unknown user {clean(username)} ip={client_ip()}")
    flash("Onjuiste gebruikersnaam of wachtwoord.", "error")
    return render_template("login.html", username=username), 401


@app.route("/logout")
def logout():
    if "user" in session:
        record(logging.INFO, "logout", f"User {current_user()} logged out ip={client_ip()}")
    session.clear()
    return redirect(url_for("login"))


# --- Webpagina's --------------------------------------------------------------

def grid_health():
    counts = query(
        "SELECT COUNT(*) FILTER (WHERE status <> 'OFFLINE') AS online, "
        "       COUNT(*) FILTER (WHERE status = 'OFFLINE')  AS offline "
        "FROM stations", one=True)
    storingen = query(
        "SELECT COUNT(*) AS n FROM alerts WHERE type = 'storing' AND status = 'open'", one=True)["n"]
    if counts["offline"] == 0 and storingen == 0:
        status = "OK"
    elif counts["offline"] <= 1 and storingen <= 3:
        status = "WAARSCHUWING"
    else:
        status = "KRITIEK"
    return {
        "stations_online": counts["online"],
        "stations_offline": counts["offline"],
        "storingen": storingen,
        "status": status,
    }


@app.route("/")
@login_required
def dashboard():
    stations = query("SELECT * FROM stations ORDER BY naam")
    return render_template("dashboard.html", stations=stations, health=grid_health())


@app.route("/stations/<int:station_id>")
@login_required
def station_detail(station_id):
    station = query("SELECT * FROM stations WHERE id = %s", (station_id,), one=True)
    if station is None:
        abort(404)
    metingen = query(
        "SELECT * FROM sensor_data WHERE station_id = %s ORDER BY tijdstip DESC LIMIT 20", (station_id,))
    meldingen = query(
        "SELECT * FROM alerts WHERE station_id = %s ORDER BY tijdstip DESC", (station_id,))
    return render_template("station.html", station=station, metingen=metingen, meldingen=meldingen)


@app.route("/meldingen", methods=["GET", "POST"])
@login_required
def meldingen():
    stations = query("SELECT id, naam FROM stations ORDER BY naam")

    if request.method == "POST":
        station_id = request.form.get("station_id", type=int)
        alert_type = request.form.get("type", "")
        ernst = request.form.get("ernst", "")
        beschrijving = request.form.get("beschrijving", "").strip()

        valid_station = any(s["id"] == station_id for s in stations)
        if not valid_station or alert_type not in ALERT_TYPES or ernst not in ALERT_LEVELS \
                or not 3 <= len(beschrijving) <= 500:
            log.warning(f"Invalid form input on /meldingen user={current_user()} ip={client_ip()}")
            flash("Vul alle velden correct in (beschrijving 3–500 tekens).", "error")
            return redirect(url_for("meldingen"), code=303)

        execute(
            "INSERT INTO alerts (station_id, type, ernst, beschrijving, gemeld_door) "
            "VALUES (%s, %s, %s, %s, %s)",
            (station_id, alert_type, ernst, beschrijving, current_user()))
        record(logging.INFO, "alert_created",
               f"Alert created type={alert_type} ernst={ernst} station_id={station_id} "
               f"user={current_user()} ip={client_ip()}")
        flash("Melding opgeslagen.", "ok")
        return redirect(url_for("meldingen"), code=303)

    filter_type = request.args.get("type")
    if filter_type in ALERT_TYPES:
        alerts = query(
            "SELECT a.*, s.naam AS station FROM alerts a LEFT JOIN stations s ON s.id = a.station_id "
            "WHERE a.type = %s ORDER BY a.tijdstip DESC", (filter_type,))
    else:
        filter_type = None
        alerts = query(
            "SELECT a.*, s.naam AS station FROM alerts a LEFT JOIN stations s ON s.id = a.station_id "
            "ORDER BY a.tijdstip DESC")
    return render_template("meldingen.html", alerts=alerts, stations=stations,
                           filter_type=filter_type, types=ALERT_TYPES, levels=ALERT_LEVELS)


@app.route("/gebeurtenissen")
@login_required
def gebeurtenissen():
    events = query("SELECT * FROM events ORDER BY tijdstip DESC LIMIT 200")
    return render_template("gebeurtenissen.html", events=events)


# --- Testscenario's -----------------------------------------------------------

@app.route("/test")
@login_required
def test_page():
    return render_template("test.html")


@app.route("/test/error", methods=["POST"])
@login_required
def test_error():
    raise RuntimeError("Test exception generated")


@app.route("/test/load", methods=["POST"])
@login_required
def test_load():
    count = min(max(request.form.get("count", 1000, type=int) or 1000, 1), 20000)
    started = time.perf_counter()

    station_ids = [row["id"] for row in query("SELECT id FROM stations WHERE status <> 'OFFLINE'")]
    rows = [
        (random.choice(station_ids),
         round(random.uniform(50, 420), 1),
         round(random.uniform(15, 80), 1),
         round(random.choice((380, 220, 150, 110)) + random.uniform(-4, 4), 1))
        for _ in range(count)
    ]
    db = get_db()
    with db.cursor() as cur:
        psycopg2.extras.execute_values(
            cur,
            "INSERT INTO sensor_data (station_id, vermogen_mw, temperatuur, spanning_kv) VALUES %s",
            rows, page_size=500)
    db.commit()
    # Extra database- en CPU-belasting: statistieken over alle meetgegevens.
    totaal = query("SELECT COUNT(*) AS n, AVG(temperatuur) AS gem FROM sensor_data", one=True)

    duration_ms = (time.perf_counter() - started) * 1000
    record(logging.WARNING if count >= 5000 else logging.INFO, "load_generated",
           f"Generated {count} sensor records duration_ms={duration_ms:.0f} "
           f"user={current_user()} ip={client_ip()}")
    flash(f"{count} sensorrecords aangemaakt in {duration_ms:.0f} ms. "
          f"Totaal in database: {totaal['n']}.", "ok")
    return redirect(url_for("test_page"), code=303)


# --- REST API -----------------------------------------------------------------

def iso(value):
    return value.isoformat(timespec="seconds") if value else None


def station_json(row):
    return {
        "id": row["id"],
        "station": row["naam"].removeprefix("Station "),
        "locatie": row["locatie"],
        "vermogen_mw": row["vermogen_mw"],
        "temperatuur": row["temperatuur"],
        "status": row["status"],
    }


def alert_json(row):
    return {
        "id": row["id"],
        "station_id": row["station_id"],
        "station": row.get("station"),
        "tijdstip": iso(row["tijdstip"]),
        "type": row["type"],
        "ernst": row["ernst"],
        "beschrijving": row["beschrijving"],
        "status": row["status"],
    }


def sensor_json(row):
    return {
        "station_id": row["station_id"],
        "tijdstip": iso(row["tijdstip"]),
        "vermogen_mw": row["vermogen_mw"],
        "temperatuur": row["temperatuur"],
        "spanning_kv": row["spanning_kv"],
    }


@app.route("/api/stations")
def api_stations():
    return jsonify([station_json(s) for s in query("SELECT * FROM stations ORDER BY id")])


@app.route("/api/station/<int:station_id>")
def api_station(station_id):
    station = query("SELECT * FROM stations WHERE id = %s", (station_id,), one=True)
    if station is None:
        abort(404)
    laatste = query("SELECT * FROM sensor_data WHERE station_id = %s ORDER BY tijdstip DESC LIMIT 1",
                    (station_id,), one=True)
    open_alerts = query("SELECT * FROM alerts WHERE station_id = %s AND status = 'open' "
                        "ORDER BY tijdstip DESC", (station_id,))
    return jsonify({
        **station_json(station),
        "laatste_meting": sensor_json(laatste) if laatste else None,
        "open_meldingen": [alert_json(a) for a in open_alerts],
    })


@app.route("/api/alerts")
def api_alerts():
    sql = ("SELECT a.*, s.naam AS station FROM alerts a "
           "LEFT JOIN stations s ON s.id = a.station_id WHERE TRUE")
    params = []
    if request.args.get("type") in ALERT_TYPES:
        sql += " AND a.type = %s"
        params.append(request.args["type"])
    if request.args.get("status") in ("open", "gesloten"):
        sql += " AND a.status = %s"
        params.append(request.args["status"])
    sql += " ORDER BY a.tijdstip DESC"
    return jsonify([alert_json(a) for a in query(sql, params)])


@app.route("/api/sensor-data")
def api_sensor_data():
    limit = min(max(request.args.get("limit", 50, type=int) or 50, 1), 500)
    station_id = request.args.get("station_id", type=int)
    if station_id:
        rows = query("SELECT * FROM sensor_data WHERE station_id = %s ORDER BY tijdstip DESC LIMIT %s",
                     (station_id, limit))
    else:
        rows = query("SELECT * FROM sensor_data ORDER BY tijdstip DESC LIMIT %s", (limit,))
    return jsonify([sensor_json(r) for r in rows])


@app.route("/api/grid-health")
def api_grid_health():
    return jsonify(grid_health())


@app.route("/health")
def health():
    """Healthcheck voor Docker en monitoring. Wordt bewust niet gelogd."""
    try:
        query("SELECT 1 AS ok", one=True)
        return jsonify(status="ok", database="ok")
    except DatabaseUnavailable:
        return jsonify(status="degraded", database="unavailable"), 503
