# Build stage: validate/compile the application before producing the runtime image.
FROM python:3.12.10-slim-bookworm AS builder

WORKDIR /build
COPY app.py ./
RUN python -m compileall -q app.py

# Runtime stage is distroless: no shell, package manager, or unused OS tools.
# The `nonroot` tag runs as UID/GID 65532; it is deliberately not `latest`.
FROM gcr.io/distroless/python3-debian13:nonroot

WORKDIR /app
COPY --from=builder --chown=65532:65532 /build/app.py ./app.py

USER nonroot:nonroot
EXPOSE 8080
CMD ["app.py"]
