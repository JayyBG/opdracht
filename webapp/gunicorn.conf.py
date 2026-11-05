from logsetup import get_logger

bind = "0.0.0.0:5000"
workers = 1
threads = 8
# docker stop wacht 10 seconden; zorg dat we daarbinnen netjes afsluiten.
graceful_timeout = 5


def post_worker_init(worker):
    # Pas hier is de applicatie geladen en kan de webapp verzoeken afhandelen.
    get_logger().info("Application started")


def on_exit(server):
    get_logger().info("Application stopped")
