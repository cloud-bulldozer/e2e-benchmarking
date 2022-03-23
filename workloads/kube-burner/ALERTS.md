# Alerts

Syntax reference in kube-burner documentation: https://kube-burner.readthedocs.io/en/latest/alerting/

Some of the alerts defined use the [avg_over_time function](https://prometheus.io/docs/prometheus/latest/querying/functions/#aggregation_over_time) to prevent firing when the metric suffers isolated spikes.
