# -*- coding: utf-8 -*-
#
# TODO (team): this file replaces the upstream docker/config.py, which we removed
# together with the rest of Taiga's own Docker tooling.
#
# Two things are pending:
#
# 1. Override here every setting that changes per environment, reading the values
#    from environment variables (os.getenv) instead of hardcoding them: DATABASES,
#    SECRET_KEY, TAIGA_SITES_SCHEME / TAIGA_SITES_DOMAIN, CELERY_BROKER_URL,
#    EVENTS_PUSH_BACKEND and its options, email, MEDIA_ROOT / STATIC_ROOT, DEBUG.
#    settings/config.py.prod.example and the upstream docker/config.py
#    (https://github.com/taigaio/taiga-back/blob/main/docker/config.py) are good
#    starting points.
#
# 2. Make Django load this module by setting, wherever the backend runs
#    (Dockerfile, entrypoint, Kubernetes manifest, ...):
#
#        DJANGO_SETTINGS_MODULE=settings.config
#
#    Without it manage.py, taiga/wsgi.py and taiga/celery.py fall back to
#    "settings.common" and this file is silently ignored.

from .common import *   # noqa, pylint: disable=unused-wildcard-import
