import io
import json
import os
import time
import urllib.request
from flask import Flask, jsonify, redirect, render_template, request, url_for
from minio import Minio
import psycopg2
import psycopg2.extras
import redis
from werkzeug.utils import secure_filename

app = Flask(__name__)
UPTIME_START = time.time()

# Configuración de PostgreSQL
DB_HOST = os.getenv("DB_HOST", "db")
DB_NAME = os.getenv("DB_NAME", "practica_db")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")

# Configuración de Redis (solo PROD)
REDIS_HOST = os.getenv("REDIS_HOST", None)
REDIS_PORT = os.getenv("REDIS_PORT", "6379")

# Configuración de MinIO (Almacenamiento de objetos S3)
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "minio:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "minioadmin123")
MINIO_BUCKET = os.getenv("MINIO_BUCKET", "pokedex-static")
MINIO_PUBLIC_URL = os.getenv("MINIO_PUBLIC_URL", "http://localhost:9000")


def get_minio_client():
    return Minio(
        MINIO_ENDPOINT,
        access_key=MINIO_ACCESS_KEY,
        secret_key=MINIO_SECRET_KEY,
        secure=False,
    )


def ensure_static_assets():
    """Sube un icono SVG estático al bucket de MinIO si no existe todavía."""
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
    except Exception:
        pass


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
        return False, f"OFFLINE ({str(e)})"


def check_redis_health():
    if not REDIS_HOST:
        return False, "DESACTIVADO (DEV)"
    try:
        r = redis.Redis(
            host=REDIS_HOST,
            port=int(REDIS_PORT),
            socket_timeout=2,
            decode_responses=True,
        )
        r.ping()
        return True, "ONLINE"
    except Exception as e:
        return False, f"OFFLINE ({str(e)})"


def check_minio_health():
    try:
        client = get_minio_client()
        if client.bucket_exists(MINIO_BUCKET):
            return True, "ONLINE (S3)"
        return False, "BUCKET NO ENCONTRADO"
    except Exception as e:
        return False, f"OFFLINE ({str(e)})"


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
    ensure_static_assets()

    db_ok, db_status = check_db_health()
    redis_ok, redis_status = check_redis_health()
    minio_ok, minio_status = check_minio_health()

    pokemon_list = []
    fuente_datos = "Ninguna"
    cache_badge = "N/A"
    inicio = time.perf_counter()

    if REDIS_HOST and redis_ok:
        try:
            r = redis.Redis(
                host=REDIS_HOST,
                port=int(REDIS_PORT),
                socket_timeout=2,
                decode_responses=True,
            )
            datos_cache = r.get("cartas_pokemon")
            if datos_cache:
                pokemon_list = json.loads(datos_cache)
                fuente_datos = "Caché Redis (Memoria RAM ⚡)"
                cache_badge = "HIT"
            elif db_ok:
                pokemon_list = fetch_pokemon_from_db()
                r.setex("cartas_pokemon", 30, json.dumps(pokemon_list))
                fuente_datos = "PostgreSQL (Guardado en Redis por 30s)"
                cache_badge = "MISS"
        except Exception:
            if db_ok:
                pokemon_list = fetch_pokemon_from_db()
                fuente_datos = "PostgreSQL (Fallback por fallo de caché)"
    elif db_ok:
        pokemon_list = fetch_pokemon_from_db()
        fuente_datos = "PostgreSQL (Directo de BD)"

    fin = time.perf_counter()
    tiempo_ms = round((fin - inicio) * 1000, 2)
    metrics = get_container_metrics()
    logo_url = f"{MINIO_PUBLIC_URL}/{MINIO_BUCKET}/pokeball.svg"

    return render_template(
        "index.html",
        entorno=entorno,
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
    nombre = request.form.get("nombre", type=str)
    tipo = request.form.get("tipo", type=str)
    hp = request.form.get("hp", type=int)
    ataque = request.form.get("ataque", type=int)
    imagen_url = request.form.get("imagen_url", type=str)
    imagen_file = request.files.get("imagen_file")

    client = get_minio_client()

    # 1. Si el usuario sube un archivo local, lo guardamos en MinIO S3
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
        except Exception:
            pass
    # 2. Si no sube archivo ni URL, descargamos el sprite oficial y lo almacenamos en MinIO S3
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
        except Exception:
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

        if REDIS_HOST:
            try:
                r = redis.Redis(host=REDIS_HOST, port=int(REDIS_PORT))
                r.delete("cartas_pokemon")
            except Exception:
                pass
    except Exception:
        pass

    return redirect(url_for("index"))


@app.route("/status")
@app.route("/health")
def status():
    db_ok, _ = check_db_health()
    redis_ok, _ = check_redis_health()
    minio_ok, _ = check_minio_health()

    sistema_sano = db_ok and minio_ok and (redis_ok if REDIS_HOST else True)

    return (
        jsonify(
            {
                "status": "healthy" if sistema_sano else "degraded",
                "database": "healthy" if db_ok else "unhealthy",
                "cache": (
                    "healthy"
                    if redis_ok
                    else ("disabled" if not REDIS_HOST else "unhealthy")
                ),
                "storage_s3": "healthy" if minio_ok else "unhealthy",
            }
        ),
        200 if sistema_sano else 503,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
