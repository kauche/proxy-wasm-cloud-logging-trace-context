# proxy-wasm-cloud-logging-trace-context

A [proxy-wasm](https://github.com/proxy-wasm/spec) compliant WebAssembly module for making proxies integrate with [Google Cloud Logging](https://cloud.google.com/logging/).

## Overview

In order to generate logs associated with [Google Cloud Trace](https://cloud.google.com/trace) for [Google Cloud Logging](https://cloud.google.com/logging/), we need to add a [`logging.googleapis.com/trace` field](https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#FIELDS.trace) to the log entries.

This [proxy-wasm](https://github.com/proxy-wasm/spec) compliant WebAssembly module helps proxies generate logs integrated with Cloud Logging and Cloud Trace by extracting the trace id from the `X-Cloud-Trace-Context` HTTP Header and populating `X-Cloud-Logging-Trace-Context` by using the extracted trace id. The populated `X-Cloud-Logging-Trace-Context` HTTP Header is formatted as `projects/<Your Google Cloud Project ID>/traces/<Trace ID>` and can be used to add a `logging.googleapis.com/trace` filed to logs.

## Usage

1. Download the latest WebAssembly module from the [release page](https://github.com/kauche/proxy-wasm-cloud-logging-trace-context/releases).

2. Configure the proxy to use the WebAssembly module and generate logs like below (this assumes [Envoy](https://www.envoyproxy.io/) as the proxy):

```yaml
access_log:
  name: log
  typed_config:
    '@type': type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
    log_format:
      json_format:
        status: '%RESPONSE_CODE%'
        message: access log
        severity: INFO
        component: envoy
        logging.googleapis.com/trace: '%REQ(x-cloud-logging-trace-context)%'
http_filters:
  - name: envoy.filters.http.wasm
    typed_config:
      '@type': type.googleapis.com/udpa.type.v1.TypedStruct
      type_url: type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
      value:
        config:
          vm_config:
            runtime: envoy.wasm.runtime.v8
            code:
              local:
                filename: /etc/envoy/proxy-wasm-cloud-logging-trace-context.wasm
          configuration:
            "@type": type.googleapis.com/google.protobuf.StringValue
            value: |
              {
                "project_id": "my-projectid"
              }
  - name: envoy.filters.http.router
    typed_config:
      '@type': type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```
