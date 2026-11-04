"""Gedeelde logconfiguratie: één regel per gebeurtenis, naar logbestand én stdout.

Formaat: 2026-04-01 09:14:22 INFO User admin logged in ip=172.18.0.1
"""
import logging
import logging.handlers
import os
import sys

LOG_FILE = os.environ.get("LOG_FILE", "/app/logs/app.log")
FORMAT = "%(asctime)s %(levelname)s %(message)s"
DATEFMT = "%Y-%m-%d %H:%M:%S"


def get_logger():
    logging.addLevelName(logging.WARNING, "WARN")
    logger = logging.getLogger("gridwatch")
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        logger.propagate = False
        formatter = logging.Formatter(FORMAT, DATEFMT)
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        handlers = [
            # WatchedFileHandler blijft werken als het bestand wordt geroteerd of verwijderd.
            logging.handlers.WatchedFileHandler(LOG_FILE),
            logging.StreamHandler(sys.stdout),
        ]
        for handler in handlers:
            handler.setFormatter(formatter)
            logger.addHandler(handler)
    return logger
