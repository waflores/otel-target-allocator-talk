docker run -p 4317:4317 -p 4318:4318 --rm -v $(pwd)/config/otel-collector-config.yaml:/etc/otelcol/config.yaml otel/opentelemetry-collector
