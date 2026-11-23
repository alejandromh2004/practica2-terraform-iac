import io
import json
import os
import signal
import sys
import time
import urllib.request
from flask import Flask, jsonify, redirect, render_template, request, url_for
from minio import Minio
import psycopg2
import psycopg2.extras
import redis
from werkzeug.utils import secure_filename

# Salida limpia e inmediata ante SIGTERM (docker stop / terraform destroy)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

app = Flask(__name__)
UPTIME_START = time.time()

# Configuración de PostgreSQL (sin contraseñas por defecto en código)
DB_HOST = os.getenv("DB_HOST", "db")
DB_NAME = os.getenv("DB_NAME", "practica_db")
DB_USER = os.getenv("DB_USER", "usuario_ejemplo")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_PORT = os.getenv("DB_PORT", "5432")

# Configuración de Redis (solo PROD)
REDIS_HOST = os.getenv("REDIS_HOST", None)
REDIS_PORT = os.getenv("REDIS_PORT", "6379")

# Configuración de MinIO / SeaweedFS (Almacenamiento de objetos S3)
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "minio:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "")
MINIO_BUCKET = os.getenv("MINIO_BUCKET", "pokedex-static")
MINIO_PUBLIC_URL = os.getenv("MINIO_PUBLIC_URL", "http://localhost:9000")


def log_error(context, err):
    print(f"[ERROR] {context}: {err}", file=sys.stderr, flush=True)


def get_redis_client():
    return redis.Redis(
        host=REDIS_HOST,
        port=int(REDIS_PORT),
        socket_timeout=2,
        socket_connect_timeout=2,
        decode_responses=True,
    )


def get_minio_client():
    return Minio(
        MINIO_ENDPOINT,
        access_key=MINIO_ACCESS_KEY,
        secret_key=MINIO_SECRET_KEY,
        secure=False,
    )


def ensure_static_assets():
    """Sube un icono SVG estático al bucket S3 si no existe todavía."""
    try:
        client = get_minio_client()
        if not client.bucket_exists(MINIO_BUCKET):
            client.make_bucket(MINIO_BUCKET)
        try:
            client.stat_object(MINIO_BUCKET, "pokeball.svg")
        except Exception:
            svg_data = b"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="40" height="40">
              <circle cx="50" cy="50" r="45" fill="#fff" stroke="#0f172a" stroke-width="6"/>
              <path d="M5 50a45 45 0 0 1 90 0z" fill="#ef4444" stroke="#0f172a" stroke-width="6"/>
              <line x1="5" y1="50" x2="95" y2="50" stroke="#0f172a" stroke-width="6"/>
              <circle cx="50" cy="50" r="14" fill="#fff" stroke="#0f172a" stroke-width="6"/>
            </svg>"""
            client.put_object(
                MINIO_BUCKET,
                "pokeball.svg",
                io.BytesIO(svg_data),
                len(svg_data),
                content_type="image/svg+xml",
            )
    except Exception as e:
        log_error("ensure_static_assets", e)


def check_db_health():
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port=DB_PORT,
            connect_timeout=2,
        )
        conn.close()
        return True, "ONLINE"
    except Exception as e:
        log_error("check_db_health", e)
        return False, "OFFLINE"


def check_redis_health():
    if not REDIS_HOST:
        return False, "DESACTIVADO (DEV)"
    try:
        r = get_redis_client()
        r.ping()
        return True, "ONLINE"
    except Exception as e:
        log_error("check_redis_health", e)
        return False, "OFFLINE"


def check_minio_health():
    try:
        client = get_minio_client()
        if client.bucket_exists(MINIO_BUCKET):
            return True, "ONLINE (S3)"
        return False, "OFFLINE"
    except Exception as e:
        log_error("check_minio_health", e)
        return False, "OFFLINE"


def fetch_pokemon_from_db():
    conn = psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        port=DB_PORT,
        connect_timeout=2,
    )
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(
        "SELECT id, numero, nombre, tipo, hp, ataque, imagen_url FROM pokemon ORDER BY numero ASC;"
    )
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return [dict(r) for r in rows]


def get_container_metrics():
    pid = os.getpid()
    hostname = os.uname().nodename
    mem_mb = "N/A"
    try:
        with open("/proc/self/statm", "r") as f:
            pages = int(f.read().split()[0])
            mem_mb = f"{round((pages * 4096) / (1024 * 1024), 1)} MB"
    except Exception:
        pass
    uptime_sec = int(time.time() - UPTIME_START)
    return {
        "container_id": hostname[:16],
        "pid": pid,
        "mem_usage": mem_mb,
        "uptime": f"{uptime_sec}s",
    }


@app.route("/")
def index():
    entorno = "Producción (PRO)" if REDIS_HOST else "Desarrollo (DEV)"
    error_msg = request.args.get("error", "")
    ensure_static_assets()

    minio_ok, minio_status = check_minio_health()
    db_status = "ONLINE"
    redis_status = "DESACTIVADO (DEV)"

    pokemon_list = []
    fuente_datos = "Ninguna"
    cache_badge = "N/A"
    inicio = time.perf_counter()

    # 1. En PRO intentamos leer primero de Redis sin abrir conexión extra a PostgreSQL
    served_from_cache = False
    if REDIS_HOST:
        try:
            r = get_redis_client()
            datos_cache = r.get("cartas_pokemon")
            redis_status = "ONLINE"
            if datos_cache:
                pokemon_list = json.loads(datos_cache)
                fuente_datos = "Caché Redis (Memoria RAM ⚡)"
                cache_badge = "HIT"
                served_from_cache = True
        except Exception as e:
            log_error("redis_read", e)
            redis_status = "OFFLINE"

    # 2. Si no hubo HIT en caché (MISS o DEV), consultamos PostgreSQL protegidos contra race conditions
    if not served_from_cache:
        try:
            pokemon_list = fetch_pokemon_from_db()
            db_status = "ONLINE"
            if REDIS_HOST and redis_status == "ONLINE":
                try:
                    r = get_redis_client()
                    r.setex("cartas_pokemon", 30, json.dumps(pokemon_list))
                    fuente_datos = "PostgreSQL (Guardado en Redis por 30s)"
                    cache_badge = "MISS"
                except Exception as e:
                    log_error("redis_write", e)
                    fuente_datos = "PostgreSQL (Directo de BD)"
            else:
                fuente_datos = "PostgreSQL (Directo de BD)"
        except Exception as e:
            log_error("fetch_pokemon_from_db", e)
            db_status = "OFFLINE"
            fuente_datos = "Error al conectar con PostgreSQL"

    fin = time.perf_counter()
    tiempo_ms = round((fin - inicio) * 1000, 2)
    metrics = get_container_metrics()
    logo_url = f"{MINIO_PUBLIC_URL}/{MINIO_BUCKET}/pokeball.svg"

    return render_template(
        "index.html",
        entorno=entorno,
        error_msg=error_msg,
        db_status=db_status,
        redis_status=redis_status,
        minio_status=minio_status,
        logo_url=logo_url,
        pokemon_list=pokemon_list,
        fuente_datos=fuente_datos,
        tiempo_ms=tiempo_ms,
        cache_badge=cache_badge,
        metrics=metrics,
    )


@app.route("/agregar", methods=["POST"])
def agregar_pokemon():
    numero = request.form.get("numero", type=int)
    nombre = (request.form.get("nombre", type=str) or "").strip()
    tipo = (request.form.get("tipo", type=str) or "").strip()
    hp = request.form.get("hp", type=int)
    ataque = request.form.get("ataque", type=int)
    imagen_url = (request.form.get("imagen_url", type=str) or "").strip()
    imagen_file = request.files.get("imagen_file")

    # Validación explícita para evitar fallos silenciosos con VARCHAR(50)
    if not numero or not nombre or not tipo or hp is None or ataque is None:
        return redirect(url_for("index", error="Todos los campos obligatorios deben rellenarse."))
    if len(nombre) > 50 or len(tipo) > 50:
        return redirect(url_for("index", error="El nombre y el tipo no pueden superar los 50 caracteres."))

    client = get_minio_client()

    if imagen_file and imagen_file.filename:
        try:
            filename = f"{numero}_{secure_filename(imagen_file.filename)}"
            data = imagen_file.read()
            client.put_object(
                MINIO_BUCKET,
                filename,
                io.BytesIO(data),
                len(data),
                content_type=imagen_file.content_type or "application/octet-stream",
            )
            imagen_url = f"{MINIO_PUBLIC_URL}/{MINIO_BUCKET}/{filename}"
        except Exception as e:
            log_error("s3_upload", e)
            return redirect(url_for("index", error="No se pudo subir la imagen al almacenamiento S3."))
    elif not imagen_url:
        default_sprite = f"https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/{numero}.png"
        try:
            req = urllib.request.urlopen(default_sprite, timeout=4)
            data = req.read()
            filename = f"pokemon_{numero}.png"
            client.put_object(
                MINIO_BUCKET,
                filename,
                io.BytesIO(data),
                len(data),
                content_type="image/png",
            )
            imagen_url = f"{MINIO_PUBLIC_URL}/{MINIO_BUCKET}/{filename}"
        except Exception as e:
            log_error("s3_default_sprite", e)
            imagen_url = default_sprite

    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port=DB_PORT,
            connect_timeout=2,
        )
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO pokemon (numero, nombre, tipo, hp, ataque, imagen_url)
            VALUES (%s, %s, %s, %s, %s, %s);
            """,
            (numero, nombre, tipo, hp, ataque, imagen_url),
        )
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        log_error("insert_pokemon", e)
        return redirect(url_for("index", error="Error al guardar el Pokémon en PostgreSQL."))

    # Invalidación de caché protegida con socket_timeout para no colgarse si Redis cae
    if REDIS_HOST:
        try:
            r = get_redis_client()
            r.delete("cartas_pokemon")
        except Exception as e:
            log_error("redis_invalidate", e)

    return redirect(url_for("index"))


@app.route("/status")
@app.route("/health")
def status():
    db_ok, db_label = check_db_health()
    redis_ok, redis_label = check_redis_health()
    minio_ok, minio_label = check_minio_health()

    sistema_sano = db_ok and minio_ok and (redis_ok if REDIS_HOST else True)

    return (
        jsonify(
            {
                "status": "healthy" if sistema_sano else "degraded",
                "database": "healthy" if db_ok else "unhealthy",
                "database_label": db_label,
                "cache": (
                    "healthy"
                    if redis_ok
                    else ("disabled" if not REDIS_HOST else "unhealthy")
                ),
                "cache_label": redis_label,
                "storage_s3": "healthy" if minio_ok else "unhealthy",
                "storage_label": minio_label,
            }
        ),
        200 if sistema_sano else 503,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
