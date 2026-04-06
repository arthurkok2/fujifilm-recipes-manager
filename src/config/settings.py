import os
from pathlib import Path

import structlog
from kombu import Queue

BASE_DIR = Path(__file__).resolve().parent.parent.parent


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def env_bool(name: str, default: str) -> bool:
    return env(name, default) in {"1", "true", "True"}


def env_int(name: str, default: str) -> int:
    return int(env(name, default))


def env_float(name: str, default: str) -> float:
    return float(env(name, default))


def env_path(name: str, default: str) -> Path:
    return Path(env(name, default))


SECRET_KEY = env("DJANGO_SECRET_KEY", "change-me-to-a-long-random-secret-key")
DEBUG = env_bool("DJANGO_DEBUG", "1")
ALLOWED_HOSTS = [h.strip() for h in env("DJANGO_ALLOWED_HOSTS", "*").split(",") if h.strip()]

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.auth",
    "src.data",
    "src.interfaces",
]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": env("POSTGRES_DB", "fujifilm_recipes"),
        "USER": env("POSTGRES_USER", "fujifilm_recipes"),
        "PASSWORD": env("POSTGRES_PASSWORD", "fujifilm_recipes"),
        "HOST": env("POSTGRES_HOST", "127.0.0.1"),
        "PORT": env("POSTGRES_PORT", "5432"),
    }
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

GALLERY_PAGE_SIZE = env_int("GALLERY_PAGE_SIZE", "24")
IMAGE_MAX_RATING = env_int("IMAGE_MAX_RATING", "5")
PTP_DEVICE = env("PTP_DEVICE", "src.domain.camera.ptp_usb_device.PTPUSBDevice")
CAMERA_VERIFY_WRITES = env_bool("CAMERA_VERIFY_WRITES", "1")

CAMERA_POST_READ_DELAY_S = env_float("CAMERA_POST_READ_DELAY_S", "0.05")
CAMERA_PRE_WRITE_DELAY_S = env_float("CAMERA_PRE_WRITE_DELAY_S", "0.05")
CAMERA_POST_WRITE_DELAY_S = env_float("CAMERA_POST_WRITE_DELAY_S", "0.05")
CAMERA_POST_CURSOR_DELAY_S = env_float("CAMERA_POST_CURSOR_DELAY_S", "0.05")
CAMERA_INTER_SLOT_DELAY_S = env_float("CAMERA_INTER_SLOT_DELAY_S", "0.05")
CAMERA_MAX_RETRIES = env_int("CAMERA_MAX_RETRIES", "3")
CAMERA_RETRY_BACKOFF_S = env_float("CAMERA_RETRY_BACKOFF_S", "0.15")

IMAGE_LIBRARY_ROOT = env_path("IMAGE_LIBRARY_ROOT", "/data/images")
THUMBNAIL_CACHE_DIR = env_path("THUMBNAIL_CACHE_DIR", str(BASE_DIR / "thumbnail_cache"))
LOG_DIR = env_path("LOG_DIR", str(BASE_DIR / "logs"))
LOG_DIR.mkdir(parents=True, exist_ok=True)

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
            ],
        },
    },
]

ROOT_URLCONF = "src.config.urls"

USE_TZ = True
TIME_ZONE = "UTC"

CELERY_BROKER_URL = env("CELERY_BROKER_URL", "amqp://guest:guest@localhost:5672//")
CELERY_RESULT_BACKEND = env("CELERY_RESULT_BACKEND", "rpc://")
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
PROCESS_IMAGE_QUEUE = env("PROCESS_IMAGE_QUEUE", "celery")
CELERY_TASK_DEFAULT_QUEUE = PROCESS_IMAGE_QUEUE
CELERY_TASK_QUEUES = (Queue(PROCESS_IMAGE_QUEUE),)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "console": {
            "()": structlog.stdlib.ProcessorFormatter,
            "processor": structlog.dev.ConsoleRenderer(),
        },
        "json": {
            "()": structlog.stdlib.ProcessorFormatter,
            "processor": structlog.processors.JSONRenderer(),
        },
    },
    "handlers": {
        "file": {
            "class": "logging.FileHandler",
            "filename": LOG_DIR / "events.jsonl",
            "formatter": "json",
        },
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "console",
        },
    },
    "loggers": {
        "events": {
            "handlers": ["file", "console"],
            "level": "INFO",
            "propagate": False,
        },
        "camera.events": {
            "handlers": ["file", "console"],
            "level": "INFO",
            "propagate": False,
        },
    },
}

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
    ],
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
)
