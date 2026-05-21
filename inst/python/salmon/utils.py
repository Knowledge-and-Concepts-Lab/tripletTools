import logging
import os


def get_logger(name):
    """Minimal logger: stream only, no file I/O, no external dependencies."""
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger  # already configured

    DEBUG = int(os.environ.get("SALMON_DEBUG", "0"))
    level = logging.DEBUG if DEBUG else logging.WARNING

    handler = logging.StreamHandler()
    handler.setLevel(level)
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(name)s %(levelname)s: %(message)s")
    )
    logger.addHandler(handler)
    logger.setLevel(level)
    return logger
