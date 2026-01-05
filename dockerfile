FROM mirror.gcr.io/library/python:3.12

RUN pip install -e "python[all]"

ENV JAX_COMPILATION_CACHE_DIR=/tmp/jit_cache

RUN mkdir -p /tmp/jit_cache /tmp/models